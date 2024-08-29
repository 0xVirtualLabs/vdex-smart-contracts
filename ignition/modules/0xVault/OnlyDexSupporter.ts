import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * This is the second module that will be run, and it is also the only module exported from this file.
 * It creates a contract instance for the Vault contract using the proxy from the previous module.
 */
const OnlyDexSupporterModule = buildModule("OnlyDexSupporterModule", (m) => {
  // Get the proxy and proxy admin from the previous module.

  // Here we're using m.contractAt(...) a bit differently than we did above.
  // While we're still using it to create a contract instance, we're now telling Hardhat Ignition
  // to treat the contract at the proxy address as an instance of the Vault contract.
  // This allows us to interact with the underlying Vault contract via the proxy from within tests and scripts.
  const crypto = m.contractAt("Crypto", "0x6e2c9d31CF22D1Bc030a3764cb96e81a3FcB7384");
  const dex = m.contractAt("Dex", "0x4D51F10C677f297e7484D64571F3dbC5Aa01618d");
  // const crypto = m.library("Crypto");

  const dexSupporter = m.contract("DexSupporter", [], {
    libraries: { Crypto: crypto, Dex: dex },
  });

  // Return the contract instance, along with the original proxy and proxyAdmin contracts
  // so that they can be used by other modules, or in tests and scripts.
  return { dexSupporter };
});

export default OnlyDexSupporterModule;
