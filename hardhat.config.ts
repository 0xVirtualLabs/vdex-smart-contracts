import type { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-ignition-viem";
import "hardhat-contract-sizer";
import { config as dotenvConfig } from "dotenv";
import { NetworkUserConfig } from "hardhat/types";
dotenvConfig();

const chainIds = {
  goerli: 5,
  hardhat: 31337,
  kovan: 42,
  mainnet: 1,
  rinkeby: 4,
  ropsten: 3,
  polygon: 137,
  bsctestnet: 97,
  bsc: 56,
  mumbai: 80001,
  sepolia: 11155111,
  bitlayertestnet: 200810,
  seidevnet: 713715,
};

// Ensure that we have all the environment variables we need.
const deployerPrivateKey: string | undefined = process.env.DEPLOYER_PRIVATE_KEY;
if (!deployerPrivateKey) {
  throw new Error("Please set your DEPLOYER_PRIVATE_KEY in a .env file");
}

const infuraApiKey: string | undefined = process.env.INFURA_API_KEY;
if (!infuraApiKey) {
  throw new Error("Please set your INFURA_API_KEY in a .env file");
}

function getChainConfig(network: keyof typeof chainIds): NetworkUserConfig {
  let url: string = "https://" + network + ".infura.io/v3/" + infuraApiKey;
  if (network === "polygon") {
    url = "https://polygon-rpc.com";
  }
  if (network === "bsctestnet") {
    url = "https://bsc-testnet-rpc.publicnode.com";
  }
  if (network === "bsc") {
    url = "https://bsc-dataseed.binance.org/";
  }
  if (network === "mumbai") {
    url = "https://rpc-mumbai.maticvigil.com/";
  }
  if (network === "sepolia") {
    url = "https://ethereum-sepolia-rpc.publicnode.com";
  }
  if (network === "bitlayertestnet") {
    url = "https://testnet-rpc.bitlayer.org";
  }
  if (network === "seidevnet") {
    url = "https://evm-rpc.arctic-1.seinetwork.io";
  }
  return {
    accounts: [`0x${deployerPrivateKey}`],
    chainId: chainIds[network],
    // gasPrice: 20000000000,
    url,
  };
}

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  gasReporter: {
    currency: "USD",
    enabled: process.env.REPORT_GAS ? true : false,
    excludeContracts: [],
    src: "./contracts",
  },
  networks: {
    // hardhat: {
    //   chainId: chainIds.hardhat,
    //   accounts: {
    //     accountsBalance: "1000000000000000000000000000000",
    //   },
    //   allowUnlimitedContractSize: true,
    // },
    goerli: getChainConfig("goerli"),
    kovan: getChainConfig("kovan"),
    rinkeby: getChainConfig("rinkeby"),
    ropsten: getChainConfig("ropsten"),
    polygon: getChainConfig("polygon"),
    bsctestnet: getChainConfig("bsctestnet"),
    bsc: getChainConfig("bsc"),
    mumbai: getChainConfig("mumbai"),
    sepolia: getChainConfig("sepolia"),
    bitlayertestnet: getChainConfig("bitlayertestnet"),
    seidevnet: getChainConfig("seidevnet"),
  },
  etherscan: {
    // Your API key for Etherscan
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./test",
  },
  solidity: {
    compilers: [
      {
        version: "0.8.24",
      },
      {
        version: "0.6.7",
        settings: {},
      },
    ],
  },

};

export default config;
