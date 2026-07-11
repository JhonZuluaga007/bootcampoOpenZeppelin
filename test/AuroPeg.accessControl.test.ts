import { expect } from "chai";
import {
  deployAuroPegFixture,
  ethers,
  networkHelpers,
} from "./helpers/fixtures.js";

describe("AuroPeg access control sweep", function () {
  describe("Role admin configuration", function () {
    it("uses DEFAULT_ADMIN_ROLE as the admin for every custom role", async function () {
      const { auroPeg } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );
      const defaultAdminRole = await auroPeg.DEFAULT_ADMIN_ROLE();

      expect(await auroPeg.getRoleAdmin(await auroPeg.MINTER_ROLE())).to.equal(
        defaultAdminRole,
      );
      expect(await auroPeg.getRoleAdmin(await auroPeg.PAUSER_ROLE())).to.equal(
        defaultAdminRole,
      );
      expect(
        await auroPeg.getRoleAdmin(await auroPeg.UNPAUSER_ROLE()),
      ).to.equal(defaultAdminRole);
    });
  });

  describe("Restricted functions revert for unauthorized callers", function () {
    it("mint reverts without MINTER_ROLE", async function () {
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

    it("pause reverts without PAUSER_ROLE", async function () {
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

    it("unpause reverts without UNPAUSER_ROLE", async function () {
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

    it("upgradeToAndCall reverts without DEFAULT_ADMIN_ROLE", async function () {
      const { auroPeg, other } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );
      const AuroPeg = await ethers.getContractFactory("AuroPeg");
      const newImplementation = await AuroPeg.deploy();
      await newImplementation.waitForDeployment();

      await expect(
        auroPeg
          .connect(other)
          .upgradeToAndCall(await newImplementation.getAddress(), "0x"),
      ).to.be.revertedWithCustomError(
        auroPeg,
        "AccessControlUnauthorizedAccount",
      );
    });

    it("grantRole reverts without DEFAULT_ADMIN_ROLE", async function () {
      const { auroPeg, other, monitor } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );

      await expect(
        auroPeg
          .connect(other)
          .grantRole(await auroPeg.MINTER_ROLE(), monitor.address),
      ).to.be.revertedWithCustomError(
        auroPeg,
        "AccessControlUnauthorizedAccount",
      );
    });

    it("revokeRole reverts without DEFAULT_ADMIN_ROLE", async function () {
      const { auroPeg, admin, other } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );

      await expect(
        auroPeg
          .connect(other)
          .revokeRole(await auroPeg.MINTER_ROLE(), admin.address),
      ).to.be.revertedWithCustomError(
        auroPeg,
        "AccessControlUnauthorizedAccount",
      );
    });
  });

  describe("Authorized callers succeed", function () {
    it("lets the admin grant and revoke MINTER_ROLE", async function () {
      const { auroPeg, admin, monitor } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );
      const minterRole = await auroPeg.MINTER_ROLE();

      await auroPeg.connect(admin).grantRole(minterRole, monitor.address);
      expect(await auroPeg.hasRole(minterRole, monitor.address)).to.be.true;

      await auroPeg.connect(admin).revokeRole(minterRole, monitor.address);
      expect(await auroPeg.hasRole(minterRole, monitor.address)).to.be.false;
    });
  });
});
