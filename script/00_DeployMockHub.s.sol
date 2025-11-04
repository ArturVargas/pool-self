// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {MockIdentityVerificationHubV2} from "../src/mocks/IdentityVerificationHub.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Deploys the MockIdentityVerificationHubV2 contract for local testing
contract DeployMockHubScript is Script {
    function run() public {
        console2.log("Deploying MockIdentityVerificationHubV2...");
        console2.log("Chain ID:");
        console2.log(block.chainid);

        vm.startBroadcast();

        MockIdentityVerificationHubV2 mockHub = new MockIdentityVerificationHubV2();

        vm.stopBroadcast();

        console2.log("MockIdentityVerificationHubV2 deployed successfully!");
        console2.log("Address:");
        console2.logAddress(address(mockHub));

        // Optional: Set a verification config for testing
        console2.log("\nTo use this mock hub, update your scripts/tests with:");
        console2.log("address constant MOCK_HUB =");
        console2.logAddress(address(mockHub));
        console2.log(";");
    }
}

