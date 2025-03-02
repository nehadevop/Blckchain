// scripts/deploy.js
const { ethers } = require("hardhat");

async function main() {
  console.log("Deploying RWA Microloan Platform...");

  // Get contract factories
  const MicroloanPlatformFactory = await ethers.getContractFactory("MicroloanPlatformFactory");

  // Deploy factory
  console.log("Deploying MicroloanPlatformFactory...");
  const factory = await MicroloanPlatformFactory.deploy();
  await factory.deployTransaction.wait();
  console.log("MicroloanPlatformFactory deployed to:", factory.address);

  // Deploy platform through factory
  console.log("Deploying platform contracts through factory...");
  const deployPlatformTx = await factory.deployPlatform();
  await deployPlatformTx.wait();
  console.log("Platform deployment completed");

  // Get platform contracts
  const platformContracts = await factory.getPlatformContracts();
  console.log("RWA Tokenization deployed to:", platformContracts[0]);
  console.log("Loan Marketplace deployed to:", platformContracts[1]);
  console.log("Risk Assessment Oracle deployed to:", platformContracts[2]);

  // Verify contracts on Etherscan (if not on a local network)
  if (network.name !== "hardhat" && network.name !== "localhost") {
    console.log("Waiting for block confirmations...");
    // Wait for 5 more blocks to make sure Etherscan will be able to detect the contracts
    await deployPlatformTx.wait(5);

    console.log("Verifying contracts on Etherscan...");
    try {
      await hre.run("verify:verify", {
        address: factory.address,
        constructorArguments: [],
      });

      await hre.run("verify:verify", {
        address: platformContracts[0], // RWA Tokenization
        constructorArguments: [],
      });

      await hre.run("verify:verify", {
        address: platformContracts[1], // Loan Marketplace
        constructorArguments: [platformContracts[0]],
      });

      await hre.run("verify:verify", {
        address: platformContracts[2], // Risk Assessment Oracle
        constructorArguments: [],
      });
    } catch (error) {
      console.error("Error verifying contracts:", error.message);
    }
  }

  console.log("Deployment completed successfully!");
}

// Execute deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Deployment failed:", error);
    process.exit(1);
  });