// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Deploys two MockERC20 tokens for pool testing
/// @dev This script is idempotent - it checks if tokens already exist before deploying
contract DeployMockTokensScript is Script {
    // Token configuration
    string constant TOKEN0_NAME = "Test Token A";
    string constant TOKEN0_SYMBOL = "TESTA";
    uint8 constant TOKEN0_DECIMALS = 18;
    
    string constant TOKEN1_NAME = "Test Token B";
    string constant TOKEN1_SYMBOL = "TESTB";
    uint8 constant TOKEN1_DECIMALS = 18;

    // Expected addresses (for reusing existing tokens)
    // Update these with the addresses from a previous deployment
    // Example from deployment:
    // Token0: 0x96Ca404310ED961b5ceA3Ad64E005C0d35a22B94
    // Token1: 0x2A19790B6Dd1fC70e45e6F0D64A1a61C79a5Da0c
    address constant EXISTING_TOKEN0 = address(0x96Ca404310ED961b5ceA3Ad64E005C0d35a22B94);
    address constant EXISTING_TOKEN1 = address(0x2A19790B6Dd1fC70e45e6F0D64A1a61C79a5Da0c);

    function run() public {
        address token0Address;
        address token1Address;

        // Check if we should use existing tokens
        if (EXISTING_TOKEN0 != address(0)) {
            address existingToken0 = EXISTING_TOKEN0;
            uint256 token0CodeSize;
            assembly {
                token0CodeSize := extcodesize(existingToken0)
            }
            if (token0CodeSize > 0) {
                // Verify it's actually a MockERC20 by checking if it has the expected interface
                // We can check by calling name() or symbol()
                try MockERC20(existingToken0).symbol() returns (string memory symbol) {
                    if (keccak256(bytes(symbol)) == keccak256(bytes(TOKEN0_SYMBOL))) {
                        token0Address = EXISTING_TOKEN0;
                        console2.log("Using existing Token0:");
                        console2.logAddress(token0Address);
                    } else {
                        console2.log("Warning: Token0 at address has different symbol, deploying new one...");
                        token0Address = _deployToken(TOKEN0_NAME, TOKEN0_SYMBOL, TOKEN0_DECIMALS);
                    }
                } catch {
                    console2.log("Warning: Token0 at address is not a valid ERC20, deploying new one...");
                    token0Address = _deployToken(TOKEN0_NAME, TOKEN0_SYMBOL, TOKEN0_DECIMALS);
                }
            } else {
                console2.log("Warning: Token0 does not exist at specified address, deploying new one...");
                token0Address = _deployToken(TOKEN0_NAME, TOKEN0_SYMBOL, TOKEN0_DECIMALS);
            }
        } else {
            token0Address = _deployToken(TOKEN0_NAME, TOKEN0_SYMBOL, TOKEN0_DECIMALS);
        }

        if (EXISTING_TOKEN1 != address(0)) {
            address existingToken1 = EXISTING_TOKEN1;
            uint256 token1CodeSize;
            assembly {
                token1CodeSize := extcodesize(existingToken1)
            }
            if (token1CodeSize > 0) {
                // Verify it's actually a MockERC20 by checking if it has the expected interface
                try MockERC20(existingToken1).symbol() returns (string memory symbol) {
                    if (keccak256(bytes(symbol)) == keccak256(bytes(TOKEN1_SYMBOL))) {
                        token1Address = EXISTING_TOKEN1;
                        console2.log("Using existing Token1:");
                        console2.logAddress(token1Address);
                    } else {
                        console2.log("Warning: Token1 at address has different symbol, deploying new one...");
                        token1Address = _deployToken(TOKEN1_NAME, TOKEN1_SYMBOL, TOKEN1_DECIMALS);
                    }
                } catch {
                    console2.log("Warning: Token1 at address is not a valid ERC20, deploying new one...");
                    token1Address = _deployToken(TOKEN1_NAME, TOKEN1_SYMBOL, TOKEN1_DECIMALS);
                }
            } else {
                console2.log("Warning: Token1 does not exist at specified address, deploying new one...");
                token1Address = _deployToken(TOKEN1_NAME, TOKEN1_SYMBOL, TOKEN1_DECIMALS);
            }
        } else {
            token1Address = _deployToken(TOKEN1_NAME, TOKEN1_SYMBOL, TOKEN1_DECIMALS);
        }

        console2.log("\n=== Deployment Summary ===");
        console2.log("Token0 deployed:");
        console2.logAddress(token0Address);
        console2.log("Token1 deployed:");
        console2.logAddress(token1Address);
        
        console2.log("\nTo use these tokens in BaseScript.sol, update:");
        console2.log("IERC20 internal constant token0 = IERC20(");
        console2.logAddress(token0Address);
        console2.log(");");
        console2.log("IERC20 internal constant token1 = IERC20(");
        console2.logAddress(token1Address);
        console2.log(");");
    }

    function _deployToken(string memory name, string memory symbol, uint8 decimals) internal returns (address) {
        console2.log("Deploying", name, "...");
        vm.startBroadcast();
        MockERC20 token = new MockERC20(name, symbol, decimals);
        vm.stopBroadcast();
        
        address tokenAddress = address(token);
        console2.log("Deployed at:");
        console2.logAddress(tokenAddress);
        
        return tokenAddress;
    }
}

