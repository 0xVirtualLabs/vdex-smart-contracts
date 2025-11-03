// import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
// import VaultProxyModule from "./VaultProxy";

// const upgradeModule = buildModule("UpgradeVaultProxyToV2Module", (m) => {
//     const proxyAdminOwner = m.getAccount(0);

//     const { proxy, proxyAdmin } = m.useModule(VaultProxyModule);

//     const vaultV2 = m.contract("VaultV2", [], {
//         libraries: {
//             Crypto: m.library("Crypto")
//         }
//     });

//     m.call(proxyAdmin, "upgradeAndCall", [proxy, vaultV2, "0x"], {
//         from: proxyAdminOwner
//     });

//     return { proxyAdmin, proxy };

// });

// export default upgradeModule;