import { expect } from "chai";
import { ZeroAddress, ZeroHash } from "ethers";
import {
  deployAuroPegFixture,
  ethers,
  networkHelpers,
} from "./helpers/fixtures.js";

const MIN_DELAY = 2 * 24 * 60 * 60; // 2 days

async function deployTimelockFixture() {
  const fixture = await deployAuroPegFixture();
  const { auroPeg, admin } = fixture;

  const AuroPegTimelock = await ethers.getContractFactory("AuroPegTimelock");
  const timelock = await AuroPegTimelock.deploy(
    MIN_DELAY,
    [admin.address], // proposer + canceller
    [admin.address], // executor
    ZeroAddress, // no separate optional admin — the timelock self-administers
  );
  const timelockAddress = await timelock.getAddress();

  const defaultAdminRole = await auroPeg.DEFAULT_ADMIN_ROLE();
  await auroPeg.connect(admin).grantRole(defaultAdminRole, timelockAddress);
  await auroPeg.connect(admin).revokeRole(defaultAdminRole, admin.address);

  return { ...fixture, timelock, timelockAddress, defaultAdminRole };
}

describe("AuroPeg DEFAULT_ADMIN_ROLE timelock handover", function () {
  describe("Handover", function () {
    it("revokes the deployer's direct admin access", async function () {
      const { auroPeg, admin, defaultAdminRole } = await networkHelpers.loadFixture(
        deployTimelockFixture,
      );

      expect(await auroPeg.hasRole(defaultAdminRole, admin.address)).to.be.false;
    });

    it("grants DEFAULT_ADMIN_ROLE to the timelock", async function () {
      const { auroPeg, timelockAddress, defaultAdminRole } =
        await networkHelpers.loadFixture(deployTimelockFixture);

      expect(await auroPeg.hasRole(defaultAdminRole, timelockAddress)).to.be.true;
    });

    it("no longer lets the deployer call admin-gated functions directly", async function () {
      const { auroPeg, admin, other } = await networkHelpers.loadFixture(
        deployTimelockFixture,
      );
      const minterRole = await auroPeg.MINTER_ROLE();

      await expect(
        auroPeg.connect(admin).grantRole(minterRole, other.address),
      ).to.be.revertedWithCustomError(auroPeg, "AccessControlUnauthorizedAccount");
    });

    it("leaves MINTER_ROLE/PAUSER_ROLE/UNPAUSER_ROLE untouched, so day-to-day operation stays instant", async function () {
      const { auroPeg, admin, other } = await networkHelpers.loadFixture(
        deployTimelockFixture,
      );

      // admin still holds MINTER_ROLE — only DEFAULT_ADMIN_ROLE moved to the timelock.
      await expect(
        auroPeg.connect(admin).mint(other.address, 10n ** 18n),
      ).to.not.revert(ethers);
    });
  });

  describe("Timelocked administration", function () {
    it("lets the timelock grant a role after the delay elapses, via schedule + execute", async function () {
      const { auroPeg, admin, other, timelock, timelockAddress } =
        await networkHelpers.loadFixture(deployTimelockFixture);
      const minterRole = await auroPeg.MINTER_ROLE();
      const auroPegAddress = await auroPeg.getAddress();
      const data = auroPeg.interface.encodeFunctionData("grantRole", [
        minterRole,
        other.address,
      ]);

      await timelock
        .connect(admin)
        .schedule(auroPegAddress, 0n, data, ZeroHash, ZeroHash, MIN_DELAY);
      await networkHelpers.time.increase(MIN_DELAY + 1);
      await timelock.connect(admin).execute(auroPegAddress, 0n, data, ZeroHash, ZeroHash);

      expect(await auroPeg.hasRole(minterRole, other.address)).to.be.true;
      expect(timelockAddress).to.equal(await timelock.getAddress());
    });

    it("reverts execute if attempted before the delay elapses", async function () {
      const { auroPeg, admin, other, timelock } = await networkHelpers.loadFixture(
        deployTimelockFixture,
      );
      const minterRole = await auroPeg.MINTER_ROLE();
      const auroPegAddress = await auroPeg.getAddress();
      const data = auroPeg.interface.encodeFunctionData("grantRole", [
        minterRole,
        other.address,
      ]);

      await timelock
        .connect(admin)
        .schedule(auroPegAddress, 0n, data, ZeroHash, ZeroHash, MIN_DELAY);

      await expect(
        timelock.connect(admin).execute(auroPegAddress, 0n, data, ZeroHash, ZeroHash),
      ).to.be.revertedWithCustomError(timelock, "TimelockUnexpectedOperationState");
    });

    it("reverts scheduling below the configured minimum delay", async function () {
      const { auroPeg, admin, other, timelock } = await networkHelpers.loadFixture(
        deployTimelockFixture,
      );
      const minterRole = await auroPeg.MINTER_ROLE();
      const auroPegAddress = await auroPeg.getAddress();
      const data = auroPeg.interface.encodeFunctionData("grantRole", [
        minterRole,
        other.address,
      ]);

      await expect(
        timelock
          .connect(admin)
          .schedule(auroPegAddress, 0n, data, ZeroHash, ZeroHash, MIN_DELAY - 1),
      ).to.be.revertedWithCustomError(timelock, "TimelockInsufficientDelay");
    });

    it("reverts when a non-proposer attempts to schedule", async function () {
      const { auroPeg, other, timelock } = await networkHelpers.loadFixture(
        deployTimelockFixture,
      );
      const minterRole = await auroPeg.MINTER_ROLE();
      const auroPegAddress = await auroPeg.getAddress();
      const data = auroPeg.interface.encodeFunctionData("grantRole", [
        minterRole,
        other.address,
      ]);

      await expect(
        timelock
          .connect(other)
          .schedule(auroPegAddress, 0n, data, ZeroHash, ZeroHash, MIN_DELAY),
      ).to.be.revertedWithCustomError(timelock, "AccessControlUnauthorizedAccount");
    });

    it("reverts when a non-executor attempts to execute a ready operation", async function () {
      const { auroPeg, admin, other, timelock } = await networkHelpers.loadFixture(
        deployTimelockFixture,
      );
      const minterRole = await auroPeg.MINTER_ROLE();
      const auroPegAddress = await auroPeg.getAddress();
      const data = auroPeg.interface.encodeFunctionData("grantRole", [
        minterRole,
        other.address,
      ]);

      await timelock
        .connect(admin)
        .schedule(auroPegAddress, 0n, data, ZeroHash, ZeroHash, MIN_DELAY);
      await networkHelpers.time.increase(MIN_DELAY + 1);

      await expect(
        timelock.connect(other).execute(auroPegAddress, 0n, data, ZeroHash, ZeroHash),
      ).to.be.revertedWithCustomError(timelock, "AccessControlUnauthorizedAccount");
    });
  });
});
