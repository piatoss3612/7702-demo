// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract CheckCode {
    function checkCode(address target) public view returns (bytes memory code) {
        assembly {
            // Allocate memory for the code
            code := mload(0x40)
            // Update free memory pointer
            mstore(0x40, add(code, 0x40))
            // Get code size
            let size := extcodesize(target)
            // Store size
            mstore(code, size)
            // Copy code
            extcodecopy(target, add(code, 0x20), 0, size)
        }
    }
}
