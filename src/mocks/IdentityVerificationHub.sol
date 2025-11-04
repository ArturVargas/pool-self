// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IIdentityVerificationHubV2 } from "@selfxyz/contracts/contracts/interfaces/IIdentityVerificationHubV2.sol";
import { IRegisterCircuitVerifier } from "@selfxyz/contracts/contracts/interfaces/IRegisterCircuitVerifier.sol";
import { IDscCircuitVerifier } from "@selfxyz/contracts/contracts/interfaces/IDscCircuitVerifier.sol";
import { SelfStructs } from "@selfxyz/contracts/contracts/libraries/SelfStructs.sol";

/**
 * @title MockIdentityVerificationHubV2
 * @notice Mock implementation of IIdentityVerificationHubV2 for testing purposes
 * @dev Implements all required functions with stub implementations
 */
contract MockIdentityVerificationHubV2 is IIdentityVerificationHubV2 {
    bytes32 public lastConfigId;
    mapping(bytes32 => SelfStructs.VerificationConfigV2) public configs;

    // ====================================================
    // External Functions
    // ====================================================

    function registerCommitment(
        bytes32,
        uint256,
        IRegisterCircuitVerifier.RegisterCircuitProof memory
    ) external pure override {}

    function registerDscKeyCommitment(
        bytes32,
        uint256,
        IDscCircuitVerifier.DscCircuitProof memory
    ) external pure override {}

    function setVerificationConfigV2(SelfStructs.VerificationConfigV2 memory config)
        external
        override
        returns (bytes32)
    {
        bytes32 id = keccak256(abi.encode(config));
        lastConfigId = id;
        configs[id] = config;
        return id;
    }

    function verify(bytes calldata, bytes calldata) external pure override {
        // Stub implementation - actual verification logic should be handled by test contracts
    }

    function updateRegistry(bytes32, address) external pure override {}

    function updateVcAndDiscloseCircuit(bytes32, address) external pure override {}

    function updateRegisterCircuitVerifier(bytes32, uint256, address) external pure override {}

    function updateDscVerifier(bytes32, uint256, address) external pure override {}

    function batchUpdateRegisterCircuitVerifiers(
        bytes32[] calldata,
        uint256[] calldata,
        address[] calldata
    ) external pure override {}

    function batchUpdateDscCircuitVerifiers(
        bytes32[] calldata,
        uint256[] calldata,
        address[] calldata
    ) external pure override {}

    // ====================================================
    // External View Functions
    // ====================================================

    function registry(bytes32) external pure override returns (address) {
        return address(0);
    }

    function discloseVerifier(bytes32) external pure override returns (address) {
        return address(0);
    }

    function registerCircuitVerifiers(bytes32, uint256) external pure override returns (address) {
        return address(0);
    }

    function dscCircuitVerifiers(bytes32, uint256) external pure override returns (address) {
        return address(0);
    }

    function rootTimestamp(bytes32, uint256) external pure override returns (uint256) {
        return 0;
    }

    function getIdentityCommitmentMerkleRoot(bytes32) external pure override returns (uint256) {
        return 0;
    }

    function verificationConfigV2Exists(bytes32 configId) external view override returns (bool) {
        // Check if config exists by checking if olderThanEnabled is set (or any field)
        return configs[configId].olderThanEnabled;
    }

    // ====================================================
    // Public Functions
    // ====================================================

    function generateConfigId(SelfStructs.VerificationConfigV2 memory config)
        external
        pure
        override
        returns (bytes32)
    {
        return keccak256(abi.encode(config));
    }
}
