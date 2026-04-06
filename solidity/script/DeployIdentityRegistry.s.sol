// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";

import {IdentityRegistry} from "../src/IdentityManager/IdentityRegistry.sol";

contract DeployIdentityRegistry is Script {
    function run() external returns (IdentityRegistry reg) {
        address intendedOwner = vm.envOr("IDENTITY_PROVIDER", address(0));

        vm.startBroadcast();
        reg = new IdentityRegistry();

        // IdentityRegistry constructor sets owner = msg.sender.
        // If you want a different owner, transfer ownership here.
        if (intendedOwner != address(0) && intendedOwner != reg.owner()) {
            reg.setOwner(intendedOwner);
        }

        vm.stopBroadcast();
        console.log("IdentityRegistry deployed at:", address(reg));
        console.log("IdentityRegistry owner:", reg.owner());
    }
}
