import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import vaultProxyModule from "./Proxy";
import LpProviderModule from "./LpProvider";
import DexSupporterModule from "./DexSupporter";

/**
 * This is the second module that will be run, and it is also the only module exported from this file.
 * It creates a contract instance for the Vault contract using the proxy from the previous module.
 */
const VaultSetter = buildModule("VaultSetter", (m) => {
  // Get the proxy and proxy admin from the previous module.

  const proxyAdminOwner = m.getAccount(0);

  // const { vault } = m.useModule(vaultProxyModule);
  // const { lpProvider } = m.useModule(LpProviderModule);
  // const { dexSupporter } = m.useModule(DexSupporterModule);

  const vault = m.contractAt("Vault", "0x03Fe256EdcDf7eC86d40DcB4582E0685b692271D");
m.call(vault, "setVaultParameters", [3600, "0x34f1a0d52C5294a699cf383CA4da0Cf8C9e96248", "0x7fFd4190F53C55FB7DfAbAab2F433F2a9975540c"], {
    from: proxyAdminOwner,
  });

  // Return the contract instance, along with the original proxy and proxyAdmin contracts
  // so that they can be used by other modules, or in tests and scripts.
  return { vault };
});

export default VaultSetter;
