# Sample Hardhat Project

This project demonstrates a basic Hardhat use case. It comes with a sample contract, a test for that contract, and a Hardhat Ignition module that deploys that contract.

Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat ignition deploy ./ignition/modules/Lock.ts
```

steps do deploy

1. run proxy.ts
   npx hardhat ignition deploy ./ignition/modules/0xVault/Proxy.ts --network bitlayertestnet
   need to remove the chain in ignition/deployments if it exists

   ProxyModule#Crypto - 0x9998ef650844BedA6a5e9911834d8c9a26eE6919
   ProxyModule#ProxyAdmin - 0xDcB9e1F191a80C69f2Eb8666C3b5a00e837dff6d
   ProxyModule#Vault - 0xd4cA51208FF8d33e9f118709B57780A50188292B
   ProxyModule#TransparentUpgradeableProxy - 0x48a05eF5Fa3B575316B6e7D82F1E80Dd063D6bdD
   VaultProxyModule#Vault - 0x48a05eF5Fa3B575316B6e7D82F1E80Dd063D6bdD // backend and frontend should use this one

   constructor(
   address \_vault,
   address \_supraVerifier,
   address \_supraStorageOracle, // pull oracle
   address \_lpProvider
   )

2. run lpprovider.ts
   npx hardhat ignition deploy ./ignition/modules/0xVault/LpProvider.ts --network bitlayertestnet

   ProxyModule#Crypto - 0x9998ef650844BedA6a5e9911834d8c9a26eE6919
   ProxyModule#ProxyAdmin - 0xDcB9e1F191a80C69f2Eb8666C3b5a00e837dff6d
   ProxyModule#Vault - 0xd4cA51208FF8d33e9f118709B57780A50188292B
   ProxyModule#TransparentUpgradeableProxy - 0x48a05eF5Fa3B575316B6e7D82F1E80Dd063D6bdD
   VaultProxyModule#Vault - 0x48a05eF5Fa3B575316B6e7D82F1E80Dd063D6bdD
   ProxyModule#LpProvider - 0xfDe6f3D20387Fb649F5242088d6e5C78F423C67d
   ProxyModule#TProxyForLPProvider - 0x44299F3cf37970D7C952C64961c4F407844C3B35
   LpProviderModule#LpProvider - 0x44299F3cf37970D7C952C64961c4F407844C3B35 // backend and frontend should use this one

3. run the dexsupporter.ts
   change the address parameters here before deploying
   const dexSupporter = m.contract(
   "DexSupporter",
   [
   "0x48a05eF5Fa3B575316B6e7D82F1E80Dd063D6bdD", // vault
   "0xaa2f56843cec7840f0c106f0202313d8d8cb13d6", // supraVerifier
   "0x30484f27c5191A34587007aD380049d54DbCfAE7", // supraStorageOracle is a pull oracle
   "0x44299F3cf37970D7C952C64961c4F407844C3B35", // lpProvider
   ],
   {
   libraries: {
   Dex: Dex,
   Crypto: Crypto,
   SupraOracleDecoder: SupraOracleDecoder,
   },
   }
   );

   npx hardhat ignition deploy ./ignition/modules/0xVault/DexSupporter.ts --network bitlayertestnet

4. pass the contract addresses of lp provider and dex supporter to vault contract
   the script is in VaultSetter.ts
   npx hardhat ignition deploy ./ignition/modules/0xVault/VaultSetter.ts --network bitlayertestnet

setDexSupporter and setLpProvider

5. to add new chains just add the chain info in hardhat.config.ts and ignition/chains , url , chainID and getter function

6. npx hardhat ignition verify chain-11155111

example to verify code on an explorer

//bitlayer contract addresses

ProxyModule#Crypto - 0x247a43e55884429c12782f49aFF889A17F873949
ProxyModule#ProxyAdmin - 0x1C7e7B742cA51E4E05783417c008ddeb196aDca6
ProxyModule#Vault - 0x5c92305Ea4d00E5E1C0a166f456dA92DfaF7646e
ProxyModule#TransparentUpgradeableProxy - 0xEBB37b957f97661949c308c80D4b4ed21C26Dd8c
VaultProxyModule#Vault - 0xEBB37b957f97661949c308c80D4b4ed21C26Dd8c // vault
ProxyModule#LpProvider - 0x79D8d8304C50Cf6a3aD240E2326642049a619B2c
ProxyModule#TProxyForLPProvider - 0xc12e4c2CA0e255C0266F6A1E2dDe19c4b82D9484
LpProviderModule#LpProvider - 0xc12e4c2CA0e255C0266F6A1E2dDe19c4b82D9484 // lpprovider
DexSupporterModule#Crypto - 0x3Ad017605600aA67257C047A7ef9D4C57Ce76E27
DexSupporterModule#Dex - 0x4F1F2aD00f0eab0B6B6E64e5A6Ee300921C1aA16
DexSupporterModule#SupraOracleDecoder - 0x966eA4b92815030dc59455366Ba075990D4E0D8a
DexSupporterModule#DexSupporter - 0x0aE3e3E0F3F865b83DF4A9e89F2e997aC0303A01 // dexsupporter

//sepolia
ProxyModule#Crypto - 0x0A115b086cF7Dd88E38996c846d555C2511b2BD1
ProxyModule#ProxyAdmin - 0x6a32dc12D3D0Cb0c24569401d72596146CB5edF8
ProxyModule#Vault - 0x16E398194B7A4485d1C590F96190715707E15399
ProxyModule#TransparentUpgradeableProxy - 0x5750E28E9BF2f07CDfC680c1F85029c74bFEeab5
VaultProxyModule#Vault - 0x5750E28E9BF2f07CDfC680c1F85029c74bFEeab5 // vault
ProxyModule#LpProvider - 0x115206a40753ED994e297c687800A48B90b66e1b
ProxyModule#TProxyForLPProvider - 0xA67cCF03Dc3d333d23320701066fE92b090B1D0d
LpProviderModule#LpProvider - 0xA67cCF03Dc3d333d23320701066fE92b090B1D0d // lpprovider
DexSupporterModule#Crypto - 0xa707e6769E575bd258F21F5722e0d719221e2895
DexSupporterModule#Dex - 0xfef2Cba98c485Cd621945A674941932D1020AE14
DexSupporterModule#SupraOracleDecoder - 0xB983Bcf53422452Ae8660643da9e3C3D2412182E
DexSupporterModule#DexSupporter - 0x6A128912f8935feBcbDB4deA69F0dE15a406A723 // dexsupporter

// note: add new tokens to vault as supported tokens
