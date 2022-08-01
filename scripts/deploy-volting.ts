import { ethers } from "hardhat";

async function main() {
  const Voting = await ethers.getContractFactory("Voting");
  const voting = await Voting.deploy();

  await voting.deployed();

  console.log("Voting deployed to:", voting.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
