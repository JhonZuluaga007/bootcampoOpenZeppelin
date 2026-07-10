import { expect } from "chai";
import {
  deployAuroPegFixture,
  ethers,
  networkHelpers,
} from "./helpers/fixtures.js";
import { INITIAL_RESERVE_GRAMS } from "./helpers/constants.js";

const RESERVE_IN_TOKEN_UNITS = INITIAL_RESERVE_GRAMS * 10n ** 10n;
const ONE_DAY_SECONDS = 24n * 60n * 60n;

describe("AuroPeg mint circuit breaker", function () {
  describe("Decimal conversion", function () {
    it("converts the oracle's 8-decimal reserve to 18-decimal token units", async function () {
      const { auroPeg } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );

      expect(await auroPeg.currentReserves()).to.equal(RESERVE_IN_TOKEN_UNITS);
    });

    it("reflects a reserve update from the oracle immediately", async function () {
      const { auroPeg, admin, goldReserveOracle } =
        await networkHelpers.loadFixture(deployAuroPegFixture);
      const newReserveGrams = 500_000n * 10n ** 8n;

      await goldReserveOracle.connect(admin).setReserve(newReserveGrams);

      expect(await auroPeg.currentReserves()).to.equal(
        newReserveGrams * 10n ** 10n,
      );
    });
  });

  describe("Reserve boundary", function () {
    it("reverts with InsufficientReserves for one unit over the reserve", async function () {
      const { auroPeg, admin, other } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );
      const amount = RESERVE_IN_TOKEN_UNITS + 1n;

      await expect(auroPeg.connect(admin).mint(other.address, amount))
        .to.be.revertedWithCustomError(auroPeg, "InsufficientReserves")
        .withArgs(amount, RESERVE_IN_TOKEN_UNITS);
    });

    it("reverts once outstanding supply plus the new mint would exceed the reserve", async function () {
      const { auroPeg, admin, other, monitor } =
        await networkHelpers.loadFixture(deployAuroPegFixture);

      await auroPeg.connect(admin).mint(other.address, RESERVE_IN_TOKEN_UNITS);

      await expect(
        auroPeg.connect(admin).mint(monitor.address, 1n),
      )
        .to.be.revertedWithCustomError(auroPeg, "InsufficientReserves")
        .withArgs(RESERVE_IN_TOKEN_UNITS + 1n, RESERVE_IN_TOKEN_UNITS);
    });
  });

  describe("Reserve drop", function () {
    it("blocks further minting once a reserve drop pushes supply above capacity", async function () {
      const { auroPeg, admin, other, goldReserveOracle } =
        await networkHelpers.loadFixture(deployAuroPegFixture);

      const seventyPercent = (RESERVE_IN_TOKEN_UNITS * 70n) / 100n;
      await auroPeg.connect(admin).mint(other.address, seventyPercent);

      // Drop the reserve by 50% (the mock's per-call cap) — outstanding
      // 70%-of-original supply now exceeds the new 50%-of-original reserve.
      await goldReserveOracle.connect(admin).simulateReserveDrop(5_000n);

      await expect(
        auroPeg.connect(admin).mint(other.address, 1n),
      ).to.be.revertedWithCustomError(auroPeg, "InsufficientReserves");
    });
  });

  describe("Stale or invalid reserve data", function () {
    it("reverts with StaleReserveData when the oracle reports a zero reserve", async function () {
      const { auroPeg, admin, other, goldReserveOracle } =
        await networkHelpers.loadFixture(deployAuroPegFixture);

      await goldReserveOracle.connect(admin).setReserve(0n);

      await expect(
        auroPeg.connect(admin).mint(other.address, 1n),
      ).to.be.revertedWithCustomError(auroPeg, "StaleReserveData");
    });

    it("reverts with StaleReserveData once the last update exceeds MAX_RESERVE_STALENESS", async function () {
      const { auroPeg, admin, other } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );

      await networkHelpers.time.increase(ONE_DAY_SECONDS + 1n);

      await expect(
        auroPeg.connect(admin).mint(other.address, 1n),
      ).to.be.revertedWithCustomError(auroPeg, "StaleReserveData");
    });

    it("does not revert for data updated just under the staleness threshold", async function () {
      const { auroPeg, admin, other } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );

      await networkHelpers.time.increase(ONE_DAY_SECONDS - 60n);

      await expect(
        auroPeg.connect(admin).mint(other.address, 1n),
      ).to.not.revert(ethers);
    });
  });
});
