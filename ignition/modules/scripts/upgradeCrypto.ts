const { ethers, upgrades } = require("hardhat");

async function main() {
  const Crypto = await ethers.getContractFactory("Crypto");
  const crypto = await Crypto.deploy();
  console.log("Crypto deployed to:", crypto.address);
}
main();
