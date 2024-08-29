#!/bin/bash

npx hardhat ignition deploy ignition/modules/0xVault/Proxy.ts --network sepolia
npx hardhat ignition deploy ignition/modules/0xVault/LPProvider.ts --network sepolia
npx hardhat ignition deploy ignition/modules/0xVault/DexSupporter.ts --network sepolia
npx hardhat ignition deploy ignition/modules/0xVault/VaultSetter.ts --network sepolia