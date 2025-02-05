// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {SimpleDelegate} from "src/SimpleDelegate.sol";

contract SafeSimpleDelegate is SimpleDelegate {
    error OnlySelf();

    function execute(Call[] memory calls) external payable override {
        if (msg.sender != address(this)) revert OnlySelf();

        _execute(calls);
    }
}
