import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import LpProviderModule from "./LpProvider";
import DexSupporterModule from "./DexSupporter";

/**
 * This is the first module that will be run. It deploys the proxy and the
 * proxy admin, and returns them so that they can be used by other modules.
 */
const proxyModule = buildModule("ProxyModule", (m) => {
  // This address is the owner of the ProxyAdmin contract,
  // so it will be the only account that can upgrade the proxy when needed.

  const proxyAdminOwner = m.getAccount(0);
  console.log("🚀 ~ proxyModule ~ proxyAdminOwner:", proxyAdminOwner);

  const proxyAdmin = m.contractAt("ProxyAdmin", "0x9E8D86C82445061BFdFE956A9b928CA8501a1663");
  const dexSupporter = m.contractAt("DexSupporter", "0xB9A25d7Be55c96C4470e9236Fdb80e6d0b0F41ad");

  // The TransparentUpgradeableProxy contract creates the ProxyAdmin within its constructor.
  // To read more about how this proxy is implemented, you can view the source code and comments here:
  // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol
  const initializeData = m.encodeFunctionCall(
    dexSupporter,
    "initialize",
    [
      "0x03Fe256EdcDf7eC86d40DcB4582E0685b692271D",
      "0x7fFd4190F53C55FB7DfAbAab2F433F2a9975540c"
    ],
    {
      id: "TProxyForDexSupporter",
    }
  );

  const proxy = m.contract("TransparentUpgradeableProxy", [
    dexSupporter,
    proxyAdmin,
    initializeData,
  ]);

  // Return the proxy and proxy admin so that they can be used by other modules.
  return { proxyAdmin, proxy };
});

/**
 * This is the second module that will be run, and it is also the only module exported from this file.
 * It creates a contract instance for the Demo contract using the proxy from the previous module.
 */
const vaultProxyModule = buildModule("VaultProxyModule", (m) => {
  // Get the proxy and proxy admin from the previous module.
  const { proxy, proxyAdmin } = m.useModule(proxyModule);

  // Here we're using m.contractAt(...) a bit differently than we did above.
  // While we're still using it to create a contract instance, we're now telling Hardhat Ignition
  // to treat the contract at the proxy address as an instance of the Demo contract.
  // This allows us to interact with the underlying Demo contract via the proxy from within tests and scripts.
  const vault = m.contractAt("Vault", proxy);

  // Return the contract instance, along with the original proxy and proxyAdmin contracts
  // so that they can be used by other modules, or in tests and scripts.
  return { vault, proxy, proxyAdmin };
});

export default vaultProxyModule;
