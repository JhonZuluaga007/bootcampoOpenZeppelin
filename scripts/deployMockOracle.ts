import { network } from "hardhat";

// Standalone deploy of a single MockGoldReserveOracle instance — useful to
// grab a fresh demo oracle address (e.g. for auropeg-monitor or auropeg-ui
// local development) without redeploying the whole AuroPeg stack. The full
// stack deploy (scripts/deploy.ts) deploys its own reserve oracle inline
// and does not depend on this script.
const DEFAULT_INITIAL_RESERVE_GRAMS = 1_000_000n * 10n ** 8n; // 1,000,000 g at 8 decimals

async function main() {
  const initialReserveGrams = process.env.INITIAL_RESERVE_GRAMS
    ? BigInt(process.env.INITIAL_RESERVE_GRAMS)
    : DEFAULT_INITIAL_RESERVE_GRAMS;

  const { ethers } = await network.create();
  const [deployer] = await ethers.getSigners();
  const ownerAddress = process.env.ORACLE_OWNER_ADDRESS ?? deployer.address;

  console.log(`Deployer: ${deployer.address}`);
  console.log(`Initial reserve: ${initialReserveGrams} (grams, 8 decimals)`);
  console.log(`Owner: ${ownerAddress}`);

  const MockGoldReserveOracle = await ethers.getContractFactory("MockGoldReserveOracle");
  const oracle = await MockGoldReserveOracle.deploy(initialReserveGrams, ownerAddress);
  await oracle.waitForDeployment();

  console.log(`\nMockGoldReserveOracle deployed to: ${await oracle.getAddress()}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
