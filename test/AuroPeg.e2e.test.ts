import { expect } from "chai";
import {
  deployAuroPegFixture,
  ethers,
  networkHelpers,
} from "./helpers/fixtures.js";
import { INITIAL_RESERVE_GRAMS } from "./helpers/constants.js";

// 1,000,000 grams at 8-decimal oracle precision → 1,000,000e18 in
// 18-decimal token units.
const RESERVE_IN_TOKEN_UNITS = INITIAL_RESERVE_GRAMS * 10n ** 10n;
const ONE_GRAM = 10n ** 18n;

describe("AuroPeg end-to-end scenario", function () {
  it("walks through multi-user minting, a reserve drop, a manual pause/unpause cycle, and recovery", async function () {
    const { auroPeg, goldReserveOracle, admin, other: alice, monitor } =
      await networkHelpers.loadFixture(deployAuroPegFixture);
    const [, , , bob] = await ethers.getSigners();

    // --- 1. Two users mint against the healthy, initial reserve. ---
    const aliceMint = (RESERVE_IN_TOKEN_UNITS * 50n) / 100n;
    const bobMint = (RESERVE_IN_TOKEN_UNITS * 40n) / 100n;
    await auroPeg.connect(admin).mint(alice.address, aliceMint);
    await auroPeg.connect(admin).mint(bob.address, bobMint);
    expect(await auroPeg.totalSupply()).to.equal(aliceMint + bobMint);

    // --- 2. Reserves fluctuate upward: the custodian reports more gold,
    // freeing up capacity that didn't exist before. ---
    const doubledReserveGrams = INITIAL_RESERVE_GRAMS * 2n;
    await goldReserveOracle.connect(admin).setReserve(doubledReserveGrams);
    const topUpMint = (RESERVE_IN_TOKEN_UNITS * 60n) / 100n; // only possible post-increase
    await auroPeg.connect(admin).mint(alice.address, topUpMint);
    const supplyAfterTopUp = aliceMint + bobMint + topUpMint;
    expect(await auroPeg.totalSupply()).to.equal(supplyAfterTopUp);
    expect(supplyAfterTopUp).to.be.greaterThan(RESERVE_IN_TOKEN_UNITS); // exceeds the original cap

    // --- 3. The reserve drops sharply; the circuit breaker blocks any
    // further mint once outstanding supply exceeds the new, lower cap. ---
    await goldReserveOracle.connect(admin).simulateReserveDrop(5_000n); // 50% off the doubled reserve
    const availableAfterDrop = await auroPeg.currentReserves();
    expect(supplyAfterTopUp).to.be.greaterThan(availableAfterDrop);

    await expect(
      auroPeg.connect(admin).mint(alice.address, 1n),
    ).to.be.revertedWithCustomError(auroPeg, "InsufficientReserves");

    // --- 4. The off-chain monitor — holding only PAUSER_ROLE, delegated
    // here the same way scripts/grantRoles.ts would in production — reacts
    // to the drop by pausing minting. ---
    await auroPeg.connect(admin).grantRole(await auroPeg.PAUSER_ROLE(), monitor.address);
    await auroPeg.connect(monitor).pause();
    expect(await auroPeg.paused()).to.be.true;

    // --- 5. That same monitor account can never unpause: it was deliberately
    // never granted UNPAUSER_ROLE, so resuming minting stays a human decision. ---
    await expect(
      auroPeg.connect(monitor).unpause(),
    ).to.be.revertedWithCustomError(auroPeg, "AccessControlUnauthorizedAccount");

    // Holders can still exit their position while paused — pause only gates mint.
    await expect(auroPeg.connect(alice).burn(ONE_GRAM)).to.not.revert(ethers);

    // --- 6. The admin "fixes" the reserve (the custodian restocks) and
    // manually unpauses — never the monitor. ---
    await goldReserveOracle.connect(admin).setReserve(doubledReserveGrams);
    await auroPeg.connect(admin).unpause();
    expect(await auroPeg.paused()).to.be.false;

    // --- 7. Normal operation resumes. ---
    await expect(
      auroPeg.connect(admin).mint(alice.address, ONE_GRAM),
    ).to.not.revert(ethers);
    expect(await auroPeg.totalSupply()).to.equal(supplyAfterTopUp - ONE_GRAM + ONE_GRAM);
  });
});
