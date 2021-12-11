# Hedron

Hedron is an Ethereum / PulseChain smart contract that builds upon the HEX smart contract to provide additional functionality. For more information visit https://hedron.loans

These smart contracts are **UNLICENSED, All rights are reserved**. This repository provided for auditing, research, and interfacing purposes only. Copying these smart contracts for use on any non-testing blockchain is strictly prohibited.


## Contracts of Interest

**Hedron.sol** - ERC20 contract reposible for minting and loaning HDRN tokens against Native and Instanced HEX stakes.

**HEXStakeInstanceManager.sol** ERC721 contract used for managing Instanced HEX stakes as well as issuing NFT tokens which correspond to said Instanced HEX stakes.
 
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
