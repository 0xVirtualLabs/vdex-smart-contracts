const { ethers, upgrades } = require("hardhat");

async function main() {
  const proxyAddress = "0x5750E28E9BF2f07CDfC680c1F85029c74bFEeab5"; // Replace with your proxy address
  const cryptoLibraryAddress = "0x79D8d8304C50Cf6a3aD240E2326642049a619B2c"; // Replace with your deployed Crypto library address

  try {
    console.log("Deploying a new Vault implementation contract...");
    const Vault = await ethers.getContractFactory("Vault", {
      libraries: {
        Crypto: cryptoLibraryAddress,
      },
    });

    console.log("Upgrading the proxy to use the new implementation...");
    const upgraded = await upgrades.upgradeProxy(proxyAddress, Vault, {
      unsafeAllowLinkedLibraries: true,
    });

    console.log("Upgrade successful!");
    console.log(`Proxy Address: ${proxyAddress}`);
    console.log(`New Implementation Address: ${upgraded.address}`);
  } catch (error) {
    console.error("Error during the upgrade process:", error);
    process.exit(1);
  }
}

main();
