// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IIdentityVerificationHubV2} from "@selfxyz/contracts/contracts/interfaces/IIdentityVerificationHubV2.sol";
import {SelfStructs} from "@selfxyz/contracts/contracts/libraries/SelfStructs.sol";

import {SelfFeeHook} from "../src/SelfFeeHook.sol";
import {SelfUtils} from "@selfxyz/contracts/contracts/libraries/SelfUtils.sol";
import {BaseTest} from "./utils/BaseTest.sol";

/**
 * @title SelfFeeHookForkTest
 * @notice Fork test for SelfFeeHook on Celo mainnet
 * @dev Tests the hook against real Uniswap v4 contracts deployed on Celo
 */
contract SelfFeeHookForkTest is BaseTest {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // Celo mainnet addresses for Uniswap v4
    IPoolManager constant CELO_POOL_MANAGER = IPoolManager(0x288dc841A52FCA2707c6947B3A777c5E56cd87BC);
    address constant CELO_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Self Identity Verification Hub V2 on Celo mainnet
    IIdentityVerificationHubV2 constant CELO_SELF_HUB = IIdentityVerificationHubV2(0xe57F4773bd9c9d8b6Cd70431117d353298B9f5BF);

    SelfFeeHook public hook;
    PoolKey public poolKey;
    bool public forked;

    // Test users
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        // Try to fork Celo mainnet
        try vm.createSelectFork(vm.rpcUrl("celo")) {
            forked = true;
            console2.log("Forked Celo mainnet");
            console2.log("Block number:", block.number);
            console2.log("Chain ID:", block.chainid);

            // Verify we're on Celo
            assertEq(block.chainid, 42220, "Must be on Celo mainnet");

            // Verify Self Hub exists
            uint256 hubCodeSize;
            address hubAddr = address(CELO_SELF_HUB);
            assembly {
                hubCodeSize := extcodesize(hubAddr)
            }
            require(hubCodeSize > 0, "Self Hub must exist on Celo");

            console2.log("Self Identity Verification Hub:");
            console2.logAddress(hubAddr);
            console2.log("PoolManager:");
            console2.logAddress(address(CELO_POOL_MANAGER));
            
            // Set up verification config
            // Using a simple config for testing - adjust based on your needs
            SelfUtils.UnformattedVerificationConfigV2 memory verificationConfig = 
                SelfUtils.UnformattedVerificationConfigV2({
                    olderThan: 0,
                    forbiddenCountries: new string[](0),
                    ofacEnabled: false
                });

            // Deploy SelfFeeHook with real Celo contracts
            // Note: Hook address needs specific flags, but for fork testing we can deploy normally
            hook = new SelfFeeHook(
                CELO_POOL_MANAGER,
                hubAddr,
                "self-residency-pool", // scope
                verificationConfig
            );

            console2.log("SelfFeeHook deployed at:");
            console2.logAddress(address(hook));
            console2.log("Verification Config ID (uint256):");
            console2.log(uint256(hook.verificationConfigId()));
        } catch {
            forked = false;
            console2.log("Could not fork Celo mainnet. Run tests with: forge test --fork-url https://celo.drpc.org");
        }
    }

    function test_Fork_CeloMainnet_IsForked() public {
        if (!forked) {
            vm.skip(true);
        }
        assertTrue(forked, "Should be forked");
        assertEq(block.chainid, 42220, "Should be on Celo mainnet");
    }

    function test_Fork_PoolManager_Exists() public {
        if (!forked) {
            vm.skip(true);
        }

        // Verify PoolManager exists and has code
        uint256 codeSize;
        address poolManagerAddr = address(CELO_POOL_MANAGER);
        assembly {
            codeSize := extcodesize(poolManagerAddr)
        }
        assertGt(codeSize, 0, "PoolManager should have code");
    }

    function test_Fork_Permit2_Exists() public {
        if (!forked) {
            vm.skip(true);
        }

        // Verify Permit2 exists
        uint256 codeSize;
        address permit2Addr = CELO_PERMIT2;
        assembly {
            codeSize := extcodesize(permit2Addr)
        }
        assertGt(codeSize, 0, "Permit2 should have code");
    }

    function test_Fork_SelfHub_Exists() public {
        if (!forked) {
            vm.skip(true);
        }

        // Verify Self Identity Verification Hub exists
        uint256 codeSize;
        address hubAddr = address(CELO_SELF_HUB);
        assembly {
            codeSize := extcodesize(hubAddr)
        }
        assertGt(codeSize, 0, "Self Hub should have code");
    }

    function test_Fork_SelfHub_HasCorrectInterface() public {
        if (!forked) {
            vm.skip(true);
        }

        // Test that the hub responds to setVerificationConfigV2
        SelfUtils.UnformattedVerificationConfigV2 memory config = 
            SelfUtils.UnformattedVerificationConfigV2({
                olderThan: 0,
                forbiddenCountries: new string[](0),
                ofacEnabled: false
            });

        // This should not revert if the hub has the correct interface
        bytes32 configId = CELO_SELF_HUB.setVerificationConfigV2(
            SelfUtils.formatVerificationConfigV2(config)
        );
        
        assertTrue(configId != bytes32(0), "Config ID should be non-zero");
        // Config ID successfully retrieved from hub
    }

    function test_Fork_Hook_DeployedCorrectly() public {
        if (!forked) {
            vm.skip(true);
        }

        assertTrue(address(hook) != address(0), "Hook should be deployed");
        assertEq(address(hook.poolManager()), address(CELO_POOL_MANAGER), "Hook should use Celo PoolManager");
        assertTrue(hook.verificationConfigId() != bytes32(0), "Hook should have verification config");
        
        // Verify hook constants
        assertEq(hook.BASE_FEE(), 10000, "Base fee should be 1%");
        assertEq(hook.DISCOUNT_FEE(), 3000, "Discount fee should be 0.3%");
    }

    // TODO: Add more fork tests once hook is properly deployed
    // - Test swap with base fee
    // - Test swap with Self proof (discount fee)
    // - Test interaction with real pools on Celo
}

