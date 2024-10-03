import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import vaultProxyModule from "./Proxy";
import LpProviderModule from "./LpProvider";

/**
 * This is the second module that will be run, and it is also the only module exported from this file.
 * It creates a contract instance for the Vault contract using the proxy from the previous module.
 */
const DexSupporterModule = buildModule("DexSupporterModule", (m) => {


  // Get the proxy and proxy admin from the previous module.

  const Dex = m.library("Dex");
  const Crypto = m.library("Crypto");
  const SupraOracleDecoder = m.library("SupraOracleDecoder");

  const { vault } = m.useModule(vaultProxyModule);

  const { lpProvider } = m.useModule(LpProviderModule);

  const dexSupporter = m.contract("DexSupporter", [
    vault,
    "0x5912A45b33aa67d2c3Bd3c93A133B727398b01Ec", // supra verifier
    "0x131918bC49Bb7de74aC7e19d61A01544242dAA80", // supra pull oracle
    lpProvider,
  ], {
    libraries: {
      Dex: Dex,
      Crypto: Crypto,
      SupraOracleDecoder: SupraOracleDecoder,
    },
  });

  // Return the contract instance, along with the original proxy and proxyAdmin contracts
  // so that they can be used by other modules, or in tests and scripts.
  return { dexSupporter };
});

export default DexSupporterModule;
