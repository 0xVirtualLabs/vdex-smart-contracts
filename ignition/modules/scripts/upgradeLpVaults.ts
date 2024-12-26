const { ethers, upgrades } = require("hardhat");

async function main() {
  const proxyAddress = "0xe2634936d907ef9bf029d042e81d5cfb728a777a"; // Replace with your proxy address
  const LpProvider = await ethers.getContractFactory("LpProvider");

  console.log("Registering and upgrading the proxy...");

  // Force import the proxy
  await upgrades.forceImport(proxyAddress, LpProvider);

  // Upgrade the proxy to the new implementation
  const upgraded = await upgrades.upgradeProxy(proxyAddress, LpProvider);

  console.log("LpProvider upgraded at address:", upgraded.address);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
