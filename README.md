# Hedron

Hedron is a collection of Ethereum / PulseChain smart contracts that build upon the HEX smart contract to provide additional functionality. For more information visit https://hedron.pro


The following smart contracts are **UNLICENSED, All rights are reserved**. 

    ./contracts/Hedron.sol
    ./contracts/references/HEX.sol
    ./contracts/auxiliary/HEXStakeInstance.sol
    ./contracts/auxiliary/HEXStakeInstanceManager.sol


The following smart contracts are **MIT Licensed**. 

    ./contracts/Hedron.sol
    ./contracts/interfaces/HEX.sol
    ./contracts/interfaces/Hedron.sol
    ./contracts/declarations/Internal.sol
    ./contracts/declarations/External.sol
    ./contracts/interfaces/HEXStakeInstance.sol
    ./contracts/interfaces/HEXStakeInstanceManager.sol
    ./contracts/rarible/royalties/contracts/LibPart.sol
    ./contracts/rarible/royalties/contracts/RoyaltiesV2.sol
    ./contracts/rarible/royalties/contracts/LibRoyaltiesV2.sol
    ./contracts/rarible/royalties/contracts/impl/RoyaltiesV2Impl.sol
    ./contracts/rarible/royalties/contracts/impl/AbstractRoyalties.sol


This repository provided for auditing, research, and interfacing purposes only. Copying any **UNLICENSED** smart contracts is strictly prohibited.


## Contracts of Interest

**Hedron.sol** - ERC20 contract responsible for minting and loaning HDRN tokens against Native and Instanced HEX stakes.

**HEXStakeInstanceManager.sol** ERC721 contract used for managing Instanced HEX stakes as well as issuing NFT tokens which correspond to said stakes.
 
**HEXStakeInstance.sol** Single use contract used to wrap a single HEX stake.

## Documentation / ABI

Documentation and ABI can be generated automatically by cloning this repository, installing all required HardHat dependencies, and compiling the contracts.

    git clone https://https://github.com/SeminaTempus/Hedron.git
    cd Hedron
    npm install
    npx hardhat compile

Documentation and ABI can be found in the `./docs` and `./abi` directories respectively after a successful compilation.

## Tests

Tests can be run by executing...

    npx hardhat test
