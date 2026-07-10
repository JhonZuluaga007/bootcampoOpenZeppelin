import { expect } from "chai";
import {
  deployAuroPegFixture,
  ethers,
  networkHelpers,
} from "./helpers/fixtures.js";
import { INITIAL_RESERVE_GRAMS } from "./helpers/constants.js";

const RESERVE_IN_TOKEN_UNITS = INITIAL_RESERVE_GRAMS * 10n ** 10n;

describe("AuroPeg reserve-drop scenario", function () {
  async function mintedNearCapacityFixture() {
    const fixture = await deployAuroPegFixture();
    const seventyPercent = (RESERVE_IN_TOKEN_UNITS * 70n) / 100n;
    await fixture.auroPeg
      .connect(fixture.admin)
      .mint(fixture.other.address, seventyPercent);
    return { ...fixture, mintedAmount: seventyPercent };
  }

  it("does not auto-pause the contract when the oracle reports a reserve drop", async function () {
    const { auroPeg, admin, goldReserveOracle } =
      await networkHelpers.loadFixture(mintedNearCapacityFixture);

    await goldReserveOracle.connect(admin).simulateReserveDrop(5_000n); // 50%

    expect(await auroPeg.paused()).to.be.false;
  });

  it("blocks further minting once outstanding supply exceeds the dropped reserve", async function () {
    const { auroPeg, admin, other, goldReserveOracle } =
      await networkHelpers.loadFixture(mintedNearCapacityFixture);

    await goldReserveOracle.connect(admin).simulateReserveDrop(5_000n); // 50%

    await expect(
      auroPeg.connect(admin).mint(other.address, 1n),
    ).to.be.revertedWithCustomError(auroPeg, "InsufficientReserves");
  });

  it("still allows holders to burn/redeem after an un-actioned reserve drop", async function () {
    const { auroPeg, other, admin, goldReserveOracle, mintedAmount } =
      await networkHelpers.loadFixture(mintedNearCapacityFixture);

    await goldReserveOracle.connect(admin).simulateReserveDrop(5_000n);

    await expect(auroPeg.connect(other).burn(mintedAmount)).to.not.revert(
      ethers,
    );
  });

  describe("Manual incident response", function () {
    it("lets PAUSER_ROLE pause minting after observing a drop, independent of the drop itself", async function () {
      const { auroPeg, admin, other, goldReserveOracle } =
        await networkHelpers.loadFixture(mintedNearCapacityFixture);

      await goldReserveOracle.connect(admin).simulateReserveDrop(5_000n);
      await auroPeg.connect(admin).pause();

      expect(await auroPeg.paused()).to.be.true;
      await expect(
        auroPeg.connect(admin).mint(other.address, 1n),
      ).to.be.revertedWithCustomError(auroPeg, "EnforcedPause");
    });

    it("resumes minting once reserves recover and an UNPAUSER_ROLE account unpauses", async function () {
      const { auroPeg, admin, other, goldReserveOracle } =
        await networkHelpers.loadFixture(mintedNearCapacityFixture);

      await goldReserveOracle.connect(admin).simulateReserveDrop(5_000n);
      await auroPeg.connect(admin).pause();

      // Reserves recover — restore to the original level.
      await goldReserveOracle.connect(admin).setReserve(INITIAL_RESERVE_GRAMS);
      await auroPeg.connect(admin).unpause();

      await expect(
        auroPeg.connect(admin).mint(other.address, 1n),
      ).to.not.revert(ethers);
    });

    it("does not resume minting from the reserve drop alone — unpause must be a separate manual step", async function () {
      const { auroPeg, admin, other, goldReserveOracle } =
        await networkHelpers.loadFixture(mintedNearCapacityFixture);

      await goldReserveOracle.connect(admin).simulateReserveDrop(5_000n);
      await auroPeg.connect(admin).pause();

      // Reserves recover, but nobody has unpaused yet.
      await goldReserveOracle.connect(admin).setReserve(INITIAL_RESERVE_GRAMS);

      await expect(
        auroPeg.connect(admin).mint(other.address, 1n),
      ).to.be.revertedWithCustomError(auroPeg, "EnforcedPause");
    });
  });
});
