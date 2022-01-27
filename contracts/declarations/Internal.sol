// SPDX-License-Identifier: UNLICENSED

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

address constant _hdrnSourceAddress = address(0x291784Cd4eDd389a9794a4C68813d6dDe048A7c0);
address constant _hdrnFlowAddress   = address(0x53686418B7C02B87771C789cB51A7b90864069F7);
uint256 constant _hdrnLaunch        = 1645830000;