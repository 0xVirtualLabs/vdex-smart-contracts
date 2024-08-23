import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import vaultProxyModule from "./Proxy";
import LpProviderModule from "./LpProvider";

/**
 * This is the second module that will be run, and it is also the only module exported from this file.
 * It creates a contract instance for the Vault contract using the proxy from the previous module.
 */
const DexSupporterModule = buildModule("DexSupporterModule", (m) => {
  // Get the proxy and proxy admin from the previous module.

  const { vault } = m.useModule(vaultProxyModule);

  const { lpProvider } = m.useModule(LpProviderModule);

  const Dex = m.library("Dex");
  const Crypto = m.library("Crypto");
  const SupraOracleDecoder = m.library("SupraOracleDecoder");
  const supraStorge = process.env.SUPRA_STORAGE_ADDRESS;
  if (!supraStorge) {
    throw new Error("Please set your SUPRA_STORAGE_ADDRESS in a .env file");
  }
  const supraVerifier = process.env.SUPRA_VERITIFER_ADDRESS;
  if (!supraVerifier) {
    throw new Error("Please set your SUPRA_VERITIFER_ADDRESS in a .env file");
  }

  const dexSupporter = m.contract(
    "DexSupporter",
    [
      vault,
      supraVerifier, // TODO: supra verifier address - change it when deploy
      supraStorge, // TODO: supra storage address - change it when deploy 
      lpProvider,
    ],
    {
      libraries: {
        Dex: Dex,
        Crypto: Crypto,
        SupraOracleDecoder: SupraOracleDecoder,
      },
    }
  );

  // Return the contract instance, along with the original proxy and proxyAdmin contracts
  // so that they can be used by other modules, or in tests and scripts.
  return { dexSupporter };
});

export default DexSupporterModule;
