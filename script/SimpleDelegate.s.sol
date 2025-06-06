// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

contract SimpleDelegateScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // deploy SimpleDelegate

        vm.stopBroadcast();
    }
}
