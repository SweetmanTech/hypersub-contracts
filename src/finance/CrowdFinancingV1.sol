// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/**
 * A minimal contract for accumulating funds from many accounts, transferring the balance
 * to a beneficiary, and allocating payouts to depositors as the beneficiary returns funds.
 *
 * The primary purpose of this contract is financing a trusted beneficiary, with the expectation of ROI.
 * If the fund target is met within the fund raising window, then processing the funds will transfer all
 * raised funds to the beneficiary, and change the state of the contract to allow for payouts to occur.
 *
 * Payouts are two things:
 * 1. Eth sent to the contract by the beneficiary as ROI
 * 2. Funding accounts withdrawing their balance of payout
 *
 * If the fund target is not met in the fund raise window, the raise fails, and all depositors can
 * withdraw their initial investment.
 */
contract CrowdFinancingV1 {
    // Emitted when an address deposits funds to the contract
    event Deposit(address indexed account, uint256 weiAmount);

    // Emitted when an account withdraws their initial allocation or payouts
    event Withdraw(address indexed account, uint256 weiAmount);

    // Emitted when the entirety of deposits is transferred to the beneficiary
    event Transfer(address indexed account, uint256 weiAmount);

    // Emitted when the targets are not met, and time has elapsed (calling processFunds)
    event Fail();

    // Emitted when eth is transferred to the contract, for depositers to withdraw their share
    event Payout(address indexed account, uint256 weiAmount);

    enum State {
        FUNDING,
        FAILED,
        FUNDED
    }

    // The current state of the contract
    State private _state;

    // The address of the beneficiary
    address payable private immutable _beneficiary;

    // The minimum fund target to meet. Once funds meet or exceed this value the
    // contract will lock and funders will not be able to withdraw
    uint256 private _fundTargetMin;

    // The maximum fund target. If a transfer from a funder causes totalFunds to exceed
    // this value, the transaction will revert.
    uint256 private _fundTargetMax;

    // The minimum wei an account can deposit
    uint256 private _minDeposit;

    // The maximum wei an account can deposit
    uint256 private _maxDeposit;

    // The expiration timestamp for the fund
    uint256 private _startTimestamp;

    // The expiration timestamp for the fund
    uint256 private _expirationTimestamp;

    // The total amount deposited for all accounts
    uint256 private _depositTotal;

    // The total amount withdrawn for all accounts
    uint256 private _withdrawTotal;

    mapping(address => uint256) private _deposits;

    // If the campaign is successful, then we track withdraw
    mapping(address => uint256) private _withdraws;

    constructor(
        address payable beneficiary,
        uint256 fundTargetMin,
        uint256 fundTargetMax,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint256 startTimestamp,
        uint256 endTimestamp
    ) {
        require(beneficiary != address(0), "Invalid beneficiary address");
        require(
            startTimestamp < endTimestamp, "Start must precede end"
        );
        require(
            endTimestamp > block.timestamp && (endTimestamp - startTimestamp) < 7776000,
            "Invalid end time"
        );
        require(fundTargetMin > 0, "Min target must be >= 0");
        require(fundTargetMin <= fundTargetMax, "Min target must be <= Max");
        require(minDeposit <= maxDeposit, "Min deposit must be <= Max");
        require(minDeposit <= fundTargetMax, "Min deposit must be <= Target Max");

        _beneficiary = beneficiary;
        _fundTargetMin = fundTargetMin;
        _fundTargetMax = fundTargetMax;
        _minDeposit = minDeposit;
        _maxDeposit = maxDeposit;
        _startTimestamp = startTimestamp;
        _expirationTimestamp = endTimestamp;

        _depositTotal = 0;
        _withdrawTotal = 0;
        _state = State.FUNDING;
    }

    ///////////////////////////////////////////
    // Phase 1: Deposits
    ///////////////////////////////////////////

    /**
     * Deposit eth into the contract track the deposit for calculating payout.
     *
     * Emits a {Deposit} event if the target was not met
     *
     * Requirements:
     *
     * - `msg.value` must be >= minimum fund amount and <= maximum fund amount
     * - deposit total must not exceed max fund target
     * - state must equal FUNDING
     */
    function deposit() public payable {
        require(depositAllowed(), "Deposits are not allowed");

        uint256 amount = msg.value;
        address account = msg.sender;
        uint256 total = _deposits[account] + amount;

        require(total >= _minDeposit, "Deposit amount is too low");
        require(total <= _maxDeposit, "Deposit amount is too high");

        _deposits[account] += amount;
        _depositTotal += amount;

        emit Deposit(account, amount);
    }

    /**
     * @return true if deposits are allowed
     */
    function depositAllowed() public view returns (bool) {
        return _depositTotal < _fundTargetMax && _state == State.FUNDING && started() && !expired();
    }

    /**
     * @return the total amount of deposits for a given account
     */
    function depositAmount(address account) public view returns (uint256) {
        return _deposits[account];
    }

    /**
     * @return the total amount of deposits for all accounts
     */
    function depositTotal() public view returns (uint256) {
        return _depositTotal;
    }

    ///////////////////////////////////////////
    // Phase 2: Transfer or Fail
    ///////////////////////////////////////////

    /*
    * Transfer funds to the beneficiary and change the state
    *
    * Emits a {Transfer} event if the target was met and funds transfered
    * Emits a {Fail} event if the target was not met
    */
    function processFunds() public {
        require(_state == State.FUNDING, "Funds already processed");
        require(expired(), "Raise window is not expired");

        if (fundTargetMet()) {
            _state = State.FUNDED;
            emit Transfer(_beneficiary, _depositTotal);
            _beneficiary.transfer(_depositTotal);
        } else {
            _state = State.FAILED;
            emit Fail();
        }
    }

    /**
     * @return true if the minimum fund target is met
     */
    function fundTargetMet() public view returns (bool) {
        return _depositTotal >= _fundTargetMin;
    }

    ///////////////////////////////////////////
    // Phase 3: Payouts / Refunds / Withdraws
    ///////////////////////////////////////////

    /**
     * @dev Only allow transfers once funded
     *
     * Emits a {Payout} event.
     */
    receive() external payable {
        require(_state == State.FUNDED, "Cannot accept payment");
        emit Payout(msg.sender, msg.value);
    }

    /**
     * @return The total amount of wei paid back by the beneficiary
     */
    function payoutTotal() public view returns (uint256) {
        if(state() != State.FUNDED) {
          return 0;
        }
        return address(this).balance + _withdrawTotal;
    }

    /**
     * @return The total wei withdrawn for a given account
     */
    function withdrawsOf(address account) public view returns (uint256) {
        return _withdraws[account];
    }

    /**
     * @return true if the contract allows withdraws
     */
    function withdrawAllowed() public view returns (bool) {
        return state() == State.FUNDED || state() == State.FAILED;
    }

    /**
     * @return The payout balance for the given account
     */
    function payoutBalance(address account) public view returns (uint256) {
        // Multiply by 1e18 to maximize precision. Note, this can be slightly lossy (1 WEI)
        uint256 depositPayoutTotal = (_deposits[account] * 1e18 * payoutTotal()) / (_depositTotal * 1e18);
        return depositPayoutTotal - withdrawsOf(account);
    }

    /**
     * Withdraw available funds to the sender, if withdraws are allowed, and
     * the sender has a deposit balance (failed), or a payout balance (funded)
     *
     * Emits a {Withdraw} event.
     */
    function withdraw() public {
        require(withdrawAllowed(), "Withdraw not allowed");
        address account = msg.sender;
        if (state() == State.FUNDED) {
            withdrawPayout(account);
        } else if (state() == State.FAILED) {
            withdrawDeposit(account);
        }
    }

    /**
     * @dev withdraw the initial deposit for hte given account
     */
    function withdrawDeposit(address account) private {
        uint256 amount = _deposits[account];
        require(amount > 0, "No balance");
        _deposits[account] = 0;
        emit Withdraw(account, amount);
        payable(account).transfer(amount);
    }

    /**
     * @dev withdraw the available payout balance for the given account
     */
    function withdrawPayout(address account) private {
        uint256 amount = payoutBalance(account);
        require(amount > 0, "No balance");
        _withdraws[account] += amount;
        _withdrawTotal += amount;
        emit Withdraw(account, amount);
        payable(account).transfer(amount);
    }

    ///////////////////////////////////////////
    // Utility Functons
    ///////////////////////////////////////////

    /**
     * @return The current state of financing
     */
    function state() public view returns (State) {
        return _state;
    }

    /**
     * @return the minimum deposit in wei
     */
    function minimumDeposit() public view returns (uint256) {
        return _minDeposit;
    }

    /**
     * @return the maximum deposit in wei
     */
    function maximumDeposit() public view returns (uint256) {
        return _maxDeposit;
    }

    /**
     * @return the unix timestamp in seconds when the funding phase starts
     */
    function startsAt() public view returns (uint256) {
        return _startTimestamp;
    }

    /**
     * @return true if the funding phase started
     */
    function started() public view returns (bool) {
        return block.timestamp >= _startTimestamp;
    }

    /**
     * @return the unix timestamp in seconds when the funding phase ends
     */
    function expiresAt() public view returns (uint256) {
        return _expirationTimestamp;
    }

    /**
     * @return true if the funding phase exipired
     */
    function expired() public view returns (bool) {
        return block.timestamp >= _expirationTimestamp;
    }

    /**
     * @return the address of the beneficiary
     */
    function beneficiaryAddress() public view returns (address) {
        return _beneficiary;
    }

    /**
     * @return the minimum fund target for the round to be considered successful
     */
    function minimumFundTarget() public view returns (uint256) {
        return _fundTargetMin;
    }

    /**
     * @return the maximum fund target for the round to be considered successful
     */
    function maximumFundTarget() public view returns (uint256) {
        return _fundTargetMax;
    }

}
