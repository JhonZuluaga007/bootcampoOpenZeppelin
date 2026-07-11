import { expect } from "chai";
import { network } from "hardhat";

// Optional, not part of the default `npx hardhat test` run: only executes
// when SEPOLIA_RPC_URL is configured (see .env.example), since it forks
// live Sepolia state to query the real Chainlink XAU/USD feed. Run it
// explicitly with:
//   npx hardhat test test/AuroPeg.priceFeed.fork.test.ts
//
// IMPORTANT: reconfirm this address against
// https://docs.chain.link/data-feeds/price-feeds/addresses before relying
// on it for an actual deployment — testnet feed addresses can change.
const SEPOLIA_XAU_USD_FEED = "0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea";
const EXPECTED_DECIMALS = 8;

const describeIfForkable = process.env.SEPOLIA_RPC_URL ? describe : describe.skip;

describeIfForkable(
  "AuroPeg XAU/USD price feed (Sepolia fork, optional)",
  function () {
    this.timeout(60_000);

    it("reads a live decimals() and non-zero answer from the real Chainlink feed", async function () {
      const { ethers } = await network.create("sepoliaFork");

      // IGoldReserveOracle shares AggregatorV3Interface's exact ABI (see
      // contracts/interfaces/IGoldReserveOracle.sol), and unlike the
      // Chainlink package's own interface, it has a compiled artifact in
      // this project — so it doubles as the attach point here.
      const priceFeed = await ethers.getContractAt(
        "IGoldReserveOracle",
        SEPOLIA_XAU_USD_FEED,
      );

      const decimals = await priceFeed.decimals();
      const [, answer, , updatedAt] = await priceFeed.latestRoundData();

      expect(decimals).to.equal(EXPECTED_DECIMALS);
      expect(answer).to.be.greaterThan(0n);
      expect(updatedAt).to.be.greaterThan(0n);
    });
  },
);
