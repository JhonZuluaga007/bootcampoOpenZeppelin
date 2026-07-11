import { expect } from "chai";
import {
  deployAuroPegFixture,
  networkHelpers,
} from "./helpers/fixtures.js";

// Mock-backed suite for the informational XAU/USD price feed. This is the
// primary, always-run coverage for getGoldPriceUSD(); the optional
// test/AuroPeg.priceFeed.fork.test.ts additionally checks the real
// Chainlink Sepolia feed when SEPOLIA_RPC_URL is configured.
describe("AuroPeg XAU/USD price feed (mock)", function () {
  it("stores the configured price feed address", async function () {
    const { auroPeg, xauUsdPriceFeed } = await networkHelpers.loadFixture(
      deployAuroPegFixture,
    );

    expect(await auroPeg.xauUsdPriceFeed()).to.equal(
      await xauUsdPriceFeed.getAddress(),
    );
  });

  it("returns the feed's latest price and timestamp", async function () {
    const { auroPeg, xauUsdPriceFeed } = await networkHelpers.loadFixture(
      deployAuroPegFixture,
    );

    const [, expectedAnswer, , expectedUpdatedAt] =
      await xauUsdPriceFeed.latestRoundData();
    const [price, updatedAt] = await auroPeg.getGoldPriceUSD();

    expect(price).to.equal(expectedAnswer);
    expect(updatedAt).to.equal(expectedUpdatedAt);
  });

  it("reflects a price update on the next call", async function () {
    const { auroPeg, admin, xauUsdPriceFeed } = await networkHelpers.loadFixture(
      deployAuroPegFixture,
    );
    const newPrice = 2_650_00000000n; // arbitrary spot-price-shaped value

    await xauUsdPriceFeed.connect(admin).setReserve(newPrice);

    const [price] = await auroPeg.getGoldPriceUSD();
    expect(price).to.equal(newPrice);
  });

  it("is callable by anyone — no role required", async function () {
    const { auroPeg, other } = await networkHelpers.loadFixture(
      deployAuroPegFixture,
    );

    const [price] = await auroPeg.connect(other).getGoldPriceUSD();
    expect(price).to.not.equal(0n);
  });

  it("remains readable while the contract is paused", async function () {
    const { auroPeg, admin } = await networkHelpers.loadFixture(
      deployAuroPegFixture,
    );
    await auroPeg.connect(admin).pause();

    const [price] = await auroPeg.getGoldPriceUSD();
    expect(price).to.not.equal(0n);
  });

  it("is never consulted by the mint circuit breaker", async function () {
    const { auroPeg, admin, other, xauUsdPriceFeed } =
      await networkHelpers.loadFixture(deployAuroPegFixture);

    // Crash the price feed entirely — mint eligibility depends only on
    // goldReserveOracle, never on xauUsdPriceFeed.
    await xauUsdPriceFeed.connect(admin).setReserve(0n);

    await auroPeg.connect(admin).mint(other.address, 1n);
    expect(await auroPeg.balanceOf(other.address)).to.equal(1n);
  });
});
