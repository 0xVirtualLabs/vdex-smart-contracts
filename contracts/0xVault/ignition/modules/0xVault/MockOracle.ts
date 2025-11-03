import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * This is the second module that will be run, and it is also the only module exported from this file.
 * It creates a contract instance for the Vault contract using the proxy from the previous module.
 */
const MockOracleModule = buildModule("MockOracleModule", (m) => {
  // Get the proxy and proxy admin from the previous module.

  const oracle = m.contract("MockOracle", []);

  // Return the contract instance, along with the original proxy and proxyAdmin contracts
  // so that they can be used by other modules, or in tests and scripts.
  return { oracle };
});

export default MockOracleModule;
