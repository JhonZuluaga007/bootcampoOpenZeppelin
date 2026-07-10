import { expect } from "chai";
import { ZeroAddress } from "ethers";
import {
  deployAuroPegFixture,
  ethers,
  networkHelpers,
} from "./helpers/fixtures.js";
import { INITIAL_RESERVE_GRAMS } from "./helpers/constants.js";

// 1,000,000 grams at 8-decimal oracle precision → 1,000,000e18 in
// 18-decimal token units.
const RESERVE_IN_TOKEN_UNITS = INITIAL_RESERVE_GRAMS * 10n ** 10n;

describe("AuroPeg minting", function () {
  describe("Happy path", function () {
    it("mints to the recipient and increases totalSupply", async function () {
      const { auroPeg, admin, other } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );
      const amount = 100n * 10n ** 18n;

      await expect(auroPeg.connect(admin).mint(other.address, amount))
        .to.emit(auroPeg, "Transfer")
        .withArgs(ZeroAddress, other.address, amount);

      expect(await auroPeg.balanceOf(other.address)).to.equal(amount);
      expect(await auroPeg.totalSupply()).to.equal(amount);
    });

    it("allows minting exactly up to the available reserve", async function () {
      const { auroPeg, admin, other } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );

      await auroPeg.connect(admin).mint(other.address, RESERVE_IN_TOKEN_UNITS);

      expect(await auroPeg.totalSupply()).to.equal(RESERVE_IN_TOKEN_UNITS);
    });

    it("accumulates totalSupply across multiple mints", async function () {
      const { auroPeg, admin, other, monitor } =
        await networkHelpers.loadFixture(deployAuroPegFixture);
      const amount = 100n * 10n ** 18n;

      await auroPeg.connect(admin).mint(other.address, amount);
      await auroPeg.connect(admin).mint(monitor.address, amount);

      expect(await auroPeg.totalSupply()).to.equal(amount * 2n);
    });
  });

  describe("Access control", function () {
    it("reverts when called by an account without MINTER_ROLE", async function () {
      const { auroPeg, other } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );

      await expect(
        auroPeg.connect(other).mint(other.address, 1n),
      ).to.be.revertedWithCustomError(
        auroPeg,
        "AccessControlUnauthorizedAccount",
      );
    });
  });

  describe("Input validation", function () {
    it("reverts when minting to the zero address", async function () {
      const { auroPeg, admin } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );

      await expect(
        auroPeg.connect(admin).mint(ZeroAddress, 1n),
      ).to.be.revertedWithCustomError(auroPeg, "ZeroAddress");
    });

    it("reverts when minting a zero amount", async function () {
      const { auroPeg, admin, other } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );

      await expect(
        auroPeg.connect(admin).mint(other.address, 0n),
      ).to.be.revertedWithCustomError(auroPeg, "ZeroAmount");
    });
  });

  describe("getGoldPriceUSD (informational)", function () {
    it("passes through the configured price feed's latest round", async function () {
      const { auroPeg, xauUsdPriceFeed } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );

      const [, expectedAnswer, , expectedUpdatedAt] =
        await xauUsdPriceFeed.latestRoundData();
      const [price, updatedAt] = await auroPeg.getGoldPriceUSD();

      expect(price).to.equal(expectedAnswer);
      expect(updatedAt).to.equal(expectedUpdatedAt);
    });

    it("does not affect mint eligibility", async function () {
      const { auroPeg, admin, other, xauUsdPriceFeed } =
        await networkHelpers.loadFixture(deployAuroPegFixture);

      // Crash the informational price feed's reserve-shaped reading; mint
      // must remain unaffected since it never reads xauUsdPriceFeed.
      await xauUsdPriceFeed.connect(admin).setReserve(0n);

      const amount = 100n * 10n ** 18n;
      await expect(
        auroPeg.connect(admin).mint(other.address, amount),
      ).to.not.revert(ethers);
    });
  });
});
