// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";

import {AssetBackedToken} from "../src/AssetBackedToken.sol";

contract DeploySettlementAssetToken is Script {
    function run() external returns (AssetBackedToken abt) {
        string memory name = vm.envOr("ABT_NAME", string("Test Asset Backed Token"));
        string memory symbol = vm.envOr("ABT_SYMBOL", string("TABT"));
        string memory uri = vm.envOr("ABT_URI", string("https://example.com/supplemental.json"));

        address issuer = vm.envAddress("ISSUER");
        address adminControls = vm.envAddress("ADMIN_CONTROLS");

        vm.startBroadcast();
        abt = new AssetBackedToken(name, symbol, uri, issuer, adminControls);
        vm.stopBroadcast();

        console.log("ABT deployed at:", address(abt));
        console.log("ABT owner:", abt.owner());
        console.log("ABT adminControls:", address(abt.adminControls()));
    }
}
