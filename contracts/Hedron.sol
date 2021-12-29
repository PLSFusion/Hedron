// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./auxiliary/HEXStakeInstanceManager.sol";

/* NOTE to the auditor/s. Our biggest concern is likely to be uint
   overflows. Since we are compiling with solidity 0.8.x an overflow
   will cause a transaction to revert. The HEX contract itself contains
   some overflow possibilities which will take some time (around 180
   years or so in our estimation) to play out. In most cases we can 
   conceive, these overflows should pose no operational threat. We cast
   down to smaller uint sizes in most overflowable cases. However,
   we need to be certain it is safe. */

contract Hedron is ERC20 {

    /* uint72 *might* be overflowable, some checks should be made.
       worst case we just double up this struct to fit in two
       storage slots or just accept the overflow. This data is
       not critical to Hedron's overall operation */
    struct DailyDataStore {
        uint72 dayMintedTotal;
        uint72 dayLoanedTotal;
        uint72 dayBurntTotal;
        uint32 dayInterestRate;
        uint8  dayMintMultiplier;
    }

    struct DailyDataCache {
        uint256 _dayMintedTotal;
        uint256 _dayLoanedTotal;
        uint256 _dayBurntTotal;
        uint256 _dayInterestRate;
        uint256 _dayMintMultiplier;
    }

    uint256 constant private _hdrnLaunchDays             = 100;     // length of the launch phase bonus in Hedron days
    uint256 constant private _hdrnLoanInterestResolution = 1000000; // loan interest decimal resolution
    uint256 constant private _hdrnLoanInterestDivisor    = 2;       // relation of Hedron's interest rate to HEX's interest rate
    uint256 constant private _hdrnLoanPaymentWindow      = 30;      // how many Hedron days to roll into a single payment
    uint256 constant private _hdrnLoanDefaultThreshold   = 90;      // how many Hedron days before loan liquidation is allowed
   
    HEX                                private _hx;
    uint256                            private _hxLaunch;
    HEXStakeInstanceManager            private _hsim;
    address                            public  hsim;
    mapping(address => ShareStore[])   public  shareLists;
    mapping(uint256 => DailyDataStore) public  dailyDataList;
    uint256                            public  loanedSupply;

    constructor(address hexAddress, uint256 hexLaunch) ERC20("Hedron", "HDRN") {
        // set HEX contract address and launch time
        _hx = HEX(payable(hexAddress));
        _hxLaunch = hexLaunch;

        // initialize HEX stake instance manager
        _hsim = new HEXStakeInstanceManager(hexAddress);
        hsim = _hsim.whoami();
    }

    function decimals()
        public
        view
        virtual
        override
        returns (uint8) 
    {
        return 9;
    }
    
    // Hedron Events

    event Mint(
        uint256 data,
        address indexed minter,
        uint40  indexed stakeId
    );

    event LoanStart(
        uint256 data,
        address indexed borrower,
        uint40  indexed stakeId
    );

    event LoanPayment(
        uint256 data,
        address indexed borrower,
        uint40  indexed stakeId
    );

    event LoanEnd(
        uint256 data,
        address indexed borrower,
        uint40  indexed stakeId
    );

    event LoanLiquidate(
        uint256 data,
        address indexed liquidator,
        uint40  indexed stakeId
    );

    // Hedron Private Functions

    function _emitMint(
        uint40 stakeId,
        uint256 stakeShares,
        uint256 mintedDays,
        uint256 launchBonus,
        uint256 payout
    )
        private
    {
        emit Mint(
            uint256(uint40(block.timestamp))
                | (uint256(uint72(stakeShares)) << 40)
                | (uint256(uint16(mintedDays)) << 112)
                | (uint256(uint8(launchBonus)) << 128)
                | (uint256(uint120(payout)) << 136),
            msg.sender,
            stakeId
        );
    }

    function _emitLoanStart(
        uint40 stakeId,
        uint256 stakeShares,
        uint256 loanedDays,
        uint256 interestRate,
        uint256 borrowed
    )
        private
    {
        emit LoanStart(
            uint256(uint40(block.timestamp))
                | (uint256(uint72(stakeShares)) << 40)
                | (uint256(uint16(loanedDays)) << 112)
                | (uint256(uint32(interestRate)) << 128)
                | (uint256(uint96(borrowed)) << 160),
            msg.sender,
            stakeId
        );
    }

    function _emitLoanPayment(
        uint40 stakeId,
        uint256 stakeShares,
        uint256 loanedDays,
        uint256 interestRate,
        uint256 paymentsMade,
        uint256 payment
    )
        private
    {
        emit LoanPayment(
            uint256(uint40(block.timestamp))
                | (uint256(uint72(stakeShares)) << 40)
                | (uint256(uint16(loanedDays)) << 112)
                | (uint256(uint32(interestRate)) << 128)
                | (uint256(uint8(paymentsMade)) << 160)
                | (uint256(uint88(payment)) << 168),
            msg.sender,
            stakeId
        );
    }

    function _emitLoanEnd(
        uint40 stakeId,
        uint256 stakeShares,
        uint256 loanedDays,
        uint256 interestRate,
        uint256 paymentsMade,
        uint256 payoff
    )
        private
    {
        emit LoanEnd(
            uint256(uint40(block.timestamp))
                | (uint256(uint72(stakeShares)) << 40)
                | (uint256(uint16(loanedDays)) << 112)
                | (uint256(uint32(interestRate)) << 128)
                | (uint256(uint8(paymentsMade)) << 160)
                | (uint256(uint88(payoff)) << 168),
            msg.sender,
            stakeId
        );
    }

    function _emitLoanLiquidate(
        uint40 stakeId,
        uint256 stakeShares,
        uint256 loanedDays,
        uint256 interestRate,
        uint256 paymentsMade,
        uint256 payoff
    )
        private
    {
        emit LoanLiquidate(
            uint256(uint40(block.timestamp))
                | (uint256(uint72(stakeShares)) << 40)
                | (uint256(uint16(loanedDays)) << 112)
                | (uint256(uint32(interestRate)) << 128)
                | (uint256(uint8(paymentsMade)) << 160)
                | (uint256(uint88(payoff)) << 168),
            msg.sender,
            stakeId
        );
    }

    // HEX Internal Functions

    /**
     * @dev Calculates the current HEX day.
     * @return A number representing the current HEX day.
     */
    function _hexCurrentDay()
        internal
        view
        returns (uint256)
    {
        return (block.timestamp - _hxLaunch) / 1 days;
    }
    
    /**
     * @dev Loads HEX daily data values from the HEX contract into a memory HEX daily data object.
     * @param hexDay The HEX day to obtain daily data for.
     * @return A memory HEX daily data object containing the daily data values returned by the HEX contract.
     */
    function _hexDailyDataLoad(
        uint256 hexDay
    )
        internal
        view
        returns (HEXDailyData memory)
    {
        uint72 dayPayoutTotal;
        uint72 dayStakeSharesTotal;
        uint56 dayUnclaimedSatoshisTotal;

        (dayPayoutTotal,
         dayStakeSharesTotal,
         dayUnclaimedSatoshisTotal) = _hx.dailyData(hexDay);

        return HEXDailyData(dayPayoutTotal,
                            dayStakeSharesTotal,
                            dayUnclaimedSatoshisTotal);

    }

    /**
     * @dev Loads HEX global values from the HEX contract into a memory HEX globals object.
     * @return A memory HEX globals object containing the global values returned by the HEX contract.
     */
    function _hexGlobalsLoad()
        internal
        view
        returns (HEXGlobals memory)
    {
        uint72 lockedHeartsTotal;
        uint72 nextStakeSharesTotal;
        uint40 shareRate;
        uint72 stakePenaltyTotal;
        uint16 dailyDataCount;
        uint72 stakeSharesTotal;
        uint40 latestStakeId;
        uint128 claimStats;

        (lockedHeartsTotal,
         nextStakeSharesTotal,
         shareRate,
         stakePenaltyTotal,
         dailyDataCount,
         stakeSharesTotal,
         latestStakeId,
         claimStats) = _hx.globals();

        return HEXGlobals(lockedHeartsTotal,
                          nextStakeSharesTotal,
                          shareRate,
                          stakePenaltyTotal,
                          dailyDataCount,
                          stakeSharesTotal,
                          latestStakeId,
                          claimStats);
    }

    /**
     * @dev Loads HEX stake values from the HEX contract into a memory HEX stake object.
     * @param stakeIndex The index of a HEX stake object in the sender's HEX stake list.
     * @return A memory HEX stake object containing the stake values returned by the HEX contract.
     */
    function _hexStakeLoad(
        uint256 stakeIndex
    )
        internal
        view
        returns (HEXStake memory)
    {
        uint40 stakeId;
        uint72 stakedHearts;
        uint72 stakeShares;
        uint16 lockedDay;
        uint16 stakedDays;
        uint16 unlockedDay;
        bool isAutoStake;
        
        (stakeId,
         stakedHearts,
         stakeShares,
         lockedDay,
         stakedDays,
         unlockedDay,
         isAutoStake) = _hx.stakeLists(msg.sender, stakeIndex);
         
         return HEXStake(stakeId,
                      stakedHearts,
                      stakeShares,
                      lockedDay,
                      stakedDays,
                      unlockedDay,
                      isAutoStake);
    }
    
    // Hedron Internal Functions

    /**
     * @dev Calculates the current Hedron day.
     * @return A number representing the current Hedron day.
     */
    function _currentDay()
        internal
        view
        returns (uint256)
    {
        return (block.timestamp - _hdrnLaunch) / 1 days;
    }

    /**
     * @dev Calculates the number of bonus tokens to be minted for minting bonuses.
     * @param multiplier Bonus multiplier increased by a factor of ten for decimal resolution.
     * @param payout Payout to apply the bonus multiplier towards.
     * @return The number of bonus tokens to mint.
     */
    function _calcBonus(
        uint256 multiplier, 
        uint256 payout
    )
        internal
        pure
        returns (uint256)
    {   
        return uint256((payout * multiplier) / 10);
    }

    /**
     * @dev Loads values from a storage daily data object into a memory daily data object.
     * @param dayStore Storage daily data object to be read.
     * @param day Memory daily data object to be populated with storage data.
     */
    function _dailyDataLoad(
        DailyDataStore storage dayStore,
        DailyDataCache memory day
    )
        internal
        view
    {
        day._dayMintedTotal    = dayStore.dayMintedTotal;
        day._dayLoanedTotal    = dayStore.dayLoanedTotal;
        day._dayBurntTotal     = dayStore.dayBurntTotal;
        day._dayInterestRate   = dayStore.dayInterestRate;
        day._dayMintMultiplier = dayStore.dayMintMultiplier;

        if (day._dayInterestRate == 0) {
            uint256             hexCurrentDay        = _hexCurrentDay();

            /* There is a very small window of time where it would be technically possible to pull
               HEX dailyData that is not yet defined. While unlikely to happen, we should prevent
               the possibility by pulling data from two days prior. This means our interest rate
               will slightly lag behind HEX's interest rate. */
            HEXDailyData memory hexDailyData         = _hexDailyDataLoad(hexCurrentDay - 2);
            HEXGlobals   memory hexGlobals           = _hexGlobalsLoad();
            uint256             hexDailyInterestRate = (hexDailyData.dayPayoutTotal * _hdrnLoanInterestResolution) / hexGlobals.lockedHeartsTotal;

            day._dayInterestRate = hexDailyInterestRate / _hdrnLoanInterestDivisor;

            /* Ideally we want a 50/50 split between loaned and minted Hedron. If less than 50% of the total supply is minted, allocate a bonus
               multiplier and scale it from 0 to 10. This is to attempt to prevent a situation where there is not enough available minted supply
               to cover loan interest. */
            if (loanedSupply > 0 && totalSupply() > 0) {
                uint256 loanedToMinted = (loanedSupply * 100) / totalSupply();
                if (loanedToMinted > 50) {
                    day._dayMintMultiplier = (loanedToMinted - 50) * 2;
                }
            }
        }
    }

    /**
     * @dev Updates a storage daily data object with values stored in memory.
     * @param dayStore Storage daily data object to be updated.
     * @param day Memory daily data object with updated values.
     */
    function _dailyDataUpdate(
        DailyDataStore storage dayStore,
        DailyDataCache memory day
    )
        internal
    {
        dayStore.dayMintedTotal    = uint72(day._dayMintedTotal);
        dayStore.dayLoanedTotal    = uint72(day._dayLoanedTotal);
        dayStore.dayBurntTotal     = uint72(day._dayBurntTotal);
        dayStore.dayInterestRate   = uint32(day._dayInterestRate);
        dayStore.dayMintMultiplier = uint8(day._dayMintMultiplier);
    }

    /**
     * @dev Loads share data from a HEX stake instance (HSI) contract into memory.
     * @param hsi The HEX stake instance object to load share data from.
     * @return A memory share object containing the share data of the HSI.
     */
    function _hsiLoad(
        HEXStakeInstance hsi
    ) 
        internal
        view
        returns (ShareCache memory)
    {
        HEXStake memory stake;
        uint16  mintedDays;
        uint8   launchBonus;
        uint16  loanStart;
        uint16  loanedDays;
        uint32  interestRate;
        uint8   paymentsMade;
        bool    isLoaned;

        (stake,
         mintedDays,
         launchBonus,
         loanStart,
         loanedDays,
         interestRate,
         paymentsMade,
         isLoaned) = hsi.share();

        return ShareCache(stake,
                          mintedDays,
                          launchBonus,
                          loanStart,
                          loanedDays,
                          interestRate,
                          paymentsMade,
                          isLoaned);
    }

    /**
     * @dev Determines if a share object refereces a HEX stake which no longer exists.
     * @param share A share object to compare against the senders HEX stake list.
     * @return a boolean value representing if the share object is stale or not.
     */
    function _isStaleShare (
        ShareCache memory share
    )
        internal
        view
        returns (bool)
    {
        uint256 stakeCount = _hx.stakeCount(msg.sender);
        for (uint256 i = 0; i < stakeCount; i++) {
            HEXStake memory stake = _hexStakeLoad(i);
            if (stake.stakeId == share._stake.stakeId) {
                // share is not stale
                return false;
            }
        }
        // share is stale
        return true;
    }
    
    /**
     * @dev Adds a new share element to a share list.
     * @param shareList List in which a new share will be added
     * @param stake The HEX stake object the new share element is tied to.
     * @param mintedDays Amount of Hedron days the HEX stake has been minted against.
     * @param launchBonus The launch bonus multiplier of the new share element.
     */
    function _shareAdd(
        ShareStore[] storage shareList,
        HEXStake memory stake,
        uint256 mintedDays,
        uint256 launchBonus
    )
        internal
    {
        shareList.push(
            ShareStore(
                stake,
                uint16(mintedDays),
                uint8(launchBonus),
                uint16(0),
                uint16(0),
                uint32(0),
                uint8(0),
                false
            )
        );
    }
    
    /**
     * @dev Loads values from a storage share object into a memory share object.
     * @param shareStore Storage share object to be read.
     * @param share Memory share object to be populated with storage data.
     */
    function _shareLoad(
        ShareStore storage shareStore,
        ShareCache memory share
    )
        internal
        view
    {
        share._stake = shareStore.stake;
        share._mintedDays = shareStore.mintedDays;
        share._launchBonus = shareStore.launchBonus;
    }
    
    /**
     * @dev Updates a storage share object with values stored in memory.
     * @param shareStore Storage share object to be updated.
     * @param share Memory share object with updated values.
     */
    function _shareUpdate(
        ShareStore storage shareStore,
        ShareCache memory share
    )
        internal
    {
        shareStore.stake = share._stake;
        shareStore.mintedDays = uint16(share._mintedDays);
        shareStore.launchBonus = uint8(share._launchBonus);
    }

    /**
     * @dev Attempts to match a HEX stake object to an existing share element within the sender's share list.
     * @param stake a HEX stake object to be matched.
     * @return a boolean indicating if the HEX stake was matched and it's index in the stake list as separate values.
     */
    function _shareSearch(
        HEXStake memory stake
    ) 
        internal
        returns (bool, uint256)
    {
        bool stakeInShareList = false;
        uint256 shareIndex = 0;
        uint256 mintDays = 0;
        uint256 payout = 0;
        
        ShareCache memory share;
        ShareStore[] storage shareList = shareLists[msg.sender];

        for(uint256 i = 0; i < shareList.length; i++){
            _shareLoad(shareList[i], share);
            
            // stake matches an existing share element
            if (share._stake.stakeId == stake.stakeId) {
                stakeInShareList = true;
                shareIndex = i;
            }
            
            // check if the share is stale
            else if (_isStaleShare(share)) {
                
                // unrealized tokens go to the source address
                mintDays = share._stake.stakedDays - share._mintedDays;
                payout = share._stake.stakeShares * mintDays;
                
                // launch phase bonus
                if (share._launchBonus > 0) {
                    uint256 bonus = _calcBonus(share._launchBonus, payout);
                    if (bonus > 0) {
                        payout += bonus;
                    }
                }
                
                // loan to mint ratio bonus does not apply here

                if (payout > 0) {
                    DailyDataCache memory day;
                    DailyDataStore storage dayStore = dailyDataList[_currentDay()];

                    _dailyDataLoad(dayStore, day);
            
                    _mint(_hdrnSourceAddress, payout);
            
                    day._dayMintedTotal += payout;
                    _dailyDataUpdate(dayStore, day);
                }

                // it's not safe to prune just yet
                delete shareList[i];
            }
        }

        return(stakeInShareList, shareIndex);
    }

    /**
     * @dev Iterates through the sender's share list and removes deleted elements.
     */
    function _sharePrune()
        internal
    {
        ShareCache memory share;
        ShareStore[] storage shareList = shareLists[msg.sender];

        for(uint256 i = 0; i < shareList.length; i++){
            
            _shareLoad(shareList[i], share);
            
            if (share._stake.stakeId == 0 &&
                share._stake.stakeShares == 0 &&
                share._stake.lockedDay == 0 &&
                share._stake.stakedDays == 0 &&
                share._mintedDays == 0 &&
                share._launchBonus == 0) {
                    
                uint256 lastIndex = shareList.length - 1;

                if (i != lastIndex) {
                    shareList[i] = shareList[lastIndex];
                }

                shareList.pop();
                
                if (i > 0) {
                    i--;
                }
            }
        }
    }

    // Hedron External Functions

    /**
     * @dev Retreives the number of share elements in an addresses share list.
     * @param user Address to retrieve the share list for.
     * @return The number of share elements found within the share list. 
     */
    function shareCount(
        address user
    )
        external
        view
        returns (uint256)
    {
        return shareLists[user].length;
    }
    
    /**
     * @dev Mints Hedron ERC20 (HDRN) tokens to the sender using a HEX stake instance (HSI) backing.
     * @param hsiIndex Index of the HSI contract address in the sender's HSI list (see hsiLists -> HEXStakeInstanceManager.sol).
     * @param hsiAddress Address of the HSI contract which coinsides with the index.
     */
    function mintInstanced(
        uint256 hsiIndex,
        address hsiAddress
    ) 
        external
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        DailyDataCache memory day;
        DailyDataStore storage dayStore = dailyDataList[_currentDay()];

        _dailyDataLoad(dayStore, day);

        address _hsiAddress = _hsim.hsiLists(msg.sender, hsiIndex);
        require(hsiAddress == _hsiAddress,
            "HDRN: HSI index address mismatch");

        ShareCache memory share = _hsiLoad(HEXStakeInstance(hsiAddress));
        require(_hexCurrentDay() >= share._stake.lockedDay,
            "HDRN: cannot mint against a pending HEX stake");
        require(share._isLoaned == false,
            "HDRN: cannot mint against a loaned HEX stake");

        uint256 servedDays = 0;
        uint256 mintDays = 0;
        uint256 payout = 0;
        uint256 launchBonus = 0;

        servedDays = _hexCurrentDay() - share._stake.lockedDay;
        
        // served days should never exceed staked days
        if (servedDays > share._stake.stakedDays) {
            servedDays = share._stake.stakedDays;
        }
        
        // remove days already minted from the payout
        mintDays = servedDays - share._mintedDays;

        // base payout
        payout = share._stake.stakeShares * mintDays;
               
        // launch phase bonus
        if (share._launchBonus > 0) {
            launchBonus = share._launchBonus;
            uint256 bonus = _calcBonus(launchBonus, payout);
            if (bonus > 0) {
                // send bonus copy to the source address
                _mint(_hdrnSourceAddress, bonus);
                payout += bonus;
            }
        }
        else if (_currentDay() < _hdrnLaunchDays) {
            launchBonus = _hdrnLaunchDays - _currentDay();
            share._launchBonus = launchBonus;
            uint256 bonus = _calcBonus(launchBonus, payout);
            if (bonus > 0) {
                // send bonus copy to the source address
                _mint(_hdrnSourceAddress, bonus);
                payout += bonus;
            }
        }

        // loan to mint ratio bonus
        if (day._dayMintMultiplier > 0) {
            uint256 bonus = _calcBonus(day._dayMintMultiplier, payout);
            if (bonus > 0) {
                // send bonus copy to the source address
                _mint(_hdrnSourceAddress, bonus);
                payout += bonus;
            }
        }
        
        // mint final payout to the sender
        if (payout > 0) {
            _mint(msg.sender, payout);
            _emitMint(share._stake.stakeId,
                      share._stake.stakeShares,
                      servedDays,
                      launchBonus,
                      payout
            );
        }

        share._mintedDays += mintDays;
        day._dayMintedTotal += payout;

        // update HEX stake instance
        _hsim.hsiUpdate(msg.sender, hsiAddress, share);

        _dailyDataUpdate(dayStore, day);
    }

    /**
     * @dev Mints unrealized Hedron ERC20 (HDRN) tokens to the source address using a HEX stake instance (HSI) backing.
     * @param hsiIndex Index of the HSI contract address in the sender's HSI list (see hsiLists -> HEXStakeInstanceManager.sol).
     * @param hsiAddress Address of the HSI contract which coinsides with the index.
     */
    function mintInstancedUnrealized(
        uint256 hsiIndex,
        address hsiAddress,
        address hsiEnderAddress
    ) 
        external
    {
        require(msg.sender == hsim,
            "HSIM: Caller must be HSIM");

        address _hsiAddress = _hsim.hsiLists(hsiEnderAddress, hsiIndex);
        require(hsiAddress == _hsiAddress,
            "HDRN: HSI index address mismatch");

        ShareCache memory share = _hsiLoad(HEXStakeInstance(hsiAddress));

        uint256 mintDays = 0;
        uint256 payout = 0;

        // unrealized tokens go to the source address
        mintDays = share._stake.stakedDays - share._mintedDays;
        payout = share._stake.stakeShares * mintDays;
                
        // launch phase bonus
        if (share._launchBonus > 0) {
            uint256 bonus = _calcBonus(share._launchBonus, payout);
            if (bonus > 0) {
                payout += bonus;
            }
        }
                
        // loan to mint ratio bonus does not apply here

        if (payout > 0) {
            DailyDataCache memory day;
            DailyDataStore storage dayStore = dailyDataList[_currentDay()];

            _dailyDataLoad(dayStore, day);

            _mint(_hdrnSourceAddress, payout);
            
            day._dayMintedTotal += payout;
            _dailyDataUpdate(dayStore, day);
        }
    }

    /**
     * @dev Mints Hedron ERC20 (HDRN) tokens to the sender using a native HEX stake backing.
     * @param stakeIndex Index of the HEX stake in sender's HEX stake list (see stakeLists -> HEX.sol).
     * @param stakeId ID of the HEX stake which coinsides with the index.
     */
    function mintNative(
        uint256 stakeIndex,
        uint40 stakeId
    )
        external
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        DailyDataCache memory day;
        DailyDataStore storage dayStore = dailyDataList[_currentDay()];

        _dailyDataLoad(dayStore, day);
        
        HEXStake memory stake = _hexStakeLoad(stakeIndex);
    
        require(stake.stakeId == stakeId,
            "HDRN: HEX stake index id mismatch");
        require(_hexCurrentDay() >= stake.lockedDay,
            "HDRN: cannot mint against a pending HEX stake");
        
        bool stakeInShareList = false;
        uint256 shareIndex = 0;
        uint256 servedDays = 0;
        uint256 mintDays = 0;
        uint256 payout = 0;
        uint256 launchBonus = 0;

        ShareCache memory share;
        ShareStore[] storage shareList = shareLists[msg.sender];
        
        // check if share element already exists in the sender's mapping
        (stakeInShareList,
         shareIndex) = _shareSearch(stake);
        
        // stake matches an existing share element
        if (stakeInShareList) {
            _shareLoad(shareList[shareIndex], share);
            
            servedDays = _hexCurrentDay() - share._stake.lockedDay;
            
            // served days should never exceed staked days
            if (servedDays > share._stake.stakedDays) {
                servedDays = share._stake.stakedDays;
            }
            
            // remove days already minted from the payout
            mintDays = servedDays - share._mintedDays;
            
            // base payout
            payout = share._stake.stakeShares * mintDays;
            
            // launch phase bonus
            if (share._launchBonus > 0) {
                uint256 bonus = _calcBonus(share._launchBonus, payout);
                if (bonus > 0) {
                    // send bonus copy to the source address
                    _mint(_hdrnSourceAddress, bonus);
                    payout += bonus;
                }
            }

            // loan to mint ratio bonus
            if (day._dayMintMultiplier > 0) {
                uint256 bonus = _calcBonus(day._dayMintMultiplier, payout);
                if (bonus > 0) {
                    // send bonus copy to the source address
                    _mint(_hdrnSourceAddress, bonus);
                    payout += bonus;
                }
            }
            
            // mint final payout to the sender
            if (payout > 0) {
                _mint(msg.sender, payout);
                _emitMint(share._stake.stakeId,
                          share._stake.stakeShares,
                          mintDays,
                          share._launchBonus,
                          payout
                );
            }
            
            share._mintedDays += mintDays;

            // update existing share mapping
            _shareUpdate(shareList[shareIndex], share);
        }
        
        // stake does not match an existing share element
        else {
            servedDays = _hexCurrentDay() - stake.lockedDay;
 
            // served days should never exceed staked days
            if (servedDays > stake.stakedDays) {
                servedDays = stake.stakedDays;
            }

            // base payout
            payout = stake.stakeShares * servedDays;
               
            // launch phase bonus
            if (_currentDay() < _hdrnLaunchDays) {
                launchBonus = _hdrnLaunchDays - _currentDay();
                uint256 bonus = _calcBonus(launchBonus, payout);
                if (bonus > 0) {
                    // send bonus copy to the source address
                    _mint(_hdrnSourceAddress, bonus);
                    payout += bonus;
                }
            }

            // loan to mint ratio bonus
            if (day._dayMintMultiplier > 0) {
                uint256 bonus = _calcBonus(day._dayMintMultiplier, payout);
                if (bonus > 0) {
                    // send bonus copy to the source address
                    _mint(_hdrnSourceAddress, bonus);
                    payout += bonus;
                }
            }
            
            // mint final payout to the sender
            if (payout > 0) {
                _mint(msg.sender, payout);
                _emitMint(stake.stakeId,
                          stake.stakeShares,
                          servedDays,
                          launchBonus,
                          payout
                );
            }
            
            // create a new share element for the sender
            _shareAdd(
                shareList,
                stake,
                servedDays,
                launchBonus
                );
        }

        day._dayMintedTotal += payout;
        
        // remove any stale share elements from the sender's mapping
        _sharePrune();

        _dailyDataUpdate(dayStore, day);
    }

    /**
     * @dev Calculates the payment for existing and non-existing HEX stake instance (HSI) loans.
     * @param hsiIndex Index of the HSI contract address in the sender's HSI list (see hsiLists -> HEXStakeInstanceManager.sol).
     * @param hsiAddress Address of the HSI contract which coinsides with the index.
     * @return The payment amount with principal and interest as serparate values.
     */
    function calcLoanPayment (
        uint256 hsiIndex,
        address hsiAddress
    ) 
        external
        view
        returns (uint256, uint256)
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        DailyDataCache memory day;
        DailyDataStore storage dayStore = dailyDataList[_currentDay()];

        _dailyDataLoad(dayStore, day);
        
        address _hsiAddress = _hsim.hsiLists(msg.sender, hsiIndex);
        require(hsiAddress == _hsiAddress,
            "HDRN: HSI index address mismatch");

        ShareCache   memory share         = _hsiLoad(HEXStakeInstance(hsiAddress));

        uint256 loanTermPaid      = share._paymentsMade * _hdrnLoanPaymentWindow;
        uint256 loanTermRemaining = share._loanedDays - loanTermPaid;
        uint256 principal         = 0;
        uint256 interest          = 0;

        // loan already exists
        if (share._interestRate > 0) {

            // remaining term is greater than a single payment window
            if (loanTermRemaining > _hdrnLoanPaymentWindow) {
                principal = share._stake.stakeShares * _hdrnLoanPaymentWindow;
                interest = (principal * (share._interestRate * _hdrnLoanPaymentWindow)) / _hdrnLoanInterestResolution;
            }
            // remaing term is less than or equal to a single payment window
            else {
                principal = share._stake.stakeShares * loanTermRemaining;
                interest = (principal * (share._interestRate * loanTermRemaining)) / _hdrnLoanInterestResolution;
            }
        }

        // loan does not exist
        else {

            // remaining term is greater than a single payment window
            if (share._stake.stakedDays > _hdrnLoanPaymentWindow) {
                principal = share._stake.stakeShares * _hdrnLoanPaymentWindow;
                interest = (principal * (day._dayInterestRate * _hdrnLoanPaymentWindow)) / _hdrnLoanInterestResolution;
            }
            // remaing term is less than or equal to a single payment window
            else {
                principal = share._stake.stakeShares * share._stake.stakedDays;
                interest = (principal * (day._dayInterestRate * share._stake.stakedDays)) / _hdrnLoanInterestResolution;
            }
        }

        return(principal, interest);
    }

    /**
     * @dev Calculates the full payoff for an existing HEX stake instance (HSI) loan calculating interest only up to the current Hedron day.
     * @param hsiIndex Index of the HSI contract address in the sender's HSI list (see hsiLists -> HEXStakeInstanceManager.sol).
     * @param hsiAddress Address of the HSI contract which coinsides with the index.
     * @return The payoff amount with principal and interest as separate values.
     */
    function calcLoanPayoff (
        uint256 hsiIndex,
        address hsiAddress
    ) 
        external
        view
        returns (uint256, uint256)
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        DailyDataCache memory day;
        DailyDataStore storage dayStore = dailyDataList[_currentDay()];

        _dailyDataLoad(dayStore, day);

        address _hsiAddress = _hsim.hsiLists(msg.sender, hsiIndex);

        require(hsiAddress == _hsiAddress,
            "HDRN: HSI index address mismatch");

        ShareCache memory share = _hsiLoad(HEXStakeInstance(hsiAddress));

        require (share._isLoaned == true,
            "HDRN: Cannot payoff non-existant loan");

        uint256 loanTermPaid      = share._paymentsMade * _hdrnLoanPaymentWindow;
        uint256 loanTermRemaining = share._loanedDays - loanTermPaid;
        uint256 outstandingDays   = 0;
        uint256 principal         = 0;
        uint256 interest          = 0;
        
        // user has made payments ahead of _currentDay(), no interest
        if (_currentDay()- share._loanStart < loanTermPaid) {
            principal = share._stake.stakeShares * loanTermRemaining;
        }

        // only calculate interest to the current Hedron day
        else {
            outstandingDays = _currentDay() - share._loanStart - loanTermPaid;

            if (outstandingDays > loanTermRemaining) {
                outstandingDays = loanTermRemaining;
            }

            principal       = share._stake.stakeShares * loanTermRemaining;
            interest        = (principal * (share._interestRate * outstandingDays)) / _hdrnLoanInterestResolution;
        }

        return(principal, interest);
    }

    /**
     * @dev Loans all unminted Hedron ERC20 (HDRN) tokens against a HEX stake instance (HSI).
     * @param hsiIndex Index of the HSI contract address in the sender's HSI list (see hsiLists -> HEXStakeInstanceManager.sol).
     * @param hsiAddress Address of the HSI contract which coinsides the index.
     */
    function loanInstanced (
        uint256 hsiIndex,
        address hsiAddress
    )
        external
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        DailyDataCache memory day;
        DailyDataStore storage dayStore = dailyDataList[_currentDay()];

        _dailyDataLoad(dayStore, day);

        address _hsiAddress = _hsim.hsiLists(msg.sender, hsiIndex);

        require(hsiAddress == _hsiAddress,
            "HDRN: HSI index address mismatch");

        ShareCache   memory share         = _hsiLoad(HEXStakeInstance(hsiAddress));

        require (share._isLoaned == false,
            "HDRN: HSI loan already exists");

        // only unminted days can be loaned upon
        uint256 loanDays = share._stake.stakedDays - share._mintedDays;

        require (loanDays > 0,
            "HDRN: No loanable days remaining");

        uint256 payout = share._stake.stakeShares * loanDays;

        // mint loaned tokens to the sender
        if (payout > 0) {
            _mint(msg.sender, payout);
            
            _emitLoanStart(
                share._stake.stakeId,
                share._stake.stakeShares,
                share._loanedDays,
                share._interestRate,
                payout
            );

            share._loanStart = _currentDay();
            share._loanedDays = loanDays;
            share._interestRate = day._dayInterestRate;
            share._isLoaned = true;
        }

        day._dayLoanedTotal += payout;
        loanedSupply += payout;

        // update HEX stake instance
        _hsim.hsiUpdate(msg.sender, hsiAddress, share);

        _dailyDataUpdate(dayStore, day);
    }

    /**
     * @dev Makes a single payment towards a HEX stake instance (HSI) loan.
     * @param hsiIndex Index of the HSI contract address in the sender's HSI list (see hsiLists -> HEXStakeInstanceManager.sol).
     * @param hsiAddress Address of the HSI contract which coinsides with the index.
     */
    function loanPayment (
        uint256 hsiIndex,
        address hsiAddress
    )
        external
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        DailyDataCache memory day;
        DailyDataStore storage dayStore = dailyDataList[_currentDay()];

        _dailyDataLoad(dayStore, day);

        address _hsiAddress = _hsim.hsiLists(msg.sender, hsiIndex);

        require(hsiAddress == _hsiAddress,
            "HDRN: HSI index address mismatch");

        ShareCache  memory share = _hsiLoad(HEXStakeInstance(hsiAddress));

        require (share._isLoaned == true,
            "HDRN: Cannot pay non-existant loan");

        uint256 loanTermPaid      = share._paymentsMade * _hdrnLoanPaymentWindow;
        uint256 loanTermRemaining = share._loanedDays - loanTermPaid;
        uint256 principal         = 0;
        uint256 interest          = 0;
        bool    lastPayment       = false;

        // increment payment counter
        share._paymentsMade++;

        // remaining term is greater than a single payment window
        if (loanTermRemaining > _hdrnLoanPaymentWindow) {
            principal = share._stake.stakeShares * _hdrnLoanPaymentWindow;
            interest = (principal * (share._interestRate * _hdrnLoanPaymentWindow)) / _hdrnLoanInterestResolution;
        }
        // remaing term is less than or equal to a single payment window
        else {
            principal = share._stake.stakeShares * loanTermRemaining;
            interest = (principal * (share._interestRate * loanTermRemaining)) / _hdrnLoanInterestResolution;
            lastPayment = true;
        }

        require (balanceOf(msg.sender) >= (principal + interest),
            "HDRN: Insufficient balance to facilitate payment");

        // burn payment from the sender
        _burn(msg.sender, (principal + interest));
        day._dayBurntTotal += (principal + interest);

        // remove pricipal from global loaned supply
        loanedSupply -= principal;

        _emitLoanPayment(
            share._stake.stakeId,
            share._stake.stakeShares,
            share._loanedDays,
            share._interestRate,
            share._paymentsMade,
            (principal + interest)
        );

        if (lastPayment == true) {
            share._loanStart = 0;
            share._loanedDays = 0;
            share._interestRate = 0;
            share._paymentsMade = 0;
            share._isLoaned = false;
        }

        // update HEX stake instance
        _hsim.hsiUpdate(msg.sender, hsiAddress, share);

        _dailyDataUpdate(dayStore, day);
    }

    /**
     * @dev Pays off a HEX stake instance (HSI) loan calculating interest only up to the current Hedron day.
     * @param hsiIndex Index of the HSI contract address in the sender's HSI list (see hsiLists -> HEXStakeInstanceManager.sol).
     * @param hsiAddress Address of the HSI contract which coinsides with the index.
     */
    function loanPayoff (
        uint256 hsiIndex,
        address hsiAddress
    )
        external
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        DailyDataCache memory day;
        DailyDataStore storage dayStore = dailyDataList[_currentDay()];

        _dailyDataLoad(dayStore, day);

        address _hsiAddress = _hsim.hsiLists(msg.sender, hsiIndex);

        require(hsiAddress == _hsiAddress,
            "HDRN: HSI index address mismatch");

        ShareCache  memory share = _hsiLoad(HEXStakeInstance(hsiAddress));

        require (share._isLoaned == true,
            "HDRN: Cannot payoff non-existant loan");

        uint256 loanTermPaid      = share._paymentsMade * _hdrnLoanPaymentWindow;
        uint256 loanTermRemaining = share._loanedDays - loanTermPaid;
        uint256 outstandingDays   = 0;
        uint256 principal         = 0;
        uint256 interest          = 0;

        // user has made payments ahead of _currentDay(), no interest
        if (_currentDay() - share._loanStart < loanTermPaid) {
            principal = share._stake.stakeShares * loanTermRemaining;
        }

        // only calculate interest to the current Hedron day
        else {
            outstandingDays = _currentDay() - share._loanStart - loanTermPaid;

            if (outstandingDays > loanTermRemaining) {
                outstandingDays = loanTermRemaining;
            }

            principal       = share._stake.stakeShares * loanTermRemaining;
            interest        = (principal * (share._interestRate * outstandingDays)) / _hdrnLoanInterestResolution;
        }

        require (balanceOf(msg.sender) >= (principal + interest),
            "HDRN: Insufficient balance to facilitate payoff");

        // burn payment from the sender
        _burn(msg.sender, (principal + interest));
        day._dayBurntTotal += (principal + interest);

        // remove pricipal from global loaned supply
        loanedSupply -= principal;

        _emitLoanEnd(
            share._stake.stakeId,
            share._stake.stakeShares,
            share._loanedDays,
            share._interestRate,
            share._paymentsMade,
            (principal + interest)
        );

        share._loanStart = 0;
        share._loanedDays = 0;
        share._interestRate = 0;
        share._paymentsMade = 0;
        share._isLoaned = false;

        // update HEX stake instance
        _hsim.hsiUpdate(msg.sender, hsiAddress, share);
         
        _dailyDataUpdate(dayStore, day);
    }

    /**
     * @dev Allows any address to liquidate a defaulted HEX stake instace (HSI) loan and claim the collateral.
     * @param owner Address of the current HSI contract owner.
     * @param hsiIndex Index of the HSI contract address in the owner's HSI list (see hsiLists -> HEXStakeInstanceManager.sol).
     * @param hsiAddress Address of the HSI contract which coinsides with the index.
     */
    function loanLiquidate (
        address owner,
        uint256 hsiIndex,
        address hsiAddress
    )
        external
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        address _hsiAddress = _hsim.hsiLists(owner, hsiIndex);

        DailyDataCache memory day;
        DailyDataStore storage dayStore = dailyDataList[_currentDay()];

        _dailyDataLoad(dayStore, day);

        require(hsiAddress == _hsiAddress,
            "HDRN: HSI index address mismatch");

        ShareCache  memory share = _hsiLoad(HEXStakeInstance(hsiAddress));

        require (share._isLoaned == true,
            "HDRN: Cannot liquidate a non-existant loan");

        uint256 loanTermPaid      = share._paymentsMade * _hdrnLoanPaymentWindow;
        uint256 loanTermRemaining = share._loanedDays - loanTermPaid;
        uint256 outstandingDays   = _currentDay() - share._loanStart - loanTermPaid;
        uint256 principal         = share._stake.stakeShares * loanTermRemaining;

        require (outstandingDays >= _hdrnLoanDefaultThreshold,
            "HDRN: Cannot liquidate a loan not in default");

        if (outstandingDays > loanTermRemaining) {
            outstandingDays = loanTermRemaining;
        }

        // only calculate interest to the current Hedron day
        uint256 interest = (principal * (share._interestRate * outstandingDays)) / _hdrnLoanInterestResolution;

        require (balanceOf(msg.sender) >= (principal + interest),
            "HDRN: Insufficient balance to facilitate liquidation");

        // burn payment from the sender
        _burn(msg.sender, (principal + interest));
        day._dayBurntTotal += (principal + interest);

        // remove pricipal from global loaned supply
        loanedSupply -= principal;

        _emitLoanLiquidate(
            share._stake.stakeId,
            share._stake.stakeShares,
            share._loanedDays,
            share._interestRate,
            share._paymentsMade,
            (principal + interest)
        );

        share._loanStart = 0;
        share._loanedDays = 0;
        share._interestRate = 0;
        share._paymentsMade = 0;
        share._isLoaned = false;

        // update HEX stake instance
        _hsim.hsiUpdate(owner, hsiAddress, share);

        // transfer ownership of the HEX stake instance
        _hsim.hsiTransfer(owner, hsiAddress, msg.sender);

        _dailyDataUpdate(dayStore, day);
    }
}