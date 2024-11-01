// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25 <0.9.0;

import { Test } from "forge-std/src/Test.sol";

import { FHERC20 } from "../src/FHERC20.sol";
import { FheEnabled } from "../util/FheHelper.sol";
import { Permission, PermissionHelper } from "../util/PermissionHelper.sol";

import { inEuint128, euint128 } from "@fhenixprotocol/contracts/FHE.sol";

/// @dev If this is your first time with Forge, read this tutorial in the Foundry Book:
/// https://book.getfoundry.sh/forge/writing-tests
contract TokenTest is Test, FheEnabled {
    FHERC20 internal token;
    PermissionHelper private permitHelper;

    address public owner;
    uint256 public ownerPrivateKey;

    uint256 private receiverPrivateKey;
    address private receiver;

    Permission private permission;
    Permission private permissionReceiver;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        // Required to mock FHE operations - do not forget to call this function
        // *****************************************************
        initializeFhe();
        // *****************************************************

        receiverPrivateKey = 0xB0B;
        receiver = vm.addr(receiverPrivateKey);

        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);

        vm.startPrank(owner);

        // Instantiate the contract-under-test.
        token = new FHERC20("hello", "TST");
        permitHelper = new PermissionHelper(address(token));

        permission = permitHelper.generatePermission(ownerPrivateKey);
        permissionReceiver = permitHelper.generatePermission(receiverPrivateKey);

        vm.stopPrank();
    }
}
