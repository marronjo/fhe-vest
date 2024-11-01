// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25 <0.9.0;

import { Test } from "forge-std/src/Test.sol";
import { console } from "forge-std/src/console.sol";
import { FHERC20 } from "../src/FHERC20.sol";

import { FHEVestingWallet } from "../src/FHEVestingWallet.sol";
import { FheEnabled } from "../util/FheHelper.sol";
import { Permission, PermissionHelper } from "../util/PermissionHelper.sol";

import { FHE, inEuint128, euint128, inEuint32, euint32, ebool } from "@fhenixprotocol/contracts/FHE.sol";

/// @dev If this is your first time with Forge, read this tutorial in the Foundry Book:
/// https://book.getfoundry.sh/forge/writing-tests
contract FHEVestingWalletTest is Test, FheEnabled {
    //contracts
    FHEVestingWallet vestingWallet;
    FHERC20 token;

    //helpers
    PermissionHelper private permitHelper;
    PermissionHelper private tokenPermitHelper;

    //variables
    address public user;
    uint256 public userPrivateKey;
    Permission private userPermission;
    Permission private userTokenPermission;

    address private beneficiary;
    uint256 private beneficiaryPrivateKey;
    Permission private beneficiaryPermission;
    Permission private beneficiaryTokenPermission;

    modifier prank(address a) {
        vm.startPrank(a);
        _;
        vm.stopPrank();
    }

    function setUp() public virtual {
        // Required to mock FHE operations - do not forget to call this function
        // *****************************************************
        initializeFhe();
        // *****************************************************

        userPrivateKey = 0xB0B;
        user = vm.addr(userPrivateKey);

        beneficiaryPrivateKey = 0xA11CE;
        beneficiary = vm.addr(beneficiaryPrivateKey);

        vm.startPrank(user);

        // Instantiate the contract-under-test.
        vestingWallet = new FHEVestingWallet();
        permitHelper = new PermissionHelper(address(vestingWallet));

        userPermission = permitHelper.generatePermission(userPrivateKey);
        beneficiaryPermission = permitHelper.generatePermission(beneficiaryPrivateKey);

        token = new FHERC20("TST", "test");
        tokenPermitHelper = new PermissionHelper(address(token));

        userTokenPermission = tokenPermitHelper.generatePermission(userPrivateKey);
        beneficiaryTokenPermission = tokenPermitHelper.generatePermission(beneficiaryPrivateKey);

        token.mint(1_000_000_000);
        token.wrap(500_000_000);

        vm.stopPrank();
    }

    function helper_createNewVestingSchedule(address u, uint256 _amount, uint256 _startTimestamp, uint256 _durationSeconds) private prank(u) {
        inEuint128 memory amount128 = encrypt128(_amount);

        inEuint32 memory amount = encrypt32(_amount);
        inEuint32 memory startTimestamp = encrypt32(_startTimestamp);
        inEuint32 memory durationSeconds = encrypt32(_durationSeconds);

        token.approveEncrypted(address(vestingWallet), amount128);
        vestingWallet.createNewVestingSchedule(address(beneficiary), address(token), amount, startTimestamp, durationSeconds);
    }

    function helper_createNewVestingScheduleRevert(
        address u,
        uint256 _amount,
        uint256 _startTimestamp,
        uint256 _durationSeconds,
        bytes4 _revertSelector
    )
        private
        prank(u)
    {
        inEuint128 memory amount128 = encrypt128(_amount);

        inEuint32 memory amount = encrypt32(_amount);
        inEuint32 memory startTimestamp = encrypt32(_startTimestamp);
        inEuint32 memory durationSeconds = encrypt32(_durationSeconds);

        token.approveEncrypted(address(vestingWallet), amount128);

        vm.expectRevert(_revertSelector);
        vestingWallet.createNewVestingSchedule(address(beneficiary), address(token), amount, startTimestamp, durationSeconds);
    }

    function test_startOnlySender() public prank(user) {
        string memory startSealed = vestingWallet.start(userPermission, user, address(1));
        uint256 startUnsealed = unseal(address(vestingWallet), startSealed);
        assertEq(startUnsealed, 0);
    }

    function test_createNewVestingScheduleSuccess() public {
        inEuint128 memory amount128 = encrypt128(100);

        inEuint32 memory amount = encrypt32(100);
        inEuint32 memory startTimestamp = encrypt32(50);
        inEuint32 memory durationSeconds = encrypt32(200);

        token.approveEncrypted(address(vestingWallet), amount128);
        vestingWallet.createNewVestingSchedule(address(beneficiary), address(token), amount, startTimestamp, durationSeconds);

        vm.startPrank(beneficiary);
        string memory startSealed = vestingWallet.start(beneficiaryPermission, beneficiary, address(token));
        uint256 startUnsealed = unseal(address(vestingWallet), startSealed);
        assertEq(startUnsealed, 50);

        string memory durationSealed = vestingWallet.duration(beneficiaryPermission, beneficiary, address(token));
        uint256 durationUnsealed = unseal(address(vestingWallet), durationSealed);
        assertEq(durationUnsealed, 200);
        vm.stopPrank();

        (address _vBeneficiary, euint32 _vAmount, /*euint32 _vStartTimestamp*/, euint32 _vDurationSeconds, euint32 _vAmountReleased) =
            vestingWallet.vestingMap(beneficiary, address(token));

        assertEq(_vBeneficiary, beneficiary);

        ebool amountsEqual = FHE.eq(_vAmount, FHE.asEuint32(amount));
        bool amountsDecrypted = FHE.decrypt(amountsEqual);
        assertEq(amountsDecrypted, true);

        // gives stack overflow error, need to investigate further
        // ebool timestampEqual = FHE.eq(_vStartTimestamp, FHE.asEuint32(startTimestamp));
        // bool timestampDecrypted = FHE.decrypt(timestampEqual);
        // assertEq(timestampDecrypted, true);

        ebool durationEqual = FHE.eq(_vDurationSeconds, FHE.asEuint32(durationSeconds));
        bool durationDecrypted = FHE.decrypt(durationEqual);
        assertEq(durationDecrypted, true);

        ebool releasedEqual = FHE.eq(_vAmountReleased, FHE.asEuint32(0));
        bool releasedDecrypted = FHE.decrypt(releasedEqual);
        assertEq(releasedDecrypted, true);
    }

    function test_createNewVestingScheduleDuplicate() public {
        helper_createNewVestingSchedule(user, 50, 50, 50);
        helper_createNewVestingScheduleRevert(user, 100, 100, 100, FHEVestingWallet.FHEVestingWallet__DuplicateError.selector);
    }
}
