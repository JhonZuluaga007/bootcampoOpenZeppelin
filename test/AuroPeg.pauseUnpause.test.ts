import { expect } from "chai";
import {
  deployAuroPegFixture,
  ethers,
  networkHelpers,
} from "./helpers/fixtures.js";

describe("AuroPeg pause / unpause", function () {
  describe("Access control", function () {
    it("allows an account with PAUSER_ROLE to pause", async function () {
      const { auroPeg, admin } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );

      await expect(auroPeg.connect(admin).pause())
        .to.emit(auroPeg, "Paused")
        .withArgs(admin.address);
      expect(await auroPeg.paused()).to.be.true;
    });

    it("allows an account with UNPAUSER_ROLE to unpause", async function () {
      const { auroPeg, admin } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );
      await auroPeg.connect(admin).pause();

      await expect(auroPeg.connect(admin).unpause())
        .to.emit(auroPeg, "Unpaused")
        .withArgs(admin.address);
      expect(await auroPeg.paused()).to.be.false;
    });

    it("reverts when a non-PAUSER account calls pause", async function () {
      const { auroPeg, other } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );

      await expect(
        auroPeg.connect(other).pause(),
      ).to.be.revertedWithCustomError(
        auroPeg,
        "AccessControlUnauthorizedAccount",
      );
    });

    it("reverts when a non-UNPAUSER account calls unpause", async function () {
      const { auroPeg, admin, other } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );
      await auroPeg.connect(admin).pause();

      await expect(
        auroPeg.connect(other).unpause(),
      ).to.be.revertedWithCustomError(
        auroPeg,
        "AccessControlUnauthorizedAccount",
      );
    });

    it("does not allow an account with only PAUSER_ROLE to unpause", async function () {
      const { auroPeg, admin, monitor } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );
      // Simulate granting the off-chain monitor keeper PAUSER_ROLE only —
      // exactly as scripts/grantRoles.ts will do in Phase 6 — and confirm
      // it can never be granted UNPAUSER_ROLE's privileges by proxy.
      await auroPeg
        .connect(admin)
        .grantRole(await auroPeg.PAUSER_ROLE(), monitor.address);
      await auroPeg.connect(monitor).pause();

      expect(
        await auroPeg.hasRole(await auroPeg.UNPAUSER_ROLE(), monitor.address),
      ).to.be.false;
      await expect(
        auroPeg.connect(monitor).unpause(),
      ).to.be.revertedWithCustomError(
        auroPeg,
        "AccessControlUnauthorizedAccount",
      );
    });
  });

  describe("Double pause/unpause protection", function () {
    it("reverts when pausing an already-paused contract", async function () {
      const { auroPeg, admin } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );
      await auroPeg.connect(admin).pause();

      await expect(
        auroPeg.connect(admin).pause(),
      ).to.be.revertedWithCustomError(auroPeg, "EnforcedPause");
    });

    it("reverts when unpausing a contract that isn't paused", async function () {
      const { auroPeg, admin } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );

      await expect(
        auroPeg.connect(admin).unpause(),
      ).to.be.revertedWithCustomError(auroPeg, "ExpectedPause");
    });
  });

  describe("Effect on mint, burn, and transfers", function () {
    it("blocks mint while paused", async function () {
      const { auroPeg, admin, other } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );
      await auroPeg.connect(admin).pause();

      await expect(
        auroPeg.connect(admin).mint(other.address, 1n),
      ).to.be.revertedWithCustomError(auroPeg, "EnforcedPause");
    });

    it("allows mint again once unpaused", async function () {
      const { auroPeg, admin, other } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );
      await auroPeg.connect(admin).pause();
      await auroPeg.connect(admin).unpause();

      await expect(
        auroPeg.connect(admin).mint(other.address, 1n),
      ).to.not.revert(ethers);
    });

    it("does not block burn while paused", async function () {
      const { auroPeg, admin, other } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );
      const amount = 100n * 10n ** 18n;
      await auroPeg.connect(admin).mint(other.address, amount);
      await auroPeg.connect(admin).pause();

      await expect(auroPeg.connect(other).burn(amount)).to.not.revert(
        ethers,
      );
    });

    it("does not block regular transfers while paused", async function () {
      const { auroPeg, admin, other, monitor } =
        await networkHelpers.loadFixture(deployAuroPegFixture);
      const amount = 100n * 10n ** 18n;
      await auroPeg.connect(admin).mint(other.address, amount);
      await auroPeg.connect(admin).pause();

      await expect(
        auroPeg.connect(other).transfer(monitor.address, amount),
      ).to.not.revert(ethers);
      expect(await auroPeg.balanceOf(monitor.address)).to.equal(amount);
    });
  });
});
