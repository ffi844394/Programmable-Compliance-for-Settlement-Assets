// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";

import {PolicyManager} from "../src/PolicyManager/PolicyManager.sol";

contract DeployPolicyManager is Script {
    function run() external returns (PolicyManager pm) {
        address complianceAdmin = vm.envAddress("COMPLIANCE_ADMIN");
        address identityRegistry = vm.envAddress("IDENTITY_REGISTRY");

        vm.startBroadcast();
        pm = new PolicyManager(complianceAdmin, identityRegistry);
        vm.stopBroadcast();

        console.log("PolicyManager deployed at:", address(pm));
        console.log("PolicyManager owner:", pm.owner());
        console.log("PolicyManager identityRegistry:", pm.identityRegistry());
    }
}
