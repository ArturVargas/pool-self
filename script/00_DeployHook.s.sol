// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IIdentityVerificationHubV2} from "@selfxyz/contracts/contracts/interfaces/IIdentityVerificationHubV2.sol";
import {SelfUtils} from "@selfxyz/contracts/contracts/libraries/SelfUtils.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";

import {MockIdentityVerificationHubV2} from "../src/mocks/IdentityVerificationHub.sol";

import {SelfFeeHook} from "../src/SelfFeeHook.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Mines the address and deploys the SelfFeeHook contract (idempotent)
/// @dev Can be run multiple times safely - checks if contracts already exist before deploying
contract DeployHookScript is Script {
    // PoolManager address - use the one from Celo mainnet when forking
    IPoolManager public poolManager;
    /////////////////////////////////////
    // --- Configure These ---
    /////////////////////////////////////
    // Self Identity Verification Hub V2 address
    // For Celo mainnet: 0xe57F4773bd9c9d8b6Cd70431117d353298B9f5BF
    // For other networks, update this address
    // For localhost (Anvil), a mock will be deployed automatically
    address constant IDENTITY_VERIFICATION_HUB_V2_CELO = address(0xe57F4773bd9c9d8b6Cd70431117d353298B9f5BF);
    
    // Force use of mock hub even if real Self Hub exists (useful for forks where Self Hub fails)
    // Set to true to always deploy and use mock, false to use real hub when available
    bool constant FORCE_USE_MOCK = false;
    
    // If you already deployed a mock hub, set its address here (leave as address(0) to deploy new one)
    // This is useful when you deploy the mock separately and want to reuse it
    // Example: address constant EXISTING_MOCK_HUB = address(0x96Ca404310ED961b5ceA3Ad64E005C0d35a22B94);
    address constant EXISTING_MOCK_HUB = address(0);
    
    // Scope for Self verification (e.g., "self-residency-pool")
    string constant SCOPE = "self-residency-pool";
    
    // CREATE2_FACTORY is already defined in forge-std/src/Base.sol
    // address constant CREATE2_FACTORY = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
    
    /////////////////////////////////////

    // Verification config - adjust based on your requirements
    // olderThan: Minimum age requirement (0 = no requirement)
    // forbiddenCountries: Array of country codes to exclude (empty = no restrictions)
    // ofacEnabled: Whether to check OFAC sanctions
    function getVerificationConfig() internal pure returns (SelfUtils.UnformattedVerificationConfigV2 memory) {
        return SelfUtils.UnformattedVerificationConfigV2({
            olderThan: 0,
            forbiddenCountries: new string[](0),
            ofacEnabled: false
        });
    }

    /// @notice Compute CREATE2 address for a contract
    function computeCreate2Address(
        address deployer,
        bytes32 salt,
        bytes memory bytecode
    ) internal pure returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xFF),
                deployer,
                salt,
                keccak256(bytecode)
            )
        );
        return address(uint160(uint256(hash)));
    }

    function run() public {
        // Get PoolManager address
        // For Celo mainnet (chainId 42220), use the real address
        // For localhost (31337), use the address from AddressConstants
        if (block.chainid == 42220) {
            // Celo mainnet PoolManager
            poolManager = IPoolManager(0x288dc841A52FCA2707c6947B3A777c5E56cd87BC);
        } else if (block.chainid == 31337 || block.chainid == 1337) {
            // Localhost - check if it exists, otherwise use AddressConstants
            address poolManagerAddr = AddressConstants.getPoolManagerAddress(block.chainid);
            if (poolManagerAddr.code.length > 0) {
                poolManager = IPoolManager(poolManagerAddr);
            } else {
                // Fallback to Celo address if fork is used
                poolManager = IPoolManager(0x288dc841A52FCA2707c6947B3A777c5E56cd87BC);
            }
        } else {
            poolManager = IPoolManager(AddressConstants.getPoolManagerAddress(block.chainid));
        }
        
        console2.log("Using PoolManager:");
        console2.logAddress(address(poolManager));
        
        // Determine which hub to use (idempotent)
        address identityVerificationHubV2;
        bool needToDeployMockHub = false;
        
        // Check if we should force use mock
        if (FORCE_USE_MOCK || EXISTING_MOCK_HUB != address(0)) {
            if (EXISTING_MOCK_HUB != address(0)) {
                // Verify that the mock hub exists at this address
                address mockHubAddr = EXISTING_MOCK_HUB;
                uint256 mockHubCodeSize;
                assembly {
                    mockHubCodeSize := extcodesize(mockHubAddr)
                }
                if (mockHubCodeSize == 0) {
                    console2.log("Warning: Mock hub does not exist at specified address, will deploy new one...");
                    needToDeployMockHub = true;
                } else {
                    // Use existing mock hub
                    identityVerificationHubV2 = EXISTING_MOCK_HUB;
                    console2.log("Using existing MockIdentityVerificationHubV2:");
                    console2.logAddress(identityVerificationHubV2);
                }
            } else {
                // Need to deploy new mock hub
                needToDeployMockHub = true;
                console2.log("FORCE_USE_MOCK enabled - will deploy MockIdentityVerificationHubV2");
            }
        } else {
            // Check if we're on Celo mainnet (either directly or via fork)
            bool isCeloMainnet = block.chainid == 42220;
            
            // Check if the Celo Self Hub exists at the expected address (for forks)
            uint256 hubCodeSize;
            address celoHubAddress = IDENTITY_VERIFICATION_HUB_V2_CELO;
            assembly {
                hubCodeSize := extcodesize(celoHubAddress)
            }
            bool celoHubExists = hubCodeSize > 0;
            
            if (isCeloMainnet || celoHubExists) {
                // Using real Celo Self Hub (either on mainnet or fork)
                identityVerificationHubV2 = IDENTITY_VERIFICATION_HUB_V2_CELO;
                if (isCeloMainnet) {
                    console2.log("Using Celo mainnet Self Hub (direct):");
                } else {
                    console2.log("Using Celo mainnet Self Hub (from fork):");
                }
                console2.logAddress(identityVerificationHubV2);
            } else if (block.chainid == 31337 || block.chainid == 1337) {
                // Localhost/Anvil without fork - need to deploy mock hub
                needToDeployMockHub = true;
                console2.log("Detected localhost without fork - will deploy MockIdentityVerificationHubV2");
            } else {
                // For other networks, you may need to configure the address
                console2.log("Chain ID:");
                console2.log(block.chainid);
                revert("Unknown chain ID. Configure Self Hub address for this network, use a fork, or set FORCE_USE_MOCK=true.");
            }
        }

        // Deploy mock hub if needed (idempotent - check if exists first)
        if (needToDeployMockHub) {
            // For mock hub, we use regular deployment (not CREATE2)
            // So we just check if a mock hub was already deployed in a previous run
            // Since we don't have a deterministic address, we'll deploy a new one each time
            // But we can check if EXISTING_MOCK_HUB was set and use it if it exists
            console2.log("Deploying MockIdentityVerificationHubV2...");
            vm.startBroadcast();
            MockIdentityVerificationHubV2 mockHub = new MockIdentityVerificationHubV2();
            identityVerificationHubV2 = address(mockHub);
            vm.stopBroadcast();
            console2.log("Mock Hub deployed at:");
            console2.logAddress(identityVerificationHubV2);
        }

        // SelfFeeHook requires BEFORE_SWAP_FLAG and BEFORE_SWAP_RETURNS_DELTA_FLAG
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        // Get verification config
        SelfUtils.UnformattedVerificationConfigV2 memory verificationConfig = getVerificationConfig();

        // Encode constructor arguments
        bytes memory constructorArgs = abi.encode(
            poolManager,
            identityVerificationHubV2,
            SCOPE,
            verificationConfig
        );

        // Get salt from environment variable or mine it
        bytes32 salt;
        address hookAddress;
        
        // Check if SALT environment variable is set
        bool hasSaltEnv;
        try vm.envBytes32("SALT") returns (bytes32 saltEnv) {
            salt = saltEnv;
            hasSaltEnv = true;
        } catch {
            hasSaltEnv = false;
        }
        
        if (hasSaltEnv) {
            // Use provided salt
            console2.log("Using salt from environment variable:");
            console2.logBytes32(salt);
            
            // Calculate expected hook address with provided salt
            bytes memory creationCodeWithArgs = abi.encodePacked(
                type(SelfFeeHook).creationCode,
                constructorArgs
            );
            hookAddress = computeCreate2Address(0x4e59b44847b379578588920cA78FbF26c0B4956C, salt, creationCodeWithArgs);
            
            // Verify the address has the correct flags
            if (uint160(hookAddress) & Hooks.ALL_HOOK_MASK != flags) {
                revert("DeployHookScript: Provided salt does not produce address with correct flags");
            }
        } else {
            // Mine a salt that will produce a hook address with the correct flags
            (hookAddress, salt) = HookMiner.find(
                0x4e59b44847b379578588920cA78FbF26c0B4956C,
                flags,
                type(SelfFeeHook).creationCode,
                constructorArgs
            );
            console2.log("Mined salt:");
            console2.logBytes32(salt);
        }

        console2.log("Expected Hook Address:");
        console2.logAddress(hookAddress);
        console2.log("PoolManager:");
        console2.logAddress(address(poolManager));
        console2.log("Self Hub:");
        console2.logAddress(identityVerificationHubV2);
        console2.log("Scope:", SCOPE);
        console2.log("Chain ID:");
        console2.log(block.chainid);

        // Check if hook already exists (idempotent check)
        uint256 hookCodeSize;
        assembly {
            hookCodeSize := extcodesize(hookAddress)
        }

        SelfFeeHook hook;
        if (hookCodeSize > 0) {
            // Hook already deployed, use existing instance
            console2.log("Hook already deployed at this address, using existing instance");
            hook = SelfFeeHook(hookAddress);
        } else {
            // Deploy the hook using CREATE2
            console2.log("Deploying new hook...");
            vm.startBroadcast();
            hook = new SelfFeeHook{salt: salt}(
                poolManager,
                identityVerificationHubV2,
                SCOPE,
                verificationConfig
            );
            vm.stopBroadcast();

            require(address(hook) == hookAddress, "DeployHookScript: Hook Address Mismatch");
            console2.log("Hook deployed successfully!");
        }

        console2.log("SelfFeeHook address:");
        console2.logAddress(address(hook));
        console2.log("Verification Config ID:");
        console2.logBytes32(hook.verificationConfigId());
        console2.log("Base Fee (bps):");
        console2.log(hook.BASE_FEE());
        console2.log("Discount Fee (bps):");
        console2.log(hook.DISCOUNT_FEE());
        
        // Print salt for reuse
        console2.log("Salt used (set SALT env var to reuse):");
        console2.logBytes32(salt);
    }
}
