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
   npx hardhat ignition deploy ./ignition/modules/0xVault/LPProvider.ts --network bitlayertestnet

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

5. // to add new chains just add the chain info in hardhat.config.ts and ignition/chains , url , chainID and getter function

ProxyModule#Crypto - 0x9998ef650844BedA6a5e9911834d8c9a26eE6919
ProxyModule#ProxyAdmin - 0xDcB9e1F191a80C69f2Eb8666C3b5a00e837dff6d
ProxyModule#Vault - 0xd4cA51208FF8d33e9f118709B57780A50188292B
ProxyModule#TransparentUpgradeableProxy - 0x48a05eF5Fa3B575316B6e7D82F1E80Dd063D6bdD
VaultProxyModule#Vault - 0x48a05eF5Fa3B575316B6e7D82F1E80Dd063D6bdD
ProxyModule#LpProvider - 0xfDe6f3D20387Fb649F5242088d6e5C78F423C67d
ProxyModule#TProxyForLPProvider - 0x44299F3cf37970D7C952C64961c4F407844C3B35
LpProviderModule#LpProvider - 0x44299F3cf37970D7C952C64961c4F407844C3B35
DexSupporterModule#Crypto - 0x9DfD264a30EC59Cc4A400B6d85226018728c385E
DexSupporterModule#Dex - 0xed1a6663fCd6447CEF8A2B9B49d549922619aE58
DexSupporterModule#SupraOracleDecoder - 0x245561425cfF971D27A80BF937969539109B24Cd
DexSupporterModule#DexSupporter - 0x64e7C8D6dC45ADAc952d1CDdf7B973A9e6FD07bb

6. npx hardhat ignition verify chain-11155111

example to verify code on an explorer
