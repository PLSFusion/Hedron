require("@nomiclabs/hardhat-waffle");
require('hardhat-abi-exporter');
require('hardhat-docgen');
require("hardhat-gas-reporter");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.5.13",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          },
        },
      },
      {
        version: "0.8.9",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          },
        },
      },
    ],
  },
  networks: {
    hardhat: {
      initialDate: "2019-12-02"
    },
    pulsetestv1: {
      url: "https://rpc.testnet.pulsechain.com",
      chainId: 940,
      // these are publicly known, just for testing
      accounts: [ "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
                  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
                  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
      ],
      gasPrice: 8000000000
    },
    pulsetestv2: {
      url: "https://rpc.v2.testnet.pulsechain.com",
      chainId: 940,
      // these are publicly known, just for testing
      accounts: [ "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
                  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
                  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
      ],
      gasPrice: 8000000000
    }
  },
  abiExporter: {
    runOnCompile: true,
    clear: true,
    flat: true,
    only: [':HEX$',
           ':Hedron$',
           ':HEXStakeInstance$',
           ':HEXStakeInstanceManager$'
    ]
  },
  docgen: {
    path: './docs',
    clear: true,
    runOnCompile: true
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: '98'
  },
};
