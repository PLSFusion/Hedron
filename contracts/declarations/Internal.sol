// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./External.sol";

struct ShareStore {
    HEXStakeMinimal stake;
    uint16          mintedDays;
    uint8           launchBonus;
    uint16          loanStart;
    uint16          loanedDays;
    uint32          interestRate;
    uint8           paymentsMade;
    bool            isLoaned;
}

struct ShareCache {
    HEXStakeMinimal _stake;
    uint256         _mintedDays;
    uint256         _launchBonus;
    uint256         _loanStart;
    uint256         _loanedDays;
    uint256         _interestRate;
    uint256         _paymentsMade;
    bool            _isLoaned;
}

address constant _hdrnSourceAddress = address(0x9d73Ced2e36C89E5d167151809eeE218a189f801);
address constant _hdrnFlowAddress   = address(0xF447BE386164dADfB5d1e7622613f289F17024D8);
uint256 constant _hdrnLaunch        = 1645833600;