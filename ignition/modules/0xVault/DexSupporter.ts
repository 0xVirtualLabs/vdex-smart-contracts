import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import LpProviderModule from "./LpProvider";
import vaultProxyModule from "./Proxy";

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

  const dexSupporter = m.contract(
    "DexSupporter",
    [
      vault,
      "0xaa2f56843cec7840f0c106f0202313d8d8cb13d6", // supra verifier
      "0x30484f27c5191A34587007aD380049d54DbCfAE7", // supra pull oracle
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
