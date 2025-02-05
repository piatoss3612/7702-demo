// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract SimpleDelegate {
    event Executed(address indexed to, uint256 value, bytes data);

    struct Call {
        bytes data;
        address to;
        uint256 value;
    }

    function execute(Call[] memory calls) external payable virtual {
        _execute(calls);
    }

    function _execute(Call[] memory calls) internal virtual {
        for (uint256 i = 0; i < calls.length; i++) {
            Call memory call = calls[i];
            (bool success, bytes memory result) = call.to.call{value: call.value}(call.data);
            require(success, string(result));
            emit Executed(call.to, call.value, call.data);
        }
    }

    receive() external payable {}
}
