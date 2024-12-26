const { ethers } = require("hardhat");

async function main() {
  const cryptoLibraryAddress = "0x79D8d8304C50Cf6a3aD240E2326642049a619B2c"; // Replace with deployed Crypto library address

  const LpProvider = await ethers.getContractFactory("Vault", {
    libraries: {
      Crypto: cryptoLibraryAddress,
    },
  });

  const vault = await LpProvider.deploy();
  await vault.deployed();
  console.log("New Vault implementation deployed at:", vault.address);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
