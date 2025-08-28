import '@nomicfoundation/hardhat-ignition-viem';
import '@nomicfoundation/hardhat-toolbox-viem';
import { config as dotenvConfig } from 'dotenv';
import 'hardhat-contract-sizer';
import { NetworkUserConfig } from 'hardhat/types';
import 'solidity-docgen';
import '@nomiclabs/hardhat-ethers';
import '@openzeppelin/hardhat-upgrades';
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
  nibirutestnet: 6911,
  nibirumainnet: 6900,
  arbitrumtestnet: 421614,
  arbitrummainnet: 42161,
};

// Ensure that we have all the environment variables we need.
const deployerPrivateKey: string | undefined = process.env.DEPLOYER_PRIVATE_KEY;
if (!deployerPrivateKey) {
  throw new Error('Please set your DEPLOYER_PRIVATE_KEY in a .env file');
}

const infuraApiKey: string | undefined = process.env.INFURA_API_KEY;
if (!infuraApiKey) {
  throw new Error('Please set your INFURA_API_KEY in a .env file');
}

function getChainConfig(network: keyof typeof chainIds): NetworkUserConfig {
  let url: string = 'https://' + network + '.infura.io/v3/' + infuraApiKey;
  if (network === 'polygon') {
    url = 'https://polygon-rpc.com';
  }
  if (network === 'bsctestnet') {
    url = 'https://bsc-testnet-rpc.publicnode.com';
  }
  if (network === 'bsc') {
    url = 'https://bsc-dataseed.binance.org/';
  }
  if (network === 'mumbai') {
    url = 'https://rpc-mumbai.maticvigil.com/';
  }
  if (network === 'sepolia') {
    url = 'https://ethereum-sepolia-rpc.publicnode.com';
  }
  if (network === 'bitlayertestnet') {
    url = 'https://testnet-rpc.bitlayer.org';
  }
  if (network === 'nibirutestnet') {
    url = 'https://evm-rpc.testnet-2.nibiru.fi';
  }
  if (network === 'nibirumainnet') {
    url = 'https://evm-rpc.nibiru.fi';
  }
  if (network === 'seidevnet') {
    url = 'https://evm-rpc.arctic-1.seinetwork.io';
  }
  if (network === 'arbitrumtestnet') {
    url = 'https://sepolia-rollup.arbitrum.io/rpc';
  }
  if (network === 'arbitrummainnet') {
    url = 'https://arb1.arbitrum.io/rpc';
  }
  return {
    accounts: [`0x${deployerPrivateKey}`],
    chainId: chainIds[network],
    // gasPrice: 20000000000,
    url,
  };
}

const config: any = {
  defaultNetwork: 'hardhat',
  gasReporter: {
    currency: 'USD',
    enabled: process.env.REPORT_GAS ? true : false,
    excludeContracts: [],
    src: './contracts',
  },
  docgen: {
    output: 'docs',
    pages: () => 'api.md',
  },
  networks: {
    // hardhat: {
    //   chainId: chainIds.hardhat,
    //   accounts: {
    //     accountsBalance: "1000000000000000000000000000000",
    //   },
    //   allowUnlimitedContractSize: true,
    // },
    goerli: getChainConfig('goerli'),
    kovan: getChainConfig('kovan'),
    rinkeby: getChainConfig('rinkeby'),
    ropsten: getChainConfig('ropsten'),
    polygon: getChainConfig('polygon'),
    bsctestnet: getChainConfig('bsctestnet'),
    bsc: getChainConfig('bsc'),
    mumbai: getChainConfig('mumbai'),
    sepolia: getChainConfig('sepolia'),
    bitlayertestnet: getChainConfig('bitlayertestnet'),
    seidevnet: getChainConfig('seidevnet'),
    nibirutestnet: getChainConfig('nibirutestnet'),
    nibirumainnet: getChainConfig('nibirumainnet'),
    arbitrumSepolia: getChainConfig('arbitrumtestnet'),
    arbitrummainnet: getChainConfig('arbitrummainnet'),
  },
  etherscan: {
    // Your API key for Etherscan
    apiKey: "SKWZBKQSXE4856HD8AY99542WBNG32H1VE",
    customChains: [
      {
        network: "arbitrumSepolia",
        chainId: 421614,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=421614",
          browserURL: "https://sepolia.arbiscan.io"
        }
      },
      {
        network: "bscTestnet",
        chainId: 97,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=97",
          browserURL: "https://testnet.bscscan.com"
        }
      },
      {
        network: "bsc",
        chainId: 56,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=56",
          browserURL: "https://bscscan.com"
        }
      },
      {
        network: "arbitrummainnet",
        chainId: 42161,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=42161",
          browserURL: "https://arbiscan.io"
        }
      }
    ],
  },
  // sourcify: {
  //   enabled: true
  // },
  paths: {
    artifacts: './artifacts',
    cache: './cache',
    sources: './contracts',
    tests: './test',
  },
  solidity: {
    compilers: [
      {
        version: '0.8.27',
        settings: {
          optimizer: {
            enabled: true,
            runs: 0,
          },
        },
      },
      {
        version: '0.6.7',
        settings: {
          optimizer: {
            enabled: true,
            runs: 0,
          },
        },
      },
    ],
  },
};

export default config;
