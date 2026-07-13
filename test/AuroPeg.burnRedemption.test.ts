import { expect } from "chai";
import { ZeroAddress } from "ethers";
import {
  deployAuroPegFixture,
  ethers,
  networkHelpers,
} from "./helpers/fixtures.js";

describe("AuroPeg burn / redemption", function () {
  async function deployWithBalanceFixture() {
    const fixture = await deployAuroPegFixture();
    const amount = 500n * 10n ** 18n;
    await fixture.auroPeg.connect(fixture.admin).mint(
      fixture.other.address,
      amount,
    );
    return { ...fixture, mintedAmount: amount };
  }

  describe("Happy path", function () {
    it("burns the caller's own balance and decreases totalSupply", async function () {
      const { auroPeg, other, mintedAmount } = await networkHelpers.loadFixture(
        deployWithBalanceFixture,
      );
      const burnAmount = 200n * 10n ** 18n;

      await expect(auroPeg.connect(other).burn(burnAmount))
        .to.emit(auroPeg, "Transfer")
        .withArgs(other.address, ZeroAddress, burnAmount);

      expect(await auroPeg.balanceOf(other.address)).to.equal(
        mintedAmount - burnAmount,
      );
      expect(await auroPeg.totalSupply()).to.equal(mintedAmount - burnAmount);
    });

    it("emits RedemptionRequested with the correct grams-of-gold conversion", async function () {
      const { auroPeg, other } = await networkHelpers.loadFixture(
        deployWithBalanceFixture,
      );
      const burnAmount = 250n * 10n ** 18n; // 250 grams
      const expectedGrams = 250n;

      await expect(auroPeg.connect(other).burn(burnAmount))
        .to.emit(auroPeg, "RedemptionRequested")
        .withArgs(other.address, burnAmount, expectedGrams);
    });

    it("allows burning the full balance down to zero", async function () {
      const { auroPeg, other, mintedAmount } = await networkHelpers.loadFixture(
        deployWithBalanceFixture,
      );

      await auroPeg.connect(other).burn(mintedAmount);

      expect(await auroPeg.balanceOf(other.address)).to.equal(0n);
    });
  });

  describe("Input validation", function () {
    it("reverts when burning a zero amount", async function () {
      const { auroPeg, other } = await networkHelpers.loadFixture(
        deployWithBalanceFixture,
      );

      await expect(
        auroPeg.connect(other).burn(0n),
      ).to.be.revertedWithCustomError(auroPeg, "ZeroAmount");
    });

    it("reverts when burning more than the caller's balance", async function () {
      const { auroPeg, other, mintedAmount } = await networkHelpers.loadFixture(
        deployWithBalanceFixture,
      );

      await expect(
        auroPeg.connect(other).burn(mintedAmount + 10n ** 18n),
      ).to.be.revertedWithCustomError(auroPeg, "ERC20InsufficientBalance");
    });

    it("reverts when burning an amount that is not a whole gram", async function () {
      const { auroPeg, other } = await networkHelpers.loadFixture(
        deployWithBalanceFixture,
      );
      const fractionalAmount = 10n ** 18n + 1n; // 1 gram + 1 wei

      await expect(auroPeg.connect(other).burn(fractionalAmount))
        .to.be.revertedWithCustomError(auroPeg, "InvalidBurnAmount")
        .withArgs(fractionalAmount);
    });

    it("cannot burn another account's balance", async function () {
      const { auroPeg, monitor, mintedAmount } =
        await networkHelpers.loadFixture(deployWithBalanceFixture);

      await expect(
        auroPeg.connect(monitor).burn(mintedAmount),
      ).to.be.revertedWithCustomError(auroPeg, "ERC20InsufficientBalance");
    });
  });

  describe("Reserve capacity after redemption", function () {
    it("frees up reserve capacity for future mints", async function () {
      const { auroPeg, admin, other, monitor } =
        await networkHelpers.loadFixture(deployWithBalanceFixture);
      const available = await auroPeg.currentReserves();
      const totalSupply = await auroPeg.totalSupply();
      const remainingCapacity = available - totalSupply;

      const oneGram = 10n ** 18n;

      // Minting past the remaining capacity reverts...
      await expect(
        auroPeg.connect(admin).mint(monitor.address, remainingCapacity + oneGram),
      ).to.be.revertedWithCustomError(auroPeg, "InsufficientReserves");

      // ...until a burn frees up exactly enough room (in whole-gram steps,
      // since burn only accepts multiples of 1e18).
      await auroPeg.connect(other).burn(oneGram);
      await expect(
        auroPeg.connect(admin).mint(monitor.address, remainingCapacity + oneGram),
      ).to.not.revert(ethers);
    });
  });
});
