// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./HEXStakeInstance.sol";

contract HEXStakeInstanceManager is ERC721Enumerable {

    using Counters for Counters.Counter;

    Counters.Counter              private          _tokenIds;
    address                       private          _creator;
    address                       public           whoami;
    mapping(address => uint256)   public           hBalance;
    mapping(address => address[]) public           hsiLists;
    mapping(uint256 => address)   public           hsiToken;
 
    constructor() ERC721("HEX Stake Instance", "HSI") {
        /* While _creator could technically be considered an admin
           key, it is set at creation to the address of the parent
           contract as to restrict access to certain functions that
           only the parent contract should be able to call */ 
        _creator = msg.sender;
        whoami = address(this);
    }

    function _baseURI()
        internal
        view
        virtual
        override
        returns (string memory)
    {
        return "https://hedron.loan/api/hsi/";
    }

    /**
     * @dev Removes a HEX stake instance (HSI) contract address from an address mapping.
     * @param hsiList A mapped list of HSI contract addresses.
     * @param hsiIndex The index of the HSI contract address which will be removed.
     */
    function _pruneHSI(address[] storage hsiList, uint256 hsiIndex)
        internal
    {
        uint256 lastIndex = hsiList.length - 1;

        if (hsiIndex != lastIndex) {
            hsiList[hsiIndex] = hsiList[lastIndex];
        }

        hsiList.pop();
    }

    /**
     * @dev Loads share data from a HEX stake instance (HSI) into a ShareCache struct.
     * @param hsi A HSI contract object from which share data will be loaded.
     */
    function _hsiLoad(HEXStakeInstance hsi) 
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
     * @dev Transfers HEX ERC20 tokens from the sender's address to this contract's address and credits the sender.
     * @param amount Number of HEX ERC20 tokens to be transfered.
     */
    function hexDeposit (uint256 amount)
        external
        returns(uint256)
    { 
        require(_hx.transferFrom(msg.sender, whoami, amount),
            "HSIM: HEX transfer from message sender to HSIM failed.");

        hBalance[msg.sender] += amount;

        return hBalance[msg.sender];
    }

    /**
     * @dev Transfers HEX ERC20 tokens from this contracts's address to the sender's address and debits the sender.
     * @param amount Number of HEX ERC20 tokens to be transfered.
     */
    function hexWithdraw (uint256 amount)
        external
        returns(uint256)
    { 
        require(amount <= hBalance[msg.sender],
            "HSIM: Insufficient HEX to facilitate withdrawl.");

        require(_hx.transfer(msg.sender, amount),
            "HSIM: HEX transfer from HSIM to message sender failed.");

        hBalance[msg.sender] -= amount;

        return hBalance[msg.sender];
    }

    /**
     * @dev Creates a new HEX stake instance (HSI), transfers HEX ERC20 tokens to the HSI contract's address, and calls the "initialize" function.
     * @param amount Number of HEX ERC20 tokens to be staked.
     * @param length Number of days the HEX ERC20 tokens will be staked.
     */
    function hexStakeStart (uint256 amount, uint256 length)
        external
        returns(address)
    {
        require(amount <= hBalance[msg.sender],
            "HSIM: Insufficient HEX to facilitate stake.");

        address[] storage hsiList = hsiLists[msg.sender];

        HEXStakeInstance hsi = new HEXStakeInstance();
        address hsiAddress = hsi.whoami();

        require(_hx.transfer(hsiAddress, amount),
            "HSIM: HEX transfer from HSIM to HSI failed.");

        hBalance[msg.sender] -= amount;

        hsiList.push(hsiAddress);
        hsi.initialize(length);

        return hsiAddress;
    }

    /**
     * @dev Calls the HEX stake instance (HSI) function "destroy", transfers HEX ERC20 tokens from the HSI contract's address, and credits the sender's address.
     * @param hsiAddress Address of the HSI contract in which to call the "destroy" function.
     */
    function hexStakeEnd (address hsiAddress)
        external
        returns(bool)
    {
        address[] storage hsiList = hsiLists[msg.sender];

        for(uint256 i = 0; i < hsiList.length; i++) {
            if (hsiList[i] == hsiAddress) {
                HEXStakeInstance hsi = HEXStakeInstance(hsiAddress);
                ShareCache memory share = _hsiLoad(hsi);

                require (share._isLoaned == false,
                    "HSIM: Cannot call stakeEnd against a loaned stake.");

                hsi.destroy();

                uint256 hsiBalance = _hx.balanceOf(hsiAddress);

                if (hsiBalance > 0) {
                    require(_hx.transferFrom(hsiAddress, address(this), hsiBalance),
                        "HSIM: HEX transfer from HSI to HSIM failed.");

                    hBalance[msg.sender] += hsiBalance;
                }

                _pruneHSI(hsiList, i);

                return true;
            }
        }

        return false;
    }

    /**
     * @dev Converts a HEX stake instance (HSI) contract address mapping into a HSI ERC721 token.
     * @param hsiAddress Address of the HSI contract to be converted.
     */
    function hexStakeTokenize (address hsiAddress)
        external
        returns(uint256)
    {
        address[] storage hsiList = hsiLists[msg.sender];

        for(uint256 i = 0; i < hsiList.length; i++) {
            if (hsiList[i] == hsiAddress) {
                _tokenIds.increment();

                uint256 newTokenId = _tokenIds.current();

                _mint(msg.sender, newTokenId);
                hsiToken[newTokenId] = hsiAddress;

                _pruneHSI(hsiList, i);

                return newTokenId;
            }
        }

        revert();
    }

    /**
     * @dev Converts a HEX stake instance (HSI) ERC721 token into an address mapping.
     * @param tokenId ID of the HSI ERC721 token to be converted.
     */
    function hexStakeDetokenize (uint256 tokenId)
        external
        returns(address)
    {
        require(ownerOf(tokenId) == msg.sender,
            "HSIM: Detokenization requires token ownership.");

        address hsiAddress = hsiToken[tokenId];
        address[] storage hsiList = hsiLists[msg.sender];

        hsiList.push(hsiAddress);
        hsiToken[tokenId] = address(0);

        _burn(tokenId);

        return(hsiAddress);
    }

    /**
     * @dev Updates the share data of a HEX stake instance (HSI) contract.
     * @param owner Address of the HSI contract owner.
     * @param hsiAddress Address of the HSI contract to be updated.
     * @param share Updated share data in the form of a ShareCache struct.
     */
    function hsiUpdate (address owner, address hsiAddress, ShareCache memory share)
        external
    {
        require(msg.sender == _creator,
            "HSIM: Caller must be contract creator.");

        address[] storage hsiList = hsiLists[owner];

        for(uint256 i = 0; i < hsiList.length; i++) {
            if (hsiList[i] == hsiAddress) {
                HEXStakeInstance hsi = HEXStakeInstance(hsiAddress);
                hsi.update(share);
            }
        }
    }

    /**
     * @dev Transfers ownership of a HEX stake instance (HSI) contract to a new address.
     * @param currentOwner Address to transfer the HSI contract from.
     * @param hsiAddress Address of the HSI contract to be transfered.
     * @param newOwner Address to transfer to HSI contract to.
     */
    function hsiTransfer (address currentOwner, address hsiAddress, address newOwner)
        external
    {
        require(msg.sender == _creator,
            "HSIM: Caller must be contract creator.");

        address[] storage hsiListCurrent = hsiLists[currentOwner];
        address[] storage hsiListNew = hsiLists[newOwner];

        for(uint256 i = 0; i < hsiListCurrent.length; i++) {
            if (hsiListCurrent[i] == hsiAddress) {
                hsiListNew.push(hsiAddress);
                _pruneHSI(hsiListCurrent, i);
            }
        }
    }
}