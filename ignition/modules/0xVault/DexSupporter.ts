import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import vaultProxyModule from "./Proxy";
import LpProviderModule from "./LpProvider";

const proxyModule = buildModule("ProxyModule", (m) => {
  const { proxyAdmin, vault } = m.useModule(vaultProxyModule);
  // const proxyAdmin = m.contract("ProxyAdmin", []);

  // const proxyAdminOwner = m.getAccount(0);
  // console.log("🚀 ~ proxyModule ~ proxyAdminOwner:", proxyAdminOwner);
  // const { vault } = m.useModule(vaultProxyModule);
  const { lpProvider } = m.useModule(LpProviderModule);
  const crypto = m.library("Crypto");
  const dex = m.library("Dex");
  const dexSupporter = m.contract("DexSupporter", [], {
    libraries: { Crypto: crypto, Dex: dex },
  });


  const initializeData = m.encodeFunctionCall(dexSupporter, "initialize", [
    vault,
    "0xDd24F84d36BF92C65F92307595335bdFab5Bbd21",
    lpProvider,
  ]);

  const proxy = m.contract(
    "TransparentUpgradeableProxy",
    [dexSupporter, proxyAdmin, initializeData],
    {
      id: "TProxyForDexSupporter",
    }
  );

  // Return the proxy and proxy admin so that they can be used by other modules.
  return { proxyAdmin, proxy };
});

/**
 * This is the second module that will be run, and it is also the only module exported from this file.
 * It creates a contract instance for the Vault contract using the proxy from the previous module.
 */
const DexSupporterModule = buildModule("DexSupporterModule", (m) => {
  // Get the proxy and proxy admin from the previous module.

  const { proxy, proxyAdmin } = m.useModule(proxyModule);

  // Here we're using m.contractAt(...) a bit differently than we did above.
  // While we're still using it to create a contract instance, we're now telling Hardhat Ignition
  // to treat the contract at the proxy address as an instance of the Demo contract.
  // This allows us to interact with the underlying Demo contract via the proxy from within tests and scripts.
  const dexSupporter = m.contractAt("DexSupporter", proxy);

  // Return the contract instance, along with the original proxy and proxyAdmin contracts
  // so that they can be used by other modules, or in tests and scripts.
  return { dexSupporter, proxy, proxyAdmin };
});

export default DexSupporterModule;
