import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * This is the second module that will be run, and it is also the only module exported from this file.
 * It creates a contract instance for the Vault contract using the proxy from the previous module.
 */
const OnlyVaultModule = buildModule("OnlyVaultModule", (m) => {
  // Get the proxy and proxy admin from the previous module.

  // Here we're using m.contractAt(...) a bit differently than we did above.
  // While we're still using it to create a contract instance, we're now telling Hardhat Ignition
  // to treat the contract at the proxy address as an instance of the Vault contract.
  // This allows us to interact with the underlying Vault contract via the proxy from within tests and scripts.
  const vault = m.contract("Vault");

  // Return the contract instance, along with the original proxy and proxyAdmin contracts
  // so that they can be used by other modules, or in tests and scripts.
  return { vault };
});

export default OnlyVaultModule;
