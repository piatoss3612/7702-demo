// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UnsafeDelegation} from "src/UnsafeDelegation.sol";

contract SafeDelegation is UnsafeDelegation {
    error OnlySelf();

    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf();
        _;
    }

    function identifier() public pure override returns (bytes32) {
        return keccak256("SafeDelegation");
    }

    function execute(Call[] memory calls) external payable override onlySelf {
        _execute(calls);
    }
}
