// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";

import {PolicyManager} from "../src/PolicyManager/PolicyManager.sol";
import {VolumeThresholdPolicy} from "../src/Policies/VolumeThresholdPolicy.sol";
import {KYCPolicy} from "../src/Policies/KYCPolicy.sol";

contract DeployPolicies is Script {
    function run() external returns (address volume, address kyc) {
        address policyManagerAddr = vm.envAddress("POLICY_MANAGER");
        uint256 lower = vm.envOr("LOWER_THRESHOLD", uint256(100));
        uint256 upper = vm.envOr("UPPER_THRESHOLD", uint256(200));

        bool requireOriginator = vm.envOr("REQ_ORIGINATOR_KYC", true);
        bool requireBeneficiary = vm.envOr("REQ_BENEFICIARY_KYC", true);
        bool requireVasp = vm.envOr("REQ_VASP_KYC", false);

        vm.startBroadcast();

        PolicyManager pm = PolicyManager(policyManagerAddr);

        VolumeThresholdPolicy vol = new VolumeThresholdPolicy(lower, upper);
        pm.addPolicy(address(vol));

        KYCPolicy kycP = new KYCPolicy(
            1,
            requireOriginator,
            requireBeneficiary,
            requireVasp
        );
        pm.addPolicy(address(kycP));

        vm.stopBroadcast();

        volume = address(vol);
        kyc = address(kycP);

        console.log("VolumeThresholdPolicy deployed+registered:", volume);
        console.log("KYCPolicy deployed+registered:", kyc);
    }
}
