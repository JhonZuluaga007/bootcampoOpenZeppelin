import { expect } from "chai";
import { ZeroAddress } from "ethers";
import {
  deployAuroPegFixture,
  ethers,
  networkHelpers,
  upgrades,
} from "./helpers/fixtures.js";
import {
  INITIAL_RESERVE_GRAMS,
  TOKEN_NAME,
  TOKEN_SYMBOL,
} from "./helpers/constants.js";

describe("AuroPeg deployment & initialization", function () {
  describe("Token metadata", function () {
    it("sets the name, symbol, and standard 18 decimals", async function () {
      const { auroPeg } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );

      expect(await auroPeg.name()).to.equal(TOKEN_NAME);
      expect(await auroPeg.symbol()).to.equal(TOKEN_SYMBOL);
      expect(await auroPeg.decimals()).to.equal(18);
      expect(await auroPeg.totalSupply()).to.equal(0n);
    });
  });

  describe("Oracle wiring", function () {
    it("stores the gold reserve oracle and XAU/USD price feed addresses", async function () {
      const { auroPeg, goldReserveOracle, xauUsdPriceFeed } =
        await networkHelpers.loadFixture(deployAuroPegFixture);

      expect(await auroPeg.goldReserveOracle()).to.equal(
        await goldReserveOracle.getAddress(),
      );
      expect(await auroPeg.xauUsdPriceFeed()).to.equal(
        await xauUsdPriceFeed.getAddress(),
      );
    });
  });

  describe("Role assignment", function () {
    it("grants the default admin every role", async function () {
      const { auroPeg, admin } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );

      expect(
        await auroPeg.hasRole(await auroPeg.DEFAULT_ADMIN_ROLE(), admin.address),
      ).to.be.true;
      expect(await auroPeg.hasRole(await auroPeg.MINTER_ROLE(), admin.address))
        .to.be.true;
      expect(await auroPeg.hasRole(await auroPeg.PAUSER_ROLE(), admin.address))
        .to.be.true;
      expect(
        await auroPeg.hasRole(await auroPeg.UNPAUSER_ROLE(), admin.address),
      ).to.be.true;
    });

    it("does not grant any role to unrelated accounts", async function () {
      const { auroPeg, other } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );

      expect(
        await auroPeg.hasRole(await auroPeg.DEFAULT_ADMIN_ROLE(), other.address),
      ).to.be.false;
      expect(await auroPeg.hasRole(await auroPeg.MINTER_ROLE(), other.address))
        .to.be.false;
    });
  });

  describe("Zero-address guards", function () {
    it("reverts when the default admin is the zero address", async function () {
      const { goldReserveOracle, xauUsdPriceFeed } =
        await networkHelpers.loadFixture(deployAuroPegFixture);
      const AuroPeg = await ethers.getContractFactory("AuroPeg");

      await expect(
        upgrades.deployProxy(
          AuroPeg,
          [
            TOKEN_NAME,
            TOKEN_SYMBOL,
            ZeroAddress,
            await goldReserveOracle.getAddress(),
            await xauUsdPriceFeed.getAddress(),
          ],
          { kind: "uups" },
        ),
      ).to.be.revertedWithCustomError(AuroPeg, "ZeroAddress");
    });

    it("reverts when the gold reserve oracle is the zero address", async function () {
      const { admin, xauUsdPriceFeed } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );
      const AuroPeg = await ethers.getContractFactory("AuroPeg");

      await expect(
        upgrades.deployProxy(
          AuroPeg,
          [
            TOKEN_NAME,
            TOKEN_SYMBOL,
            admin.address,
            ZeroAddress,
            await xauUsdPriceFeed.getAddress(),
          ],
          { kind: "uups" },
        ),
      ).to.be.revertedWithCustomError(AuroPeg, "ZeroAddress");
    });

    it("reverts when the XAU/USD price feed is the zero address", async function () {
      const { admin, goldReserveOracle } = await networkHelpers.loadFixture(
        deployAuroPegFixture,
      );
      const AuroPeg = await ethers.getContractFactory("AuroPeg");

      await expect(
        upgrades.deployProxy(
          AuroPeg,
          [
            TOKEN_NAME,
            TOKEN_SYMBOL,
            admin.address,
            await goldReserveOracle.getAddress(),
            ZeroAddress,
          ],
          { kind: "uups" },
        ),
      ).to.be.revertedWithCustomError(AuroPeg, "ZeroAddress");
    });
  });

  describe("Re-initialization protection", function () {
    it("reverts when initialize is called a second time on the proxy", async function () {
      const { auroPeg, admin, goldReserveOracle, xauUsdPriceFeed } =
        await networkHelpers.loadFixture(deployAuroPegFixture);

      await expect(
        auroPeg.initialize(
          TOKEN_NAME,
          TOKEN_SYMBOL,
          admin.address,
          await goldReserveOracle.getAddress(),
          await xauUsdPriceFeed.getAddress(),
        ),
      ).to.be.revertedWithCustomError(auroPeg, "InvalidInitialization");
    });

    it("reverts when initialize is called directly on the implementation contract", async function () {
      const { auroPeg, admin, goldReserveOracle, xauUsdPriceFeed } =
        await networkHelpers.loadFixture(deployAuroPegFixture);

      const implementationAddress = await upgrades.erc1967.getImplementationAddress(
        await auroPeg.getAddress(),
      );
      const AuroPeg = await ethers.getContractFactory("AuroPeg");
      const implementation = AuroPeg.attach(implementationAddress);

      await expect(
        implementation.initialize(
          TOKEN_NAME,
          TOKEN_SYMBOL,
          admin.address,
          await goldReserveOracle.getAddress(),
          await xauUsdPriceFeed.getAddress(),
        ),
      ).to.be.revertedWithCustomError(auroPeg, "InvalidInitialization");
    });
  });

  it("reports the expected initial reserve on its configured oracle", async function () {
    const { goldReserveOracle } = await networkHelpers.loadFixture(
      deployAuroPegFixture,
    );

    const [, answer] = await goldReserveOracle.latestRoundData();
    expect(answer).to.equal(INITIAL_RESERVE_GRAMS);
  });
});
