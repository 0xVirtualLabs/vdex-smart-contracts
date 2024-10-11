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
   npx hardhat ignition deploy ./ignition/modules/0xVault/DexSupporter.ts --network bitlayertestnet
4. pass the contract addresses of lp provider and dex supporter to vault contract

setDexSupporter and setLpProvider

// to add new chains just add the chain info in hardhat.config.ts and ignition/chains
