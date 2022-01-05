// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "../declarations/Internal.sol";

contract HEXStakeInstance {
    
    HEX        private _hx;
    address    private _creator;
    address    public  whoami;
    ShareStore public  share;

    constructor(address hexAddress) {
        /* _creator is not an admin key. It is set at contsruction to be a link
           to the parent contract. In this case HSIM */
        _creator = msg.sender;
        whoami   = address(this);

        // set HEX contract address
        _hx = HEX(payable(hexAddress));
    }

    /**
     * @dev Creates a new HEX stake using all HEX ERC20 tokens assigned
     *      to this contract's address.
     * @param stakeLength Number of days the HEX ERC20 tokens will be staked.
     */
    function initialize(uint256 stakeLength) external {
        uint256 hexBalance = _hx.balanceOf(whoami);

        require(msg.sender == _creator,
            "HSI: Caller must be contract creator");
        require(share.stake.stakedDays == 0,
            "HSI: Initialization already performed");
        require(hexBalance > 0,
            "HSI: Initialization requires non-zero HEX balance");

        _hx.stakeStart(
            hexBalance,
            stakeLength
        );

        (share.stake.stakeId,
            share.stake.stakedHearts,
            share.stake.stakeShares,
            share.stake.lockedDay,
            share.stake.stakedDays,
            share.stake.unlockedDay,
            share.stake.isAutoStake
        ) = _hx.stakeLists(whoami, 0);
    }

    /**
     * @dev Calls the HEX function "stakeGoodAccounting" against this
     *      contract's address.
     */
    function goodAccounting() external {
        require(share.stake.stakedDays > 0,
            "HSI: Initialization not yet performed");

        _hx.stakeGoodAccounting(whoami, 0, share.stake.stakeId);

        (share.stake.stakeId,
            share.stake.stakedHearts,
            share.stake.stakeShares,
            share.stake.lockedDay,
            share.stake.stakedDays,
            share.stake.unlockedDay,
            share.stake.isAutoStake
        ) = _hx.stakeLists(whoami, 0);
    }

    /**
     * @dev Ends the HEX stake, transfers HEX ERC20 tokens to the creator
            address, and self-destructs this contract.
     */
    function destroy() external {
        require(msg.sender == _creator,
            "HSI: Caller must be contract creator");
        require(share.stake.stakedDays > 0,
            "HSI: Initialization not yet performed");

        _hx.stakeEnd(0, share.stake.stakeId);
        
        uint256 hexBalance = _hx.balanceOf(whoami);

        if (_hx.approve(_creator, hexBalance)) {
            selfdestruct(payable(_creator));
        }
        else {
            revert();
        }
    }

    /**
     * @dev Updates this contracts share data.
     * @param _share Updated share data in the form of a ShareCache struct.
     */
    function update(ShareCache memory _share) external {
        require(msg.sender == _creator,
            "HSI: Caller must be contract creator");

        share.mintedDays   = uint16(_share._mintedDays);
        share.launchBonus  = uint8 (_share._launchBonus);
        share.loanStart    = uint16(_share._loanStart);
        share.loanedDays   = uint16(_share._loanedDays);
        share.interestRate = uint32(_share._interestRate);
        share.paymentsMade = uint8 (_share._paymentsMade);
        share.isLoaned     = _share._isLoaned;
    }
}