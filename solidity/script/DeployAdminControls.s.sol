// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";

import {AdminControls} from "../src/AdministrativeControls/AdminControls.sol";

contract DeployAdminControls is Script {
    function run() external returns (AdminControls admin) {
        address governor = vm.envAddress("GOVERNOR");
        address registrar = vm.envAddress("REGISTRAR");
        address recoveryOps = vm.envAddress("RECOVERY_OPS");

        vm.startBroadcast();
        admin = new AdminControls(governor, registrar, recoveryOps);
        vm.stopBroadcast();

        console.log("AdminControls deployed at:", address(admin));
    }
}
