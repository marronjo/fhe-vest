// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { FHE, inEuint32, euint32 } from "@fhenixprotocol/contracts/FHE.sol";
import { Permissioned, Permission } from "@fhenixprotocol/contracts/access/Permissioned.sol";
import { IFHERC20 } from "./IFHERC20.sol";

/**
 * MENOTE
 * 
 *  - fix IFHERC20 balances, euint instead of string ... allow computation
 *  added extra method that returns euint instead of sealed string
 *  maybe this is unsafe ? need further clarification
 *  - look at best casting, look at limitations for mul/sub/add/div etc. (bits)
 *  add : 128
 *  sub : 128
 *  mul : 64
 *  div : 32
 * 
 *  for now use lowest value to avoid too much casting / confusion
 *  when larger bits are supported by FHE contracts then update
 * 
 *  - check latest version of FHE package - 0.2.1(latest)
 * 
 *  This contract does not support native ETH only FHERC20 tokens, unlike the OZ impl which supports both
 * 
 *  Limitations : 
 *  - 32 bit numbers only
 *  - only FHERC20 tokens supported
 *  - how to transfer fherc20 tokens to the contract ? metamask / implementation contract ? make vesting wallet abstract ??
 *  - no overflow or safety checks
 *  - only linear vesting, could be cool to add different vesting ? maybe too complex for this use case
 */

contract FHEVestingWallet is Permissioned {

    error FHEVestingWallet__DuplicateError(address beneficiary, address token);

    struct VestDetails {
        address beneficiary;
        euint32 amount;
        euint32 startTimestamp;
        euint32 durationSeconds;
        euint32 amountReleased;
    }

    // mapping(address token => euint32) private _fherc20Released;

    mapping(address user => mapping(address token => VestDetails)) vestingMap;

    // euint32 private immutable _start;
    // euint32 private immutable _duration;
    // address private immutable _beneficiary;

    euint32 private immutable ZERO = FHE.asEuint32(0);

    function createNewVestingSchedule(address beneficiary, address token, euint32 amount, euint32 startTimestamp, euint32 durationSeconds) public {
        VestDetails memory vest = vestingMap[beneficiary][token];
        if(vest.beneficiary != address(0)){
            revert FHEVestingWallet__DuplicateError(beneficiary, token);
        }

        IFHERC20(token).transferFromEncrypted(msg.sender, address(this), FHE.asEuint128(amount)); 

        vestingMap[beneficiary][token] = VestDetails({
            beneficiary: beneficiary,
            amount: amount,
            startTimestamp: startTimestamp,
            durationSeconds: durationSeconds,
            amountReleased: ZERO
        });
    }

    /**
     * @dev Getter for the start timestamp.
     */
    function start(Permission calldata permission, address beneficiary, address token) public view onlySender(permission) returns (string memory) {
        return FHE.sealoutput(vestingMap[beneficiary][token].startTimestamp, permission.publicKey);
    }

    /**
     * @dev Getter for the vesting duration.
     */
    function duration(Permission calldata permission, address beneficiary, address token) public view onlySender(permission) returns (string memory) {
        return FHE.sealoutput(vestingMap[beneficiary][token].durationSeconds, permission.publicKey);
    }

    /**
     * @dev Public getter for the end timestamp.
     */
    function end(Permission calldata permission, address beneficiary, address token) public view onlySender(permission) returns (string memory) {
        return FHE.sealoutput(end(beneficiary, token), permission.publicKey);
    }

    /**
     * @dev Private getter for the end timestamp.
     */
    function end(address beneficiary, address token) private view returns (euint32) {
        VestDetails memory vest = vestingMap[beneficiary][token];
        return FHE.add(vest.startTimestamp, vest.durationSeconds);
    }

    /**
     * @dev Amount of fhe token already released, private method for use in contract
     */
    function released(address beneficiary, address token) private view returns (euint32) {
        return vestingMap[beneficiary][token].amountReleased;
    }

    /**
     * @dev Amount of fhe token already released, public method for permissioned users only
     */
    function released(Permission calldata permission, address beneficiary, address token) public view onlySender(permission) returns (string memory) {
        return FHE.sealoutput(vestingMap[beneficiary][token].amountReleased, permission.publicKey);
    }

    /**
     * @dev Getter for the amount of releasable `token` tokens. `token` should be the address of an
     * IFHERC20 contract.
     */
    function releasable(address beneficiary, address token) public view virtual returns (euint32) {
        euint32 vested = vestedAmount(beneficiary, token, FHE.asEuint32(block.timestamp));
        return FHE.sub(vested, released(beneficiary, token));
    }

    /**
     * @dev Release the tokens that have already vested.
     *
     * Emits a {ERC20Released} event.
     */
    function release(address beneficiary, address token) public virtual {
        euint32 amountToRelease = releasable(beneficiary, token);
        euint32 releasedTokens = vestingMap[beneficiary][token].amountReleased;

        vestingMap[beneficiary][token].amountReleased = FHE.add(releasedTokens, amountToRelease);

        //_fherc20Released[token] = FHE.add(releasedTokens, amount);

        //emit ERC20Released(token, amount);

        // MENOTE
        // this reveals the person but only after tokens are released
        // could be improved by editing the FHERC20 token to allow secret transfers
        // e.g. instead of updating address in balances mapping ...
        // update eaddress in balances mapping instead!
        IFHERC20(token).transferEncrypted(beneficiary, FHE.asEuint128(amountToRelease)); // cast to 128 needed, no 32 bit method supported in FHERC20 yet
    }

    /**
     * @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
     */
    function vestedAmount(address beneficiary, address token, euint32 currentTimestamp) public view virtual returns (euint32) {

        VestDetails memory vest = vestingMap[beneficiary][token];

        // euint128 encryptedBalance = IFHERC20(token).balanceOfEncrypted(address(this)); //TODO
        // euint32 encryptedBalance32 = FHE.asEuint32(encryptedBalance);

        // euint32 totalAllocation32 = FHE.add(encryptedBalance32, released(token));

        return _vestingSchedule(vest.amount, vest.startTimestamp, currentTimestamp, vest.durationSeconds);
    }

    /**
     * @dev Virtual implementation of the vesting formula. This returns the amount vested, as a function of time, for
     * an asset given its total historical allocation.
     */
    function _vestingSchedule(euint32 totalAllocation, euint32 startTimestamp, euint32 currentTimestamp, euint32 durationSeconds) internal view virtual returns (euint32) {
        //MENOTE
        // if timestamp less than start, vesting has not started yet! return zero otherwise calculate amount
        return FHE.select(FHE.lt(currentTimestamp, startTimestamp), ZERO, _calculateVestingAmount(totalAllocation, startTimestamp, currentTimestamp, durationSeconds));
    }

    function _calculateVestingAmount(euint32 totalAllocation, euint32 startTimestamp, euint32 currentTimestamp, euint32 durationSeconds) private pure returns (euint32) {
        //MENOTE
        // if vesting is over (timestamp > end) then total amount can be released
        // otherwise vesting is ongoing, calculate amount according to linear vesting
        return FHE.select(FHE.gte(currentTimestamp, FHE.add(startTimestamp, durationSeconds)), totalAllocation, _calculateVestingMidAuction(totalAllocation, currentTimestamp, startTimestamp, durationSeconds));
    }

    //MENOTE
    // OZ Calculation 
    // (totalAllocation * (timestamp - start())) / duration()
    function _calculateVestingMidAuction(euint32 totalAllocation, euint32 currentTimestamp, euint32 startTimestamp, euint32 durationSeconds) private pure returns (euint32) {
        euint32 progress = FHE.mul(totalAllocation, FHE.sub(currentTimestamp, startTimestamp));    // result = totalAllocation * (timesamp - duration)
        return FHE.div(progress, durationSeconds);                                                 // return result / duration
    }
}