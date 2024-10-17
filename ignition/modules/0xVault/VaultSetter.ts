import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import DexSupporterModule from "./DexSupporter";
import LpProviderModule from "./LpProvider";
import vaultProxyModule from "./Proxy";

/**
 * This is the second module that will be run, and it is also the only module exported from this file.
 * It creates a contract instance for the Vault contract using the proxy from the previous module.
 */
const VaultSetter = buildModule("VaultSetter", (m) => {
  // Get the proxy and proxy admin from the previous module.

  const proxyAdminOwner = m.getAccount(0);

  const { vault } = m.useModule(vaultProxyModule);
  const { lpProvider } = m.useModule(LpProviderModule);
  const { dexSupporter } = m.useModule(DexSupporterModule);

  m.call(vault, "setLpProvider", [lpProvider], {
    from: proxyAdminOwner,
  });

  m.call(vault, "setDexSupporter", [dexSupporter], {
    from: proxyAdminOwner,
  });

  m.call(
    vault,
    "setSupportedToken",
    ["0x0723dfdb59072ffde155da561312dbc0da8bd31b"],
    {
      from: proxyAdminOwner,
    }
  );
  m.call(lpProvider, "setWithdrawalDelayTime", [3600], {
    from: proxyAdminOwner,
  });
  m.call(
    lpProvider,
    "setOracle",
    ["0x30484f27c5191A34587007aD380049d54DbCfAE7"],
    {
      from: proxyAdminOwner,
    }
  );

  // Return the contract instance, along with the original proxy and proxyAdmin contracts
  // so that they can be used by other modules, or in tests and scripts.
  return { vault };
});

export default VaultSetter;
