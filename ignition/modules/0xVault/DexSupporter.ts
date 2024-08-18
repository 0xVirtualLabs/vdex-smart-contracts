import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * This is the second module that will be run, and it is also the only module exported from this file.
 * It creates a contract instance for the Vault contract using the proxy from the previous module.
 */
const DexSupporterModule = buildModule("DexSupporterModule", (m) => {


  // Get the proxy and proxy admin from the previous module.

  const Dex = m.library("Dex");
  const Crypto = m.library("Crypto");
  const SupraOracleDecoder = m.library("SupraOracleDecoder");

  const dexSupporter = m.contract("DexSupporter", [
    "0x79acEc25Cc0Eb12912C0898f78bd4869C764E343",
    "0x5912A45b33aa67d2c3Bd3c93A133B727398b01Ec",
    "0x131918bC49Bb7de74aC7e19d61A01544242dAA80",
    "0x1d1ea686d3F7d2d8FEcA26a5Da4176084bC92Ac6",
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
