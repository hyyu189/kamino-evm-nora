// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

contract BaseScript is Test {
    function lookup(string memory name) internal view returns (address) {
        return vm.envAddress(name);
    }
}
