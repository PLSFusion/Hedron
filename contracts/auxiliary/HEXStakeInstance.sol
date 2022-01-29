// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.9;

import "../declarations/Internal.sol";

contract HEXStakeInstance {
    
    IHEX       private _hx;
    address    private _creator;
    address    public  whoami;
    ShareStore public  share;

    constructor(
        address hexAddress
    )
    {
        /* _creator is not an admin key. It is set at contsruction to be a link
           to the parent contract. In this case HSIM */
        _creator = msg.sender;
        whoami   = address(this);

        // set HEX contract address
        _hx = IHEX(payable(hexAddress));
    }

    /**
     * @dev Updates the HSI's internal HEX stake data.
     */
    function _stakeDataUpdate(
    )
        internal
    {
        uint40 stakeId;
        uint72 stakedHearts;
        uint72 stakeShares;
        uint16 lockedDay;
        uint16 stakedDays;
        uint16 unlockedDay;
        bool   isAutoStake;
        
        (stakeId,
         stakedHearts,
         stakeShares,
         lockedDay,
         stakedDays,
         unlockedDay,
         isAutoStake
        ) = _hx.stakeLists(whoami, 0);

        share.stake.stakeId = stakeId;
        share.stake.stakeShares = stakeShares;
        share.stake.lockedDay = lockedDay;
        share.stake.stakedDays = stakedDays;
    }

    /**
     * @dev Creates a new HEX stake using all HEX ERC20 tokens assigned
     *      to the HSI's contract address. This is a privileged operation only
     *      HEXStakeInstanceManager.sol can call.
     * @param stakeLength Number of days the HEX ERC20 tokens will be staked.
     */
    function initialize(
        uint256 stakeLength
    )
        external
    {
        uint256 hexBalance = _hx.balanceOf(whoami);

        require(msg.sender == _creator,
            "HSI: Caller must be contract creator");
        require(share.stake.stakedDays == 0,
            "HSI: Initialization already performed");
        require(hexBalance > 0,
            "HSI: Initialization requires a non-zero HEX balance");

        _hx.stakeStart(
            hexBalance,
            stakeLength
        );

        _stakeDataUpdate();
    }

    /**
     * @dev Calls the HEX function "stakeGoodAccounting" against the
     *      HEX stake held within the HSI.
     */
    function goodAccounting(
    )
        external
    {
        require(share.stake.stakedDays > 0,
            "HSI: Initialization not yet performed");

        _hx.stakeGoodAccounting(whoami, 0, share.stake.stakeId);

        _stakeDataUpdate();
    }

    /**
     * @dev Ends the HEX stake, approves the "_creator" address to transfer
     *      all HEX ERC20 tokens, and self-destructs the HSI. This is a 
     *      privileged operation only HEXStakeInstanceManager.sol can call.
     */
    function destroy(
    )
        external
    {
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
     * @dev Updates the HSI's internal share data. This is a privileged 
     *      operation only HEXStakeInstanceManager.sol can call.
     * @param _share "ShareCache" object containing updated share data.
     */
    function update(
        ShareCache memory _share
    )
        external 
    {
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

    /**
     * @dev Fetches stake data from the HEX contract.
     * @return A HEXStake object containg the HEX stake data. 
     */
    function stakeDataFetch(
    ) 
        external
        view
        returns(HEXStake memory)
    {
        uint40 stakeId;
        uint72 stakedHearts;
        uint72 stakeShares;
        uint16 lockedDay;
        uint16 stakedDays;
        uint16 unlockedDay;
        bool   isAutoStake;
        
        (stakeId,
         stakedHearts,
         stakeShares,
         lockedDay,
         stakedDays,
         unlockedDay,
         isAutoStake
        ) = _hx.stakeLists(whoami, 0);

        return HEXStake(stakeId,
                        stakedHearts,
                        stakeShares,
                        lockedDay,
                        stakedDays,
                        unlockedDay,
                        isAutoStake
        );
    }
}