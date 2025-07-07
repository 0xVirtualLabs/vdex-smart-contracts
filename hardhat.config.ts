import '@nomicfoundation/hardhat-ignition-viem';
import '@nomicfoundation/hardhat-toolbox-viem';
import { config as dotenvConfig } from 'dotenv';
import 'hardhat-contract-sizer';
import { NetworkUserConfig } from 'hardhat/types';
import 'solidity-docgen';
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
  },
  etherscan: {
    // Your API key for Etherscan
    apiKey: {
      nibirutestnet: 'nibirutestnet',
      nibirumainnet: 'nibirumainnet',
    },
    customChains: [
      {
        network: 'nibirutestnet',
        chainId: 6911,
        urls: {
          apiURL:
            'https://api.routescan.io/v2/network/testnet/evm/6911/etherscan',
          browserURL: 'https://testnet.nibiscan.io',
        },
      },
      {
        network: 'nibirumainnet',
        chainId: 6900,
        urls: {
          apiURL:
            'https://api.routescan.io/v2/network/mainnet/evm/6900/etherscan',
          browserURL: 'https://nibiscan.io',
        },
      },
    ],
  },
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
