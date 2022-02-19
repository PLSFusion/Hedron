// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./auxiliary/HEXStakeInstanceManager.sol";

/* Hedron is a collection of Ethereum / PulseChain smart contracts that  *
 * build upon the HEX smart contract to provide additional functionality */

contract Hedron is ERC20 {

    using Counters for Counters.Counter;

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

    struct LiquidationStore{
        uint256 liquidationStart;
        address hsiAddress;
        uint96  bidAmount;
        address liquidator;
        uint88  endOffset;
        bool    isActive;
    }

    struct LiquidationCache {
        uint256 _liquidationStart;
        address _hsiAddress;
        uint256 _bidAmount;
        address _liquidator;
        uint256 _endOffset;
        bool    _isActive;
    }

    uint256 constant private _hdrnLaunchDays             = 100;     // length of the launch phase bonus in Hedron days
    uint256 constant private _hdrnLoanInterestResolution = 1000000; // loan interest decimal resolution
    uint256 constant private _hdrnLoanInterestDivisor    = 2;       // relation of Hedron's interest rate to HEX's interest rate
    uint256 constant private _hdrnLoanPaymentWindow      = 30;      // how many Hedron days to roll into a single payment
    uint256 constant private _hdrnLoanDefaultThreshold   = 90;      // how many Hedron days before loan liquidation is allowed
   
    IHEX                                   private _hx;
    uint256                                private _hxLaunch;
    HEXStakeInstanceManager                private _hsim;
    Counters.Counter                       private _liquidationIds;
    address                                public  hsim;
    mapping(uint256 => ShareStore)         public  shareList;
    mapping(uint256 => DailyDataStore)     public  dailyDataList;
    mapping(uint256 => LiquidationStore)   public  liquidationList;
    uint256                                public  loanedSupply;

    constructor(
        address hexAddress,
        uint256 hexLaunch
    )
        ERC20("Hedron", "HDRN")
    {
        // set HEX contract address and launch time
        _hx = IHEX(payable(hexAddress));
        _hxLaunch = hexLaunch;

        // initialize HEX stake instance manager
        hsim = address(new HEXStakeInstanceManager(hexAddress));
        _hsim = HEXStakeInstanceManager(hsim);
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

    event Claim(
        uint256         data,
        address indexed claimant,
        uint40  indexed stakeId
    );

    event Mint(
        uint256         data,
        address indexed minter,
        uint40  indexed stakeId
    );

    event LoanStart(
        uint256         data,
        address indexed borrower,
        uint40  indexed stakeId
    );

    event LoanPayment(
        uint256         data,
        address indexed borrower,
        uint40  indexed stakeId
    );

    event LoanEnd(
        uint256         data,
        address indexed borrower,
        uint40  indexed stakeId
    );

    event LoanLiquidateStart(
        uint256         data,
        address indexed borrower,
        uint40  indexed stakeId,
        uint40  indexed liquidationId
    );

    event LoanLiquidateBid(
        uint256         data,
        address indexed bidder,
        uint40  indexed stakeId,
        uint40  indexed liquidationId
    );

    event LoanLiquidateExit(
        uint256         data,
        address indexed liquidator,
        uint40  indexed stakeId,
        uint40  indexed liquidationId
    );

    // Hedron Private Functions

    function _emitClaim(
        uint40  stakeId,
        uint256 stakeShares,
        uint256 launchBonus
    )
        private
    {
        emit Claim(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint72 (stakeShares)) << 40)
                |  (uint256(uint144(launchBonus)) << 112),
            msg.sender,
            stakeId
        );
    }

    function _emitMint(
        ShareCache memory share,
        uint256 payout
    )
        private
    {
        emit Mint(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint72 (share._stake.stakeShares)) << 40)
                |  (uint256(uint16 (share._mintedDays))        << 112)
                |  (uint256(uint8  (share._launchBonus))       << 128)
                |  (uint256(uint120(payout))                   << 136),
            msg.sender,
            share._stake.stakeId
        );
    }

    function _emitLoanStart(
        ShareCache memory share,
        uint256 borrowed
    )
        private
    {
        emit LoanStart(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint72(share._stake.stakeShares)) << 40)
                |  (uint256(uint16(share._loanedDays))        << 112)
                |  (uint256(uint32(share._interestRate))      << 128)
                |  (uint256(uint96(borrowed))                 << 160),
            msg.sender,
            share._stake.stakeId
        );
    }

    function _emitLoanPayment(
        ShareCache memory share,
        uint256 payment
    )
        private
    {
        emit LoanPayment(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint72(share._stake.stakeShares)) << 40)
                |  (uint256(uint16(share._loanedDays))        << 112)
                |  (uint256(uint32(share._interestRate))      << 128)
                |  (uint256(uint8 (share._paymentsMade))      << 160)
                |  (uint256(uint88(payment))                  << 168),
            msg.sender,
            share._stake.stakeId
        );
    }

    function _emitLoanEnd(
        ShareCache memory share,
        uint256 payoff
    )
        private
    {
        emit LoanEnd(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint72(share._stake.stakeShares)) << 40)
                |  (uint256(uint16(share._loanedDays))        << 112)
                |  (uint256(uint32(share._interestRate))      << 128)
                |  (uint256(uint8 (share._paymentsMade))      << 160)
                |  (uint256(uint88(payoff))                   << 168),
            msg.sender,
            share._stake.stakeId
        );
    }

    function _emitLoanLiquidateStart(
        ShareCache memory share,
        uint40  liquidationId,
        address borrower,
        uint256 startingBid
    )
        private
    {
        emit LoanLiquidateStart(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint72(share._stake.stakeShares)) << 40)
                |  (uint256(uint16(share._loanedDays))        << 112)
                |  (uint256(uint32(share._interestRate))      << 128)
                |  (uint256(uint8 (share._paymentsMade))      << 160)
                |  (uint256(uint88(startingBid))              << 168),
            borrower,
            share._stake.stakeId,
            liquidationId
        );
    }

    function _emitLoanLiquidateBid(
        uint40  stakeId,
        uint40  liquidationId,
        uint256 bidAmount
    )
        private
    {
        emit LoanLiquidateBid(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint216(bidAmount)) << 40),
            msg.sender,
            stakeId,
            liquidationId
        );
    }

    function _emitLoanLiquidateExit(
        uint40  stakeId,
        uint40  liquidationId,
        address liquidator,
        uint256 finalBid
    )
        private
    {
        emit LoanLiquidateExit(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint216(finalBid)) << 40),
            liquidator,
            stakeId,
            liquidationId
        );
    }

    // HEX Internal Functions

    /**
     * @dev Calculates the current HEX day.
     * @return Number representing the current HEX day.
     */
    function _hexCurrentDay()
        internal
        view
        returns (uint256)
    {
        return (block.timestamp - _hxLaunch) / 1 days;
    }
    
    /**
     * @dev Loads HEX daily data values from the HEX contract into a "HEXDailyData" object.
     * @param hexDay The HEX day to obtain daily data for.
     * @return "HEXDailyData" object containing the daily data values returned by the HEX contract.
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

        return HEXDailyData(
            dayPayoutTotal,
            dayStakeSharesTotal,
            dayUnclaimedSatoshisTotal
        );

    }

    /**
     * @dev Loads HEX global values from the HEX contract into a "HEXGlobals" object.
     * @return "HEXGlobals" object containing the global values returned by the HEX contract.
     */
    function _hexGlobalsLoad()
        internal
        view
        returns (HEXGlobals memory)
    {
        uint72  lockedHeartsTotal;
        uint72  nextStakeSharesTotal;
        uint40  shareRate;
        uint72  stakePenaltyTotal;
        uint16  dailyDataCount;
        uint72  stakeSharesTotal;
        uint40  latestStakeId;
        uint128 claimStats;

        (lockedHeartsTotal,
         nextStakeSharesTotal,
         shareRate,
         stakePenaltyTotal,
         dailyDataCount,
         stakeSharesTotal,
         latestStakeId,
         claimStats) = _hx.globals();

        return HEXGlobals(
            lockedHeartsTotal,
            nextStakeSharesTotal,
            shareRate,
            stakePenaltyTotal,
            dailyDataCount,
            stakeSharesTotal,
            latestStakeId,
            claimStats
        );
    }

    /**
     * @dev Loads HEX stake values from the HEX contract into a "HEXStake" object.
     * @param stakeIndex The index of the desired HEX stake within the sender's HEX stake list.
     * @return "HEXStake" object containing the stake values returned by the HEX contract.
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
        bool   isAutoStake;
        
        (stakeId,
         stakedHearts,
         stakeShares,
         lockedDay,
         stakedDays,
         unlockedDay,
         isAutoStake) = _hx.stakeLists(msg.sender, stakeIndex);
         
         return HEXStake(
            stakeId,
            stakedHearts,
            stakeShares,
            lockedDay,
            stakedDays,
            unlockedDay,
            isAutoStake
        );
    }
    
    // Hedron Internal Functions

    /**
     * @dev Calculates the current Hedron day.
     * @return Number representing the current Hedron day.
     */
    function _currentDay()
        internal
        view
        returns (uint256)
    {
        return (block.timestamp - _hdrnLaunch) / 1 days;
    }

    /**
     * @dev Calculates the multiplier to be used for the Launch Phase Bonus.
     * @param launchDay The current day of the Hedron launch phase.
     * @return Multiplier to use for the given launch day.
     */
    function _calcLPBMultiplier (
        uint256 launchDay
    )
        internal
        pure
        returns (uint256)
    {
        if (launchDay > 90) {
            return 100;
        }
        else if (launchDay > 80) {
            return 90;
        }
        else if (launchDay > 70) {
            return 80;
        }
        else if (launchDay > 60) {
            return 70;
        }
        else if (launchDay > 50) {
            return 60;
        }
        else if (launchDay > 40) {
            return 50;
        }
        else if (launchDay > 30) {
            return 40;
        }
        else if (launchDay > 20) {
            return 30;
        }
        else if (launchDay > 10) {
            return 20;
        }
        else if (launchDay > 0) {
            return 10;
        }

        return 0;
    }

    /**
     * @dev Calculates the number of bonus HDRN tokens to be minted in regards to minting bonuses.
     * @param multiplier The multiplier to use, increased by a factor of 10.
     * @param payout Payout to apply the multiplier towards.
     * @return Number of tokens to mint as a bonus.
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
     * @dev Loads values from a "DailyDataStore" object into a "DailyDataCache" object.
     * @param dayStore "DailyDataStore" object to be loaded.
     * @param day "DailyDataCache" object to be populated with storage data.
     */
    function _dailyDataLoad(
        DailyDataStore storage dayStore,
        DailyDataCache memory  day
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
            uint256 hexCurrentDay = _hexCurrentDay();

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
     * @dev Updates a "DailyDataStore" object with values stored in a "DailyDataCache" object.
     * @param dayStore "DailyDataStore" object to be updated.
     * @param day "DailyDataCache" object with updated values.
     */
    function _dailyDataUpdate(
        DailyDataStore storage dayStore,
        DailyDataCache memory  day
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
     * @dev Loads share data from a HEX stake instance (HSI) into a "ShareCache" object.
     * @param hsi The HSI to load share data from.
     * @return "ShareCache" object containing the share data of the HSI.
     */
    function _hsiLoad(
        HEXStakeInstance hsi
    ) 
        internal
        view
        returns (ShareCache memory)
    {
        HEXStakeMinimal memory stake;

        uint16 mintedDays;
        uint8  launchBonus;
        uint16 loanStart;
        uint16 loanedDays;
        uint32 interestRate;
        uint8  paymentsMade;
        bool   isLoaned;

        (stake,
         mintedDays,
         launchBonus,
         loanStart,
         loanedDays,
         interestRate,
         paymentsMade,
         isLoaned) = hsi.share();

        return ShareCache(
            stake,
            mintedDays,
            launchBonus,
            loanStart,
            loanedDays,
            interestRate,
            paymentsMade,
            isLoaned
        );
    }

    /**
     * @dev Creates (or overwrites) a new share element in the share list.
     * @param stake "HEXStakeMinimal" object with which the share element is tied to.
     * @param mintedDays Amount of Hedron days the HEX stake has been minted against.
     * @param launchBonus The launch bonus multiplier of the share element.
     * @param loanStart The Hedron day the loan was started
     * @param loanedDays Amount of Hedron days the HEX stake has been borrowed against.
     * @param interestRate The interest rate of the loan.
     * @param paymentsMade Amount of payments made towards the loan.
     * @param isLoaned Flag used to determine if the HEX stake is currently borrowed against..
     */
    function _shareAdd(
        HEXStakeMinimal memory stake,
        uint256 mintedDays,
        uint256 launchBonus,
        uint256 loanStart,
        uint256 loanedDays,
        uint256 interestRate,
        uint256 paymentsMade,
        bool    isLoaned
    )
        internal
    {
        shareList[stake.stakeId] =
            ShareStore(
                stake,
                uint16(mintedDays),
                uint8(launchBonus),
                uint16(loanStart),
                uint16(loanedDays),
                uint32(interestRate),
                uint8(paymentsMade),
                isLoaned
            );
    }

    /**
     * @dev Creates a new liquidation element in the liquidation list.
     * @param hsiAddress Address of the HEX Stake Instance (HSI) being liquidated.
     * @param liquidator Address of the user starting the liquidation process.
     * @param liquidatorBid Bid amount (in HDRN) the user is starting the liquidation process with.
     * @return ID of the liquidation element.
     */
    function _liquidationAdd(
        address hsiAddress,
        address liquidator,
        uint256 liquidatorBid
    )
        internal
        returns (uint256)
    {
        _liquidationIds.increment();

        liquidationList[_liquidationIds.current()] =
            LiquidationStore (
                block.timestamp,
                hsiAddress,
                uint96(liquidatorBid),
                liquidator,
                uint88(0),
                true
            );

        return _liquidationIds.current();
    }
    
    /**
     * @dev Loads values from a "ShareStore" object into a "ShareCache" object.
     * @param shareStore "ShareStore" object to be loaded.
     * @param share "ShareCache" object to be populated with storage data.
     */
    function _shareLoad(
        ShareStore storage shareStore,
        ShareCache memory  share
    )
        internal
        view
    {
        share._stake        = shareStore.stake;
        share._mintedDays   = shareStore.mintedDays;
        share._launchBonus  = shareStore.launchBonus;
        share._loanStart    = shareStore.loanStart;
        share._loanedDays   = shareStore.loanedDays;
        share._interestRate = shareStore.interestRate;
        share._paymentsMade = shareStore.paymentsMade;
        share._isLoaned     = shareStore.isLoaned;
    }

    /**
     * @dev Loads values from a "LiquidationStore" object into a "LiquidationCache" object.
     * @param liquidationStore "LiquidationStore" object to be loaded.
     * @param liquidation "LiquidationCache" object to be populated with storage data.
     */
    function _liquidationLoad(
        LiquidationStore storage liquidationStore,
        LiquidationCache memory  liquidation
    ) 
        internal
        view
    {
        liquidation._liquidationStart = liquidationStore.liquidationStart;
        liquidation._endOffset        = liquidationStore.endOffset;
        liquidation._hsiAddress       = liquidationStore.hsiAddress;
        liquidation._liquidator       = liquidationStore.liquidator;
        liquidation._bidAmount        = liquidationStore.bidAmount;
        liquidation._isActive         = liquidationStore.isActive;
    }
    
    /**
     * @dev Updates a "ShareStore" object with values stored in a "ShareCache" object.
     * @param shareStore "ShareStore" object to be updated.
     * @param share "ShareCache object with updated values.
     */
    function _shareUpdate(
        ShareStore storage shareStore,
        ShareCache memory  share
    )
        internal
    {
        shareStore.stake        = share._stake;
        shareStore.mintedDays   = uint16(share._mintedDays);
        shareStore.launchBonus  = uint8(share._launchBonus);
        shareStore.loanStart    = uint16(share._loanStart);
        shareStore.loanedDays   = uint16(share._loanedDays);
        shareStore.interestRate = uint32(share._interestRate);
        shareStore.paymentsMade = uint8(share._paymentsMade);
        shareStore.isLoaned     = share._isLoaned;
    }

    /**
     * @dev Updates a "LiquidationStore" object with values stored in a "LiquidationCache" object.
     * @param liquidationStore "LiquidationStore" object to be updated.
     * @param liquidation "LiquidationCache" object with updated values.
     */
    function _liquidationUpdate(
        LiquidationStore storage liquidationStore,
        LiquidationCache memory  liquidation
    ) 
        internal
    {
        liquidationStore.endOffset  = uint48(liquidation._endOffset);
        liquidationStore.hsiAddress = liquidation._hsiAddress;
        liquidationStore.liquidator = liquidation._liquidator;
        liquidationStore.bidAmount  = uint96(liquidation._bidAmount);
        liquidationStore.isActive   = liquidation._isActive;
    }

    /**
     * @dev Attempts to match a "HEXStake" object to an existing share element within the share list.
     * @param stake "HEXStake" object to be matched.
     * @return Boolean indicating if the HEX stake was matched and it's index within the stake list as separate values.
     */
    function _shareSearch(
        HEXStake memory stake
    ) 
        internal
        view
        returns (bool, uint256)
    {
        bool stakeInShareList = false;
        uint256 shareIndex = 0;
        
        ShareCache memory share;

        _shareLoad(shareList[stake.stakeId], share);
            
        // stake matches an existing share element
        if (share._stake.stakeId     == stake.stakeId &&
            share._stake.stakeShares == stake.stakeShares &&
            share._stake.lockedDay   == stake.lockedDay &&
            share._stake.stakedDays  == stake.stakedDays)
        {
            stakeInShareList = true;
            shareIndex = stake.stakeId;
        }
            
        return(stakeInShareList, shareIndex);
    }

    // Hedron External Functions

    /**
     * @dev Returns the current Hedron day.
     * @return Current Hedron day
     */
    function currentDay()
        external
        view
        returns (uint256)
    {
        return _currentDay();
    }

    /**
     * @dev Claims the launch phase bonus for a HEX stake instance (HSI). It also injects
     *      the HSI share data into into the shareList. This is a privileged  operation 
     *      only HEXStakeInstanceManager.sol can call.
     * @param hsiIndex Index of the HSI contract address in the sender's HSI list.
     *                 (see hsiLists -> HEXStakeInstanceManager.sol)
     * @param hsiAddress Address of the HSI contract which coinsides with the index.
     * @param hsiStarterAddress Address of the user creating the HSI.
     */
    function claimInstanced(
        uint256 hsiIndex,
        address hsiAddress,
        address hsiStarterAddress
    )
        external
    {
        require(msg.sender == hsim,
            "HSIM: Caller must be HSIM");

        address _hsiAddress = _hsim.hsiLists(hsiStarterAddress, hsiIndex);
        require(hsiAddress == _hsiAddress,
            "HDRN: HSI index address mismatch");

        ShareCache memory share = _hsiLoad(HEXStakeInstance(hsiAddress));

        if (_currentDay() < _hdrnLaunchDays) {
            share._launchBonus = _calcLPBMultiplier(_hdrnLaunchDays - _currentDay());
            _emitClaim(share._stake.stakeId, share._stake.stakeShares, share._launchBonus);
        }

        _hsim.hsiUpdate(hsiStarterAddress, hsiIndex, hsiAddress, share);

        _shareAdd(
            share._stake,
            share._mintedDays,
            share._launchBonus,
            share._loanStart,
            share._loanedDays,
            share._interestRate,
            share._paymentsMade,
            share._isLoaned
        );
    }
    
    /**
     * @dev Mints Hedron ERC20 (HDRN) tokens to the sender using a HEX stake instance (HSI) backing.
     *      HDRN Minted = HEX Stake B-Shares * (Days Served - Days Already Minted)
     * @param hsiIndex Index of the HSI contract address in the sender's HSI list.
     *                 (see hsiLists -> HEXStakeInstanceManager.sol)
     * @param hsiAddress Address of the HSI contract which coinsides with the index.
     * @return Amount of HDRN ERC20 tokens minted.
     */
    function mintInstanced(
        uint256 hsiIndex,
        address hsiAddress
    ) 
        external
        returns (uint256)
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        DailyDataCache memory  day;
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
        uint256 mintDays   = 0;
        uint256 payout     = 0;

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
                day._dayMintedTotal += bonus;
                payout += bonus;
            }
        }
        else if (_currentDay() < _hdrnLaunchDays) {
            share._launchBonus = _calcLPBMultiplier(_hdrnLaunchDays - _currentDay());
            uint256 bonus = _calcBonus(share._launchBonus, payout);
            if (bonus > 0) {
                // send bonus copy to the source address
                _mint(_hdrnSourceAddress, bonus);
                day._dayMintedTotal += bonus;
                payout += bonus;
            }
        }

        // loan to mint ratio bonus
        if (day._dayMintMultiplier > 0) {
            uint256 bonus = _calcBonus(day._dayMintMultiplier, payout);
            if (bonus > 0) {
                // send bonus copy to the source address
                _mint(_hdrnSourceAddress, bonus);
                day._dayMintedTotal += bonus;
                payout += bonus;
            }
        }
        
        share._mintedDays += mintDays;

        // mint final payout to the sender
        if (payout > 0) {
            _mint(msg.sender, payout);

            _emitMint(
                share,
                payout
            );
        }

        day._dayMintedTotal += payout;

        // update HEX stake instance
        _hsim.hsiUpdate(msg.sender, hsiIndex, hsiAddress, share);
        _shareUpdate(shareList[share._stake.stakeId], share);

        _dailyDataUpdate(dayStore, day);

        return payout;
    }
    
    /**
     * @dev Claims the launch phase bonus for a naitve HEX stake.
     * @param stakeIndex Index of the HEX stake in sender's HEX stake list.
     *                   (see stakeLists -> HEX.sol)
     * @param stakeId ID of the HEX stake which coinsides with the index.
     * @return Number representing the launch bonus of the claimed HEX stake
     *         increased by a factor of 10 for decimal resolution.
     */
    function claimNative(
        uint256 stakeIndex,
        uint40  stakeId
    )
        external
        returns (uint256)
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        HEXStake memory stake = _hexStakeLoad(stakeIndex);

        require(stake.stakeId == stakeId,
            "HDRN: HEX stake index id mismatch");

        bool stakeInShareList = false;
        uint256 shareIndex    = 0;
        uint256 launchBonus   = 0;
        
        // check if share element already exists in the sender's mapping
        (stakeInShareList,
         shareIndex) = _shareSearch(stake);

        require(stakeInShareList == false,
            "HDRN: HEX Stake already claimed");

        if (_currentDay() < _hdrnLaunchDays) {
            launchBonus = _calcLPBMultiplier(_hdrnLaunchDays - _currentDay());
            _emitClaim(stake.stakeId, stake.stakeShares, launchBonus);
        }

        _shareAdd(
            HEXStakeMinimal(
                stake.stakeId,
                stake.stakeShares,
                stake.lockedDay,
                stake.stakedDays
            ),
            0,
            launchBonus,
            0,
            0,
            0,
            0,
            false
        );

        return launchBonus;
    }

    /**
     * @dev Mints Hedron ERC20 (HDRN) tokens to the sender using a native HEX stake backing.
     *      HDRN Minted = HEX Stake B-Shares * (Days Served - Days Already Minted)
     * @param stakeIndex Index of the HEX stake in sender's HEX stake list (see stakeLists -> HEX.sol).
     * @param stakeId ID of the HEX stake which coinsides with the index.
     * @return Amount of HDRN ERC20 tokens minted.
     */
    function mintNative(
        uint256 stakeIndex,
        uint40 stakeId
    )
        external
        returns (uint256)
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        DailyDataCache memory  day;
        DailyDataStore storage dayStore = dailyDataList[_currentDay()];

        _dailyDataLoad(dayStore, day);
        
        HEXStake memory stake = _hexStakeLoad(stakeIndex);
    
        require(stake.stakeId == stakeId,
            "HDRN: HEX stake index id mismatch");
        require(_hexCurrentDay() >= stake.lockedDay,
            "HDRN: cannot mint against a pending HEX stake");
        
        bool stakeInShareList = false;
        uint256 shareIndex    = 0;
        uint256 servedDays    = 0;
        uint256 mintDays      = 0;
        uint256 payout        = 0;
        uint256 launchBonus   = 0;

        ShareCache memory share;
        
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
                    day._dayMintedTotal += bonus;
                    payout += bonus;
                }
            }

            // loan to mint ratio bonus
            if (day._dayMintMultiplier > 0) {
                uint256 bonus = _calcBonus(day._dayMintMultiplier, payout);
                if (bonus > 0) {
                    // send bonus copy to the source address
                    _mint(_hdrnSourceAddress, bonus);
                    day._dayMintedTotal += bonus;
                    payout += bonus;
                }
            }
            
            share._mintedDays += mintDays;

            // mint final payout to the sender
            if (payout > 0) {
                _mint(msg.sender, payout);

                _emitMint(
                    share,
                    payout
                );
            }
            
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
                launchBonus = _calcLPBMultiplier(_hdrnLaunchDays - _currentDay());
                uint256 bonus = _calcBonus(launchBonus, payout);
                if (bonus > 0) {
                    // send bonus copy to the source address
                    _mint(_hdrnSourceAddress, bonus);
                    day._dayMintedTotal += bonus;
                    payout += bonus;
                }
            }

            // loan to mint ratio bonus
            if (day._dayMintMultiplier > 0) {
                uint256 bonus = _calcBonus(day._dayMintMultiplier, payout);
                if (bonus > 0) {
                    // send bonus copy to the source address
                    _mint(_hdrnSourceAddress, bonus);
                    day._dayMintedTotal += bonus;
                    payout += bonus;
                }
            }

            // create a new share element for the sender
            _shareAdd(
                HEXStakeMinimal(
                    stake.stakeId,
                    stake.stakeShares, 
                    stake.lockedDay,
                    stake.stakedDays
                ),
                servedDays,
                launchBonus,
                0,
                0,
                0,
                0,
                false
            );

            _shareLoad(shareList[stake.stakeId], share);
            
            // mint final payout to the sender
            if (payout > 0) {
                _mint(msg.sender, payout);

                _emitMint(
                    share,
                    payout
                );
            }
        }

        day._dayMintedTotal += payout;
        
        _dailyDataUpdate(dayStore, day);

        return payout;
    }

    /**
     * @dev Calculates the payment for existing and non-existing HEX stake instance (HSI) loans.
     * @param borrower Address which has mapped ownership the HSI contract.
     * @param hsiIndex Index of the HSI contract address in the sender's HSI list.
     *                 (see hsiLists -> HEXStakeInstanceManager.sol)
     * @param hsiAddress Address of the HSI contract which coinsides with the index.
     * @return Payment amount with principal and interest as serparate values.
     */
    function calcLoanPayment (
        address borrower,
        uint256 hsiIndex,
        address hsiAddress
    ) 
        external
        view
        returns (uint256, uint256)
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        DailyDataCache memory  day;
        DailyDataStore storage dayStore = dailyDataList[_currentDay()];

        _dailyDataLoad(dayStore, day);
        
        address _hsiAddress = _hsim.hsiLists(borrower, hsiIndex);
        require(hsiAddress == _hsiAddress,
            "HDRN: HSI index address mismatch");

        ShareCache memory share = _hsiLoad(HEXStakeInstance(hsiAddress));

        uint256 loanTermPaid      = share._paymentsMade * _hdrnLoanPaymentWindow;
        uint256 loanTermRemaining = share._loanedDays - loanTermPaid;
        uint256 principal         = 0;
        uint256 interest          = 0;

        // loan already exists
        if (share._interestRate > 0) {

            // remaining term is greater than a single payment window
            if (loanTermRemaining > _hdrnLoanPaymentWindow) {
                principal = share._stake.stakeShares * _hdrnLoanPaymentWindow;
                interest  = (principal * (share._interestRate * _hdrnLoanPaymentWindow)) / _hdrnLoanInterestResolution;
            }
            // remaing term is less than or equal to a single payment window
            else {
                principal = share._stake.stakeShares * loanTermRemaining;
                interest  = (principal * (share._interestRate * loanTermRemaining)) / _hdrnLoanInterestResolution;
            }
        }

        // loan does not exist
        else {

            // remaining term is greater than a single payment window
            if (share._stake.stakedDays > _hdrnLoanPaymentWindow) {
                principal = share._stake.stakeShares * _hdrnLoanPaymentWindow;
                interest  = (principal * (day._dayInterestRate * _hdrnLoanPaymentWindow)) / _hdrnLoanInterestResolution;
            }
            // remaing term is less than or equal to a single payment window
            else {
                principal = share._stake.stakeShares * share._stake.stakedDays;
                interest  = (principal * (day._dayInterestRate * share._stake.stakedDays)) / _hdrnLoanInterestResolution;
            }
        }

        return(principal, interest);
    }

    /**
     * @dev Calculates the full payoff for an existing HEX stake instance (HSI) loan calculating interest only up to the current Hedron day.
     * @param borrower Address which has mapped ownership the HSI contract.
     * @param hsiIndex Index of the HSI contract address in the sender's HSI list.
     *                 (see hsiLists -> HEXStakeInstanceManager.sol)
     * @param hsiAddress Address of the HSI contract which coinsides with the index.
     * @return Payoff amount with principal and interest as separate values.
     */
    function calcLoanPayoff (
        address borrower,
        uint256 hsiIndex,
        address hsiAddress
    ) 
        external
        view
        returns (uint256, uint256)
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        DailyDataCache memory  day;
        DailyDataStore storage dayStore = dailyDataList[_currentDay()];

        _dailyDataLoad(dayStore, day);

        address _hsiAddress = _hsim.hsiLists(borrower, hsiIndex);

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
        if (_currentDay() - share._loanStart < loanTermPaid) {
            principal = share._stake.stakeShares * loanTermRemaining;
        }

        // only calculate interest to the current Hedron day
        else {
            outstandingDays = _currentDay() - share._loanStart - loanTermPaid;

            if (outstandingDays > loanTermRemaining) {
                outstandingDays = loanTermRemaining;
            }

            principal = share._stake.stakeShares * loanTermRemaining;
            interest  = ((share._stake.stakeShares * outstandingDays) * (share._interestRate * outstandingDays)) / _hdrnLoanInterestResolution;
        }

        return(principal, interest);
    }

    /**
     * @dev Loans all unminted Hedron ERC20 (HDRN) tokens against a HEX stake instance (HSI).
     *      HDRN Loaned = HEX Stake B-Shares * (Days Staked - Days Already Minted)
     * @param hsiIndex Index of the HSI contract address in the sender's HSI list.
     *                 (see hsiLists -> HEXStakeInstanceManager.sol)
     * @param hsiAddress Address of the HSI contract which coinsides the index.
     * @return Amount of HDRN ERC20 tokens borrowed.
     */
    function loanInstanced (
        uint256 hsiIndex,
        address hsiAddress
    )
        external
        returns (uint256)
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        DailyDataCache memory  day;
        DailyDataStore storage dayStore = dailyDataList[_currentDay()];

        _dailyDataLoad(dayStore, day);

        address _hsiAddress = _hsim.hsiLists(msg.sender, hsiIndex);

        require(hsiAddress == _hsiAddress,
            "HDRN: HSI index address mismatch");

        ShareCache memory share = _hsiLoad(HEXStakeInstance(hsiAddress));

        require (share._isLoaned == false,
            "HDRN: HSI loan already exists");

        // only unminted days can be loaned upon
        uint256 loanDays = share._stake.stakedDays - share._mintedDays;

        require (loanDays > 0,
            "HDRN: No loanable days remaining");

        uint256 payout = share._stake.stakeShares * loanDays;

        // mint loaned tokens to the sender
        if (payout > 0) {
            share._loanStart    = _currentDay();
            share._loanedDays   = loanDays;
            share._interestRate = day._dayInterestRate;
            share._isLoaned     = true;

            _emitLoanStart(
                share,
                payout
            );

            day._dayLoanedTotal += payout;
            loanedSupply += payout;

            // update HEX stake instance
            _hsim.hsiUpdate(msg.sender, hsiIndex, hsiAddress, share);
            _shareUpdate(shareList[share._stake.stakeId], share);

            _dailyDataUpdate(dayStore, day);

            _mint(msg.sender, payout);
        }

        return payout;
    }

    /**
     * @dev Makes a single payment towards a HEX stake instance (HSI) loan.
     * @param hsiIndex Index of the HSI contract address in the sender's HSI list.
     *                 (see hsiLists -> HEXStakeInstanceManager.sol)
     * @param hsiAddress Address of the HSI contract which coinsides with the index.
     * @return Amount of HDRN ERC20 burnt to facilitate the payment.
     */
    function loanPayment (
        uint256 hsiIndex,
        address hsiAddress
    )
        external
        returns (uint256)
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        DailyDataCache memory  day;
        DailyDataStore storage dayStore = dailyDataList[_currentDay()];

        _dailyDataLoad(dayStore, day);

        address _hsiAddress = _hsim.hsiLists(msg.sender, hsiIndex);

        require(hsiAddress == _hsiAddress,
            "HDRN: HSI index address mismatch");

        ShareCache memory share = _hsiLoad(HEXStakeInstance(hsiAddress));

        require (share._isLoaned == true,
            "HDRN: Cannot pay non-existant loan");

        uint256 loanTermPaid      = share._paymentsMade * _hdrnLoanPaymentWindow;
        uint256 loanTermRemaining = share._loanedDays - loanTermPaid;
        uint256 principal         = 0;
        uint256 interest          = 0;
        bool    lastPayment       = false;

        // remaining term is greater than a single payment window
        if (loanTermRemaining > _hdrnLoanPaymentWindow) {
            principal = share._stake.stakeShares * _hdrnLoanPaymentWindow;
            interest  = (principal * (share._interestRate * _hdrnLoanPaymentWindow)) / _hdrnLoanInterestResolution;
        }
        // remaing term is less than or equal to a single payment window
        else {
            principal   = share._stake.stakeShares * loanTermRemaining;
            interest    = (principal * (share._interestRate * loanTermRemaining)) / _hdrnLoanInterestResolution;
            lastPayment = true;
        }

        require (balanceOf(msg.sender) >= (principal + interest),
            "HDRN: Insufficient balance to facilitate payment");

        // increment payment counter
        share._paymentsMade++;

        _emitLoanPayment(
            share,
            (principal + interest)
        );

        if (lastPayment == true) {
            share._loanStart    = 0;
            share._loanedDays   = 0;
            share._interestRate = 0;
            share._paymentsMade = 0;
            share._isLoaned     = false;
        }

        // update HEX stake instance
        _hsim.hsiUpdate(msg.sender, hsiIndex, hsiAddress, share);
        _shareUpdate(shareList[share._stake.stakeId], share);

        // update daily data
        day._dayBurntTotal += (principal + interest);
        _dailyDataUpdate(dayStore, day);

        // remove pricipal from global loaned supply
        loanedSupply -= principal;

        // burn payment from the sender
        _burn(msg.sender, (principal + interest));

        return(principal + interest);
    }

    /**
     * @dev Pays off a HEX stake instance (HSI) loan calculating interest only up to the current Hedron day.
     * @param hsiIndex Index of the HSI contract address in the sender's HSI list.
     *                 (see hsiLists -> HEXStakeInstanceManager.sol)
     * @param hsiAddress Address of the HSI contract which coinsides with the index.
     * @return Amount of HDRN ERC20 burnt to facilitate the payoff.
     */
    function loanPayoff (
        uint256 hsiIndex,
        address hsiAddress
    )
        external
        returns (uint256)
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        DailyDataCache memory  day;
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
        if (_currentDay() - share._loanStart < loanTermPaid) {
            principal = share._stake.stakeShares * loanTermRemaining;
        }

        // only calculate interest to the current Hedron day
        else {
            outstandingDays = _currentDay() - share._loanStart - loanTermPaid;

            if (outstandingDays > loanTermRemaining) {
                outstandingDays = loanTermRemaining;
            }

            principal = share._stake.stakeShares * loanTermRemaining;
            interest  = ((share._stake.stakeShares * outstandingDays) * (share._interestRate * outstandingDays)) / _hdrnLoanInterestResolution;
        }

        require (balanceOf(msg.sender) >= (principal + interest),
            "HDRN: Insufficient balance to facilitate payoff");

        _emitLoanEnd(
            share,
            (principal + interest)
        );

        share._loanStart    = 0;
        share._loanedDays   = 0;
        share._interestRate = 0;
        share._paymentsMade = 0;
        share._isLoaned     = false;

        // update HEX stake instance
        _hsim.hsiUpdate(msg.sender, hsiIndex, hsiAddress, share);
        _shareUpdate(shareList[share._stake.stakeId], share);

        // update daily data 
        day._dayBurntTotal += (principal + interest);
        _dailyDataUpdate(dayStore, day);

        // remove pricipal from global loaned supply
        loanedSupply -= principal;

        // burn payment from the sender
        _burn(msg.sender, (principal + interest));

        return(principal + interest);
    }

    /**
     * @dev Allows any address to liquidate a defaulted HEX stake instace (HSI) loan and start the liquidation process.
     * @param owner Address of the current HSI contract owner.
     * @param hsiIndex Index of the HSI contract address in the owner's HSI list.
     *                 (see hsiLists -> HEXStakeInstanceManager.sol)
     * @param hsiAddress Address of the HSI contract which coinsides with the index.
     * @return Amount of HDRN ERC20 tokens burnt as the initial liquidation bid.
     */
    function loanLiquidate (
        address owner,
        uint256 hsiIndex,
        address hsiAddress
    )
        external
        returns (uint256)
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        address _hsiAddress = _hsim.hsiLists(owner, hsiIndex);

        require(hsiAddress == _hsiAddress,
            "HDRN: HSI index address mismatch");

        ShareCache memory share = _hsiLoad(HEXStakeInstance(hsiAddress));

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
        uint256 interest = ((share._stake.stakeShares * outstandingDays) * (share._interestRate * outstandingDays)) / _hdrnLoanInterestResolution;

        require (balanceOf(msg.sender) >= (principal + interest),
            "HDRN: Insufficient balance to facilitate liquidation");

        // zero out loan data
        share._loanStart    = 0;
        share._loanedDays   = 0;
        share._interestRate = 0;
        share._paymentsMade = 0;
        share._isLoaned     = false;

        // update HEX stake instance
        _hsim.hsiUpdate(owner, hsiIndex, hsiAddress, share);
        _shareUpdate(shareList[share._stake.stakeId], share);

        // transfer ownership of the HEX stake instance to a temporary holding address
        _hsim.hsiTransfer(owner, hsiIndex, hsiAddress, address(0));

        // create a new liquidation element
        _liquidationAdd(hsiAddress, msg.sender, (principal + interest));

        _emitLoanLiquidateStart(
            share,
            uint40(_liquidationIds.current()),
            owner,
            (principal + interest)
        );

        // remove pricipal from global loaned supply
        loanedSupply -= principal;

        // burn payment from the sender
        _burn(msg.sender, (principal + interest));

        return(principal + interest);
    }

    /**
     * @dev Allows any address to enter a bid into an active liquidation.
     * @param liquidationId ID number of the liquidation to place the bid in.
     * @param liquidationBid Amount of HDRN to bid.
     * @return Block timestamp of when the liquidation is currently scheduled to end.
     */
    function loanLiquidateBid (
        uint256 liquidationId,
        uint256 liquidationBid
    )
        external
        returns (uint256)
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        LiquidationCache memory  liquidation;
        LiquidationStore storage liquidationStore = liquidationList[liquidationId];
        
        _liquidationLoad(liquidationStore, liquidation);

        require(liquidation._isActive == true,
            "HDRN: Cannot bid on invalid liquidation");

        require (balanceOf(msg.sender) >= liquidationBid,
            "HDRN: Insufficient balance to facilitate liquidation");

        require (liquidationBid > liquidation._bidAmount,
            "HDRN: Liquidation bid must be greater than current bid");

        require((block.timestamp - (liquidation._liquidationStart + liquidation._endOffset)) <= 86400,
            "HDRN: Cannot bid on expired liquidation");

        // if the bid is being placed in the last five minutes
        uint256 timestampModified = ((block.timestamp + 300) - (liquidation._liquidationStart + liquidation._endOffset));
        if (timestampModified > 86400) {
            liquidation._endOffset += (timestampModified - 86400);
        }

        // give the previous bidder back their HDRN
        _mint(liquidation._liquidator, liquidation._bidAmount);

        // new bidder takes the liquidation position
        liquidation._liquidator = msg.sender;
        liquidation._bidAmount  = liquidationBid;

        _liquidationUpdate(liquidationStore, liquidation);

        ShareCache memory share = _hsiLoad(HEXStakeInstance(liquidation._hsiAddress));

        _emitLoanLiquidateBid(
            share._stake.stakeId,
            uint40(liquidationId),
            liquidationBid
        );

        // burn the new bidders bid amount
        _burn(msg.sender, liquidationBid);

        return(
            liquidation._liquidationStart +
            liquidation._endOffset +
            86400
        );
    }

    /**
     * @dev Allows any address to exit a completed liquidation, granting control of the
            HSI to the highest bidder.
     * @param hsiIndex Index of the HSI contract address in the zero address's HSI list.
     *                 (see hsiLists -> HEXStakeInstanceManager.sol)
     * @param liquidationId ID number of the liquidation to exit.
     * @return Address of the HEX Stake Instance (HSI) contract granted to the liquidator.
     */
    function loanLiquidateExit (
        uint256 hsiIndex,
        uint256 liquidationId
    )
        external
        returns (address)
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        DailyDataCache memory  day;
        DailyDataStore storage dayStore = dailyDataList[_currentDay()];

        _dailyDataLoad(dayStore, day);

        LiquidationStore storage liquidationStore = liquidationList[liquidationId];
        LiquidationCache memory  liquidation;

        _liquidationLoad(liquidationStore, liquidation);
        
        require(liquidation._isActive == true,
            "HDRN: Cannot exit on invalid liquidation");

        require((block.timestamp - (liquidation._liquidationStart + liquidation._endOffset)) >= 86400,
            "HDRN: Cannot exit on active liquidation");

        // transfer the held HSI to the liquidator
        _hsim.hsiTransfer(address(0), hsiIndex, liquidation._hsiAddress, liquidation._liquidator);

        // update the daily burnt total
        day._dayBurntTotal += liquidation._bidAmount;

        // deactivate liquidation, but keep data around for historical reasons.
        liquidation._isActive == false;

        ShareCache memory share = _hsiLoad(HEXStakeInstance(liquidation._hsiAddress));

        _emitLoanLiquidateExit(
            share._stake.stakeId,
            uint40(liquidationId),
            liquidation._liquidator,
            liquidation._bidAmount
        );

        _dailyDataUpdate(dayStore, day);
        _liquidationUpdate(liquidationStore, liquidation);

        return liquidation._hsiAddress;
    }

    /**
     * @dev Burns HDRN tokens from the caller's address.
     * @param amount Amount of HDRN to burn.
     */
    function proofOfBenevolence (
        uint256 amount
    )
        external
    {
        require(block.timestamp >= _hdrnLaunch,
            "HDRN: Contract not yet active");

        DailyDataCache memory  day;
        DailyDataStore storage dayStore = dailyDataList[_currentDay()];

        _dailyDataLoad(dayStore, day);

        require (balanceOf(msg.sender) >= amount,
            "HDRN: Insufficient balance to facilitate PoB");

        uint256 currentAllowance = allowance(msg.sender, address(this));

        require(currentAllowance >= amount,
            "HDRN: Burn amount exceeds allowance");
        
        day._dayBurntTotal += amount;
        _dailyDataUpdate(dayStore, day);

        unchecked {
            _approve(msg.sender, address(this), currentAllowance - amount);
        }

        _burn(msg.sender, amount);
    }
}