// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./HEXStakeInstance.sol";
import "../Hedron.sol";

import "../rarible/royalties/contracts/impl/RoyaltiesV2Impl.sol";
import "../rarible/royalties/contracts/LibRoyaltiesV2.sol";

contract HEXStakeInstanceManager is ERC721, ERC721Enumerable, RoyaltiesV2Impl {

    using Counters for Counters.Counter;

    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;
    uint96 private constant _hsimRoyaltyBasis = 369; // Rarible V2 royalty basis
    
    Counters.Counter private _tokenIds;
    address          private _creator;
    HEX              private _hx;
    address          private _hxAddress;
    
    address                       public  whoami;
    mapping(address => uint256)   public  hexBalance;
    mapping(address => address[]) public  hsiLists;
    mapping(uint256 => address)   public  hsiToken;
 
    constructor(address hexAddress) ERC721("HEX Stake Instance", "HSI") {
        /* _creator is not an admin key. It is set at contsruction to be a link
           to the parent contract. In this case Hedron */
        _creator = msg.sender;
        whoami = address(this);

        // set HEX contract address
        _hx = HEX(payable(hexAddress));
        _hxAddress = hexAddress;
    }

    function _baseURI()
        internal
        view
        virtual
        override
        returns (string memory)
    {
        return "https://hedron.loans/api/hsi/";
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    )
        internal
        override(ERC721, ERC721Enumerable) 
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }


    event HSIStart(
        address indexed instance,
        address indexed staker
    );

    event HSIEnd(
        address indexed instance,
        address indexed staker
    );

    event HSITransfer(
        address indexed instance,
        address indexed oldStaker,
        address indexed newStaker
    );

    event HSITokenize(
        uint256 indexed tokenId,
        address indexed instance,
        address indexed staker
    );

    event HSIDetokenize(
        uint256 indexed tokenId,
        address indexed instance,
        address indexed staker
    );

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

    // Internal NFT Marketplace Glue

    /** @dev Sets the Rarible V2 royalties on a specific token
     *  @param tokenId Unique ID of the HSI NFT token.
     */
    function _setRoyalties(
        uint256 tokenId
    )
        internal
    {
        LibPart.Part[] memory _royalties = new LibPart.Part[](1);
        _royalties[0].value = _hsimRoyaltyBasis;
        _royalties[0].account = payable(_hdrnFlowAddress);
        _saveRoyalties(tokenId, _royalties);
    }

    /**
     * @dev Retreives the number of HSI elements in an addresses HSI list.
     * @param user Address to retrieve the HSI list for.
     * @return The number of HSI elements found within the HSI list. 
     */
    function hsiCount(
        address user
    )
        external
        view
        returns (uint256)
    {
        return hsiLists[user].length;
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
            "HSIM: HEX transfer from message sender to HSIM failed");

        hexBalance[msg.sender] += amount;

        return hexBalance[msg.sender];
    }

    /**
     * @dev Transfers HEX ERC20 tokens from this contracts's address to the sender's address and debits the sender.
     * @param amount Number of HEX ERC20 tokens to be transfered.
     */
    function hexWithdraw (uint256 amount)
        external
        returns(uint256)
    { 
        require(amount <= hexBalance[msg.sender],
            "HSIM: Insufficient HEX to facilitate withdrawl");

        require(_hx.transfer(msg.sender, amount),
            "HSIM: HEX transfer from HSIM to message sender failed");

        hexBalance[msg.sender] -= amount;

        return hexBalance[msg.sender];
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
        require(amount <= hexBalance[msg.sender],
            "HSIM: Insufficient HEX to facilitate stake");

        address[] storage hsiList = hsiLists[msg.sender];

        HEXStakeInstance hsi = new HEXStakeInstance(_hxAddress);
        address hsiAddress = hsi.whoami();

        require(_hx.transfer(hsiAddress, amount),
            "HSIM: HEX transfer from HSIM to HSI failed");

        hexBalance[msg.sender] -= amount;

        hsiList.push(hsiAddress);
        hsi.initialize(length);

        emit HSIStart(hsiAddress, msg.sender);

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
                    "HSIM: Cannot call stakeEnd against a loaned stake");

                Hedron hedron = Hedron(_creator);
                hedron.mintInstancedUnrealized(i, hsiAddress, msg.sender);

                hsi.destroy();

                emit HSIEnd(hsiAddress, msg.sender);

                uint256 hsiBalance = _hx.balanceOf(hsiAddress);

                if (hsiBalance > 0) {
                    require(_hx.transferFrom(hsiAddress, whoami, hsiBalance),
                        "HSIM: HEX transfer from HSI to HSIM failed");

                    hexBalance[msg.sender] += hsiBalance;
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
                HEXStakeInstance hsi = HEXStakeInstance(hsiAddress);
                ShareCache memory share = _hsiLoad(hsi);

                require (share._isLoaned == false,
                    "HSIM: Cannot tokenize a loaned stake");

                _tokenIds.increment();

                uint256 newTokenId = _tokenIds.current();

                _mint(msg.sender, newTokenId);
                hsiToken[newTokenId] = hsiAddress;

                _setRoyalties(newTokenId);

                _pruneHSI(hsiList, i);

                emit HSITokenize(newTokenId, hsiAddress, msg.sender);

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
            "HSIM: Detokenization requires token ownership");

        address hsiAddress = hsiToken[tokenId];
        address[] storage hsiList = hsiLists[msg.sender];

        hsiList.push(hsiAddress);
        hsiToken[tokenId] = address(0);

        _burn(tokenId);

        emit HSIDetokenize(tokenId, hsiAddress, msg.sender);

        return(hsiAddress);
    }

    /**
     * @dev Updates the share data of a HEX stake instance (HSI) contract.
     * @param holder Address of the HSI contract owner.
     * @param hsiAddress Address of the HSI contract to be updated.
     * @param share Updated share data in the form of a ShareCache struct.
     */
    function hsiUpdate (address holder, address hsiAddress, ShareCache memory share)
        external
    {
        require(msg.sender == _creator,
            "HSIM: Caller must be contract creator");

        address[] storage hsiList = hsiLists[holder];

        for(uint256 i = 0; i < hsiList.length; i++) {
            if (hsiList[i] == hsiAddress) {
                HEXStakeInstance hsi = HEXStakeInstance(hsiAddress);
                hsi.update(share);
            }
        }
    }

    /**
     * @dev Transfers ownership of a HEX stake instance (HSI) contract to a new address.
     * @param currentHolder Address to transfer the HSI contract from.
     * @param hsiAddress Address of the HSI contract to be transfered.
     * @param newHolder Address to transfer to HSI contract to.
     */
    function hsiTransfer (address currentHolder, address hsiAddress, address newHolder)
        external
    {
        require(msg.sender == _creator,
            "HSIM: Caller must be contract creator");

        address[] storage hsiListCurrent = hsiLists[currentHolder];
        address[] storage hsiListNew = hsiLists[newHolder];

        for(uint256 i = 0; i < hsiListCurrent.length; i++) {
            if (hsiListCurrent[i] == hsiAddress) {
                hsiListNew.push(hsiAddress);
                _pruneHSI(hsiListCurrent, i);

                emit HSITransfer(hsiAddress, currentHolder, newHolder);
            }
        }
    }

    // External NFT Marketplace Glue

    /**
     * @dev Implements ERC2981 royalty functionality. We just read the royalty data from
     *      the Rarible V2 implementation. 
     * @param tokenId Unique ID of the HSI NFT token.
     * @param salePrice Price the HSI NFT token was sold for.
     * @return receiver address to send the royalties to as well as the royalty amount.
     */
    function royaltyInfo(
        uint256 tokenId,
        uint256 salePrice
    )
        external
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        LibPart.Part[] memory _royalties = royalties[tokenId];
        
        if (_royalties.length > 0) {
            return (_royalties[0].account, (salePrice * _royalties[0].value) / 10000);
        }

        return (address(0), 0);
    }

    /**
     * @dev returns _hdrnFlowAddress, needed for some NFT marketplaces. This is not
            an admin key.
     * @return _hdrnFlowAddress
     */
    function owner()
        public
        pure
        returns (address) 
    {
        return _hdrnFlowAddress;
    }

    /**
     * @dev Adds Rarible V2 and ERC2981 interface support.
     * @param interfaceId Unique contract interface identifier.
     * @return true if the interface is supported, false if not.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        if (interfaceId == LibRoyaltiesV2._INTERFACE_ID_ROYALTIES) {
            return true;
        }

        if (interfaceId == _INTERFACE_ID_ERC2981) {
            return true;
        }

        return super.supportsInterface(interfaceId);
    }
}