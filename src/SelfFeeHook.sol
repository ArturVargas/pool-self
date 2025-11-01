// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

// Self
import {SelfVerificationRoot} from "@selfxyz/contracts/contracts/abstract/SelfVerificationRoot.sol";
import {ISelfVerificationRoot} from "@selfxyz/contracts/contracts/interfaces/ISelfVerificationRoot.sol";
import {SelfUtils} from "@selfxyz/contracts/contracts/libraries/SelfUtils.sol";
import {SelfStructs} from "@selfxyz/contracts/contracts/libraries/SelfStructs.sol";
import {IIdentityVerificationHubV2} from "@selfxyz/contracts/contracts/interfaces/IIdentityVerificationHubV2.sol";

/// @title SelfFeeHook
/// @notice Uniswap v4 hook that reduces fees if the user presents a valid Self proof
contract SelfFeeHook is BaseHook, SelfVerificationRoot {
    using PoolIdLibrary for PoolKey;
    
    uint24 public constant BASE_FEE = 10000; // 1%
    uint24 public constant DISCOUNT_FEE = 3000; // 0.3%

    bytes32 public verificationConfigId;

    event HookSwapMetrics(
        bytes32 indexed poolId, // hash del PoolKey (no revelas tokens)
        bool verified,
        uint24 appliedFeeBps,
        uint256 notionalAmount,
        uint256 feeApplied,
        uint256 timestamp
    );

    // Flag temporal para rastrear si la última verificación fue exitosa
    // Se resetea antes de cada intento de verificación
    bool private lastVerificationStatus;

    constructor(
        IPoolManager _poolManager,
        address identityVerificationHubV2Address,
        string memory scope,
        SelfUtils.UnformattedVerificationConfigV2 memory _verificationConfig
    ) BaseHook(_poolManager) SelfVerificationRoot(identityVerificationHubV2Address, scope) {
        verificationConfigId = IIdentityVerificationHubV2(identityVerificationHubV2Address)
            .setVerificationConfigV2(SelfUtils.formatVerificationConfigV2(_verificationConfig));
    }

    // === Hooks.Permissions ===
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            beforeDonate: false,
            afterDonate: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // === Self overrides ===

    function getConfigId(
        bytes32, /* destinationChainId */
        bytes32, /* userIdentifier */
        bytes memory /* userDefinedData */
    )
        public
        view
        override
        returns (bytes32)
    {
        return verificationConfigId;
    }

    // === Self overrides ===

    /// @dev llamado automáticamente por SelfVerificationRoot cuando la prueba es válida
    function customVerificationHook(
        ISelfVerificationRoot.GenericDiscloseOutputV2 memory, /*output*/
        bytes memory /*userData*/
    )
        internal
        override
    {
        // No escribimos nada persistente (evitamos storage para gas)
        lastVerificationStatus = true;
    }

    // === Hook principal ===
    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata data)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint24 feeToApply = BASE_FEE;
        bool verified = false;

        // Try Self verification if the user sent data
        if (data.length > 0) {
            verified = _trySelfDisclose(data);
            if (verified) {
                feeToApply = DISCOUNT_FEE;
            }
        }

        // Convert calldata key to memory to use in toId
        PoolKey memory keyMem = key;
        emit HookSwapMetrics(
            PoolId.unwrap(keyMem.toId()),
            verified,
            feeToApply,
            _getNotional(params),
            _calcFee(params, feeToApply),
            block.timestamp
        );

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, feeToApply);
    }

    /// @dev Encapsulates the call to discloseV2 without reverting the swap
    /// @param userData ABI-encoded as tuple (bytes proofPayload, bytes userContextData)
    function _trySelfDisclose(bytes calldata userData) internal returns (bool) {
        // Reset the temporal state
        lastVerificationStatus = false;

        try this.discloseV2(userData) {
            // If it doesn't revert and the internal hook marked true
            return lastVerificationStatus;
        } catch {
            return false;
        }
    }

    /**
     * @notice External helper function that decodes and verifies the Self proof
     * @dev Decodes userData as (bytes proofPayload, bytes userContextData) and calls verifySelfProof
     * @param userData ABI-encoded as tuple (bytes, bytes)
     */
    function discloseV2(bytes calldata userData) external {
        require(msg.sender == address(this), "Internal only");

        // Decodes as tuple (bytes proofPayload, bytes userContextData)
        (bytes memory proofPayload, bytes memory userContextData) = abi.decode(userData, (bytes, bytes));

        // Need to convert from memory to calldata for verifySelfProof
        // Make an external call to ourselves with the data in calldata
        bytes memory callData =
            abi.encodeWithSelector(this.verifySelfProofInternal.selector, proofPayload, userContextData);

        (bool success,) = address(this).delegatecall(callData);
        require(success, "Verification call failed");
    }

    /**
     * @notice Internal function that calls verifySelfProof with data in memory
     * @dev Converts memory to calldata using a different approach
     */
    function verifySelfProofInternal(bytes memory proofPayload, bytes memory userContextData) external {
        require(msg.sender == address(this), "Internal only");

        // Since verifySelfProof requires calldata, we need to replicate its logic
        // but accepting memory
        _verifySelfProofMemory(proofPayload, userContextData);
    }

    /**
     * @notice Internal function to verify with data in memory
     * @dev Replicates the logic of verifySelfProof but accepts memory
     */
    function _verifySelfProofMemory(bytes memory proofPayload, bytes memory userContextData) internal {
        // Replicates the logic of verifySelfProof but with memory
        if (proofPayload.length < 32 || userContextData.length < 64) {
            revert InvalidDataFormat();
        }

        // Extracts attestationId (first 32 bytes)
        bytes32 attestationId;
        assembly {
            attestationId := mload(add(proofPayload, 32))
        }

        // Extracts data from userContextData
        bytes32 destinationChainId;
        bytes32 userIdentifier;
        bytes memory userDefinedData;

        assembly {
            destinationChainId := mload(add(userContextData, 32))
            userIdentifier := mload(add(userContextData, 64))
        }

        // If there are additional data after the first 64 bytes
        if (userContextData.length > 64) {
            userDefinedData = new bytes(userContextData.length - 64);
            for (uint256 i = 0; i < userDefinedData.length; i++) {
                userDefinedData[i] = userContextData[i + 64];
            }
        }

        bytes32 configId = getConfigId(destinationChainId, userIdentifier, userDefinedData);

        // Prepares baseVerificationInput
        bytes memory baseVerificationInput = abi.encodePacked(
            uint8(2), // CONTRACT_VERSION
            bytes31(0),
            scope(),
            proofPayload
        );

        // Calls the hub directly (synchronous, will trigger onVerificationSuccess if successful)
        _identityVerificationHubV2.verify(baseVerificationInput, bytes.concat(configId, userContextData));
    }

    function _getNotional(SwapParams calldata params) internal pure returns (uint256) {
        int256 amountSpecified = params.amountSpecified;
        return uint256(amountSpecified > 0 ? amountSpecified : -amountSpecified);
    }

    function _calcFee(SwapParams calldata params, uint24 feeBps) internal pure returns (uint256) {
        uint256 notional = _getNotional(params);
        return (notional * uint256(feeBps)) / 10000; // feeBps está en basis points (10000 = 100%)
    }
}
