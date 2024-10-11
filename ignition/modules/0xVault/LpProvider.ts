import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import vaultProxyModule from "./Proxy";

/**
 * This is the first module that will be run. It deploys the proxy and the
 * proxy admin, and returns them so that they can be used by other modules.
 */
const proxyModule = buildModule("ProxyModule", (m) => {
  const { proxyAdmin } = m.useModule(vaultProxyModule);

  const proxyAdminOwner = m.getAccount(0);
  console.log("🚀 ~ proxyModule ~ proxyAdminOwner:", proxyAdminOwner);
  const { vault } = m.useModule(vaultProxyModule);
  const lpProvider = m.contract("LpProvider", []);

  const initializeData = m.encodeFunctionCall(lpProvider, "initialize", [
    proxyAdminOwner,
    vault,
    "0x131918bC49Bb7de74aC7e19d61A01544242dAA80",
    0,
    0,
    345600, // 6th one in the array is the withdrawal delay time
    proxyAdminOwner,
  ]);

  const proxy = m.contract(
    "TransparentUpgradeableProxy",
    [lpProvider, proxyAdmin, initializeData],
    {
      id: "TProxyForLPProvider",
    }
  );

  // Return the proxy and proxy admin so that they can be used by other modules.
  return { proxyAdmin, proxy };
});

/**
 * This is the second module that will be run, and it is also the only module exported from this file.
 * It creates a contract instance for the Demo contract using the proxy from the previous module.
 */
const LpProviderModule = buildModule("LpProviderModule", (m) => {
  // Get the proxy and proxy admin from the previous module.
  const { proxy, proxyAdmin } = m.useModule(proxyModule);

  // Here we're using m.contractAt(...) a bit differently than we did above.
  // While we're still using it to create a contract instance, we're now telling Hardhat Ignition
  // to treat the contract at the proxy address as an instance of the Demo contract.
  // This allows us to interact with the underlying Demo contract via the proxy from within tests and scripts.
  const lpProvider = m.contractAt("LpProvider", proxy);

  // Return the contract instance, along with the original proxy and proxyAdmin contracts
  // so that they can be used by other modules, or in tests and scripts.
  return { lpProvider, proxy, proxyAdmin };
});

export default LpProviderModule;
