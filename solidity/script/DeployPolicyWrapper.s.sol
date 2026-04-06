// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";

import {PolicyWrapper} from "../src/PolicyWrapper/PolicyWrapper.sol";

contract DeployPolicyWrapper is Script {
    function run() external returns (PolicyWrapper w) {
        address vaspOperator = vm.envAddress("VASP_OPERATOR");
        address abt = vm.envAddress("ABT");
        address policyManager = vm.envAddress("POLICY_MANAGER");
        address adminControls = vm.envAddress("ADMIN_CONTROLS");

        uint256 timeoutReject = vm.envOr("TIMEOUT_REJECT", uint256(1 days));
        string memory name = vm.envOr("WRAPPER_NAME", string("Wrapped TABT"));
        string memory symbol = vm.envOr("WRAPPER_SYMBOL", string("wTABT"));

        vm.startBroadcast();
        w = new PolicyWrapper(
            vaspOperator,
            abt,
            timeoutReject,
            name,
            symbol,
            policyManager,
            adminControls
        );
        vm.stopBroadcast();

        console.log("PolicyWrapper deployed at:", address(w));
        console.log("PolicyWrapper owner:", w.owner());
        console.log("PolicyWrapper underlying:", address(w.underlying()));
        console.log("PolicyWrapper policyManager:", w.policyManager());
        console.log("PolicyWrapper adminControls:", address(w.adminControls()));
    }
}
