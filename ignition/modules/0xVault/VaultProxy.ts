import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ethers, upgrades } from "hardhat";

const VaultProxyModule = buildModule("VaultProxyModule", (m) => {
  const proxyAdminOwner = m.getAccount(0);

  // Deploy the Crypto library
  const crypto = m.library("Crypto");

  // Link the library and prepare the implementation factory
  const vaultContract = m.contract("Vault", [], {
    libraries: {
      "contracts/0xVault/libs/Crypto.sol:Crypto": crypto,
    },
  });


  const proxy = m.contract('TransparentUpgradeableProxy', [
    vaultContract, 
    proxyAdminOwner, 
    "0x"
  ]);
  const vaultProxy = m.contractAt('Vault', proxy, {id: 'VaultProxyInstance'});

  const proxyAdminAddress = m.readEventArgument(
    proxy,
    'AdminChanged',
    'newAdmin'
  );

  m.call(vaultProxy, 'initialize', [proxyAdminOwner, 3600, proxyAdminOwner, proxyAdminOwner], {
    from: proxyAdminOwner,
  });

  

  const proxyAdmin = m.contractAt('ProxyAdmin', proxyAdminAddress);

  return { vaultContract, proxy, proxyAdmin };
});

export default VaultProxyModule;
