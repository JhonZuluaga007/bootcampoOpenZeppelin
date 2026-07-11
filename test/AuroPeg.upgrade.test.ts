import { expect } from "chai";
import {
  deployAuroPegFixture,
  ethers,
  networkHelpers,
  upgrades,
} from "./helpers/fixtures.js";

describe("AuroPeg upgrade safety", function () {
  it("preserves storage (balances, totalSupply, roles) across an upgrade", async function () {
    const { auroPeg, admin, other } = await networkHelpers.loadFixture(
      deployAuroPegFixture,
    );
    const amount = 250n * 10n ** 18n;
    await auroPeg.connect(admin).mint(other.address, amount);

    const AuroPegV2Mock = await ethers.getContractFactory("AuroPegV2Mock");
    const upgraded = await upgrades.upgradeProxy(
      await auroPeg.getAddress(),
      AuroPegV2Mock,
    );

    expect(await upgraded.balanceOf(other.address)).to.equal(amount);
    expect(await upgraded.totalSupply()).to.equal(amount);
    expect(
      await upgraded.hasRole(await upgraded.DEFAULT_ADMIN_ROLE(), admin.address),
    ).to.be.true;
    expect(await upgraded.hasRole(await upgraded.MINTER_ROLE(), admin.address))
      .to.be.true;
  });

  it("keeps the same proxy address across the upgrade", async function () {
    const { auroPeg } = await networkHelpers.loadFixture(deployAuroPegFixture);
    const proxyAddress = await auroPeg.getAddress();

    const AuroPegV2Mock = await ethers.getContractFactory("AuroPegV2Mock");
    const upgraded = await upgrades.upgradeProxy(proxyAddress, AuroPegV2Mock);

    expect(await upgraded.getAddress()).to.equal(proxyAddress);
  });

  it("exposes the new V2 functionality after upgrading", async function () {
    const { auroPeg, admin } = await networkHelpers.loadFixture(
      deployAuroPegFixture,
    );

    const AuroPegV2Mock = await ethers.getContractFactory("AuroPegV2Mock");
    const upgraded = await upgrades.upgradeProxy(
      await auroPeg.getAddress(),
      AuroPegV2Mock,
    );

    expect(await upgraded.version()).to.equal("v2");
    await upgraded.connect(admin).setUpgradeMarker(42n);
    expect(await upgraded.upgradeMarker()).to.equal(42n);
  });

  it("still refuses to re-run initialize after an upgrade", async function () {
    const { auroPeg, admin, goldReserveOracle, xauUsdPriceFeed } =
      await networkHelpers.loadFixture(deployAuroPegFixture);

    const AuroPegV2Mock = await ethers.getContractFactory("AuroPegV2Mock");
    const upgraded = await upgrades.upgradeProxy(
      await auroPeg.getAddress(),
      AuroPegV2Mock,
    );

    await expect(
      upgraded.initialize(
        "AuroPeg",
        "AUP",
        admin.address,
        await goldReserveOracle.getAddress(),
        await xauUsdPriceFeed.getAddress(),
      ),
    ).to.be.revertedWithCustomError(upgraded, "InvalidInitialization");
  });

  it("reverts when a non-admin account attempts the upgrade directly", async function () {
    const { auroPeg, other } = await networkHelpers.loadFixture(
      deployAuroPegFixture,
    );

    // Deploy a standalone V2Mock implementation to use as the upgrade
    // target, bypassing the upgrades plugin (which always signs with the
    // connection's default signer) so we can attempt the call as `other`.
    const AuroPegV2Mock = await ethers.getContractFactory("AuroPegV2Mock");
    const newImplementation = await AuroPegV2Mock.deploy();
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
});
