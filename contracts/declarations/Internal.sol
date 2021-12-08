// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "./External.sol";

struct ShareStore {
    HEXStake stake;
    uint16   mintedDays;
    uint8    launchBonus;
    uint16   loanStart;
    uint16   loanedDays;
    uint32   interestRate;
    uint8    paymentsMade;
    bool     isLoaned;
}

struct ShareCache {
    HEXStake _stake;
    uint256  _mintedDays;
    uint256  _launchBonus;
    uint256  _loanStart;
    uint256  _loanedDays;
    uint256  _interestRate;
    uint256  _paymentsMade;
    bool     _isLoaned;
}

address constant _hdrnSourceAddress = address(0); //TODO CHANGE ME
uint256 constant _hdrnLaunch        = 1640386800; // TODO CHANGE ME