import hre, { network } from "hardhat";
import { upgrades as upgradesFactory } from "@openzeppelin/hardhat-upgrades";

// Chainlink XAU/USD proxy feed on Sepolia. Purely informational — read only
// via AuroPeg.getGoldPriceUSD(), never consulted by the mint circuit
// breaker. Reconfirm against
// https://docs.chain.link/data-feeds/price-feeds/addresses before relying
// on it: testnet feed addresses can change without notice.
const SEPOLIA_XAU_USD_FEED = "0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea";

const DEFAULT_INITIAL_RESERVE_GRAMS = 1_000_000n * 10n ** 8n; // 1,000,000 g at 8 decimals
const DEFAULT_TOKEN_NAME = "AuroPeg";
const DEFAULT_TOKEN_SYMBOL = "AUP";

async function main() {
  const initialReserveGrams = process.env.INITIAL_RESERVE_GRAMS
    ? BigInt(process.env.INITIAL_RESERVE_GRAMS)
    : DEFAULT_INITIAL_RESERVE_GRAMS;
  const tokenName = process.env.TOKEN_NAME ?? DEFAULT_TOKEN_NAME;
  const tokenSymbol = process.env.TOKEN_SYMBOL ?? DEFAULT_TOKEN_SYMBOL;

  const connection = await network.create();
  const { ethers } = connection;
  const upgrades = await upgradesFactory(hre, connection);
  const [deployer] = await ethers.getSigners();
  const adminAddress = process.env.ADMIN_ADDRESS ?? deployer.address;

  console.log(`Network: ${connection.networkName}`);
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Default admin: ${adminAddress}`);

  // The gold reserve (Proof-of-Reserve) oracle is always the mock: no real
  // PoR testnet feed exists for a fictional gold-backed asset — see the
  // README's "Known Limitations" section.
  console.log("\nDeploying MockGoldReserveOracle (Proof-of-Reserve, mocked)...");
  const MockGoldReserveOracle = await ethers.getContractFactory("MockGoldReserveOracle");
  const goldReserveOracle = await MockGoldReserveOracle.deploy(initialReserveGrams, adminAddress);
  await goldReserveOracle.waitForDeployment();
  const goldReserveOracleAddress = await goldReserveOracle.getAddress();
  console.log(`  MockGoldReserveOracle: ${goldReserveOracleAddress}`);

  let priceFeedAddress = process.env.PRICE_FEED_ADDRESS;
  if (!priceFeedAddress && connection.networkName === "sepolia") {
    priceFeedAddress = SEPOLIA_XAU_USD_FEED;
    console.log(`\nUsing the real Chainlink XAU/USD feed on Sepolia: ${priceFeedAddress}`);
    console.log(
      "  Reconfirm this address against https://docs.chain.link/data-feeds/price-feeds/addresses before relying on it.",
    );
  }
  if (!priceFeedAddress) {
    console.log("\nDeploying a MockGoldReserveOracle stand-in for the XAU/USD price feed (no real feed on this network)...");
    const priceFeedStandIn = await MockGoldReserveOracle.deploy(initialReserveGrams, adminAddress);
    await priceFeedStandIn.waitForDeployment();
    priceFeedAddress = await priceFeedStandIn.getAddress();
    console.log(`  Price feed stand-in: ${priceFeedAddress}`);
  }

  console.log("\nDeploying AuroPeg (UUPS proxy)...");
  const AuroPeg = await ethers.getContractFactory("AuroPeg");
  const auroPeg = await upgrades.deployProxy(
    AuroPeg,
    [tokenName, tokenSymbol, adminAddress, goldReserveOracleAddress, priceFeedAddress],
    { kind: "uups" },
  );
  const auroPegAddress = await auroPeg.getAddress();
  const implementationAddress = await upgrades.erc1967.getImplementationAddress(auroPegAddress);

  console.log(`  AuroPeg proxy: ${auroPegAddress}`);
  console.log(`  AuroPeg implementation: ${implementationAddress}`);

  console.log("\nDeployment summary");
  console.log("===================");
  console.log(`AUROPEG_ADDRESS=${auroPegAddress}`);
  console.log(`AUROPEG_IMPLEMENTATION_ADDRESS=${implementationAddress}`);
  console.log(`GOLD_RESERVE_ORACLE_ADDRESS=${goldReserveOracleAddress}`);
  console.log(`PRICE_FEED_ADDRESS=${priceFeedAddress}`);

  console.log("\nNext steps:");
  console.log(`  1. Verify the implementation: npx hardhat verify --network sepolia ${implementationAddress}`);
  console.log(
    `  2. Delegate operational roles: MINTER_ADDRESS=... AUROPEG_ADDRESS=${auroPegAddress} npx hardhat run scripts/grantRoles.ts --network sepolia`,
  );
  console.log(
    `  3. Hand DEFAULT_ADMIN_ROLE to a timelock: AUROPEG_ADDRESS=${auroPegAddress} npx hardhat run scripts/deployTimelock.ts --network sepolia`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
