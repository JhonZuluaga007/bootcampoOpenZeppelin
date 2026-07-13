import { expect } from "chai";
import { network } from "hardhat";
import { anyUint } from "@nomicfoundation/hardhat-ethers-chai-matchers/withArgs";

const { ethers, networkHelpers } = await network.create();

const INITIAL_RESERVE_GRAMS = 1_000_000n * 10n ** 8n; // 1,000,000 g at 8 decimals

async function deployMockOracleFixture() {
  const [admin, other] = await ethers.getSigners();

  const MockGoldReserveOracle = await ethers.getContractFactory(
    "MockGoldReserveOracle",
  );
  const oracle = await MockGoldReserveOracle.deploy(
    INITIAL_RESERVE_GRAMS,
    admin.address,
  );

  return { oracle, admin, other };
}

describe("MockGoldReserveOracle", function () {
  describe("Constructor", function () {
    it("sets the initial reserve as round 1", async function () {
      const { oracle } = await networkHelpers.loadFixture(
        deployMockOracleFixture,
      );

      const [roundId, answer] = await oracle.latestRoundData();
      expect(roundId).to.equal(1n);
      expect(answer).to.equal(INITIAL_RESERVE_GRAMS);
    });

    it("sets the deployer-provided admin as owner", async function () {
      const { oracle, admin } = await networkHelpers.loadFixture(
        deployMockOracleFixture,
      );

      expect(await oracle.owner()).to.equal(admin.address);
    });

    it("exposes Chainlink-compatible metadata", async function () {
      const { oracle } = await networkHelpers.loadFixture(
        deployMockOracleFixture,
      );

      expect(await oracle.decimals()).to.equal(8);
      expect(await oracle.description()).to.equal(
        "AuroPeg Mock Gold Reserve Oracle (grams, testnet only)",
      );
      expect(await oracle.version()).to.equal(1);
    });
  });

  describe("setReserve access control", function () {
    it("allows the owner to update the reserve", async function () {
      const { oracle } = await networkHelpers.loadFixture(
        deployMockOracleFixture,
      );
      const newReserve = 2_000_000n * 10n ** 8n;

      await expect(oracle.setReserve(newReserve))
        .to.emit(oracle, "ReserveUpdated")
        .withArgs(2n, newReserve, anyUint);

      const [, answer] = await oracle.latestRoundData();
      expect(answer).to.equal(newReserve);
    });

    it("reverts when a non-owner calls setReserve", async function () {
      const { oracle, other } = await networkHelpers.loadFixture(
        deployMockOracleFixture,
      );

      await expect(
        oracle.connect(other).setReserve(1n),
      ).to.be.revertedWithCustomError(oracle, "OwnableUnauthorizedAccount");
    });
  });

  describe("latestRoundData shape", function () {
    it("returns matching startedAt/updatedAt timestamps for the latest round", async function () {
      const { oracle } = await networkHelpers.loadFixture(
        deployMockOracleFixture,
      );

      const [roundId, answer, startedAt, updatedAt, answeredInRound] =
        await oracle.latestRoundData();

      expect(roundId).to.equal(answeredInRound);
      expect(startedAt).to.equal(updatedAt);
      expect(answer).to.equal(INITIAL_RESERVE_GRAMS);
    });
  });

  describe("getRoundData", function () {
    it("returns historical round data for a past round", async function () {
      const { oracle } = await networkHelpers.loadFixture(
        deployMockOracleFixture,
      );
      const newReserve = 2_000_000n * 10n ** 8n;
      await oracle.setReserve(newReserve);

      const [roundId, answer] = await oracle.getRoundData(1n);
      expect(roundId).to.equal(1n);
      expect(answer).to.equal(INITIAL_RESERVE_GRAMS);
    });

    it("reverts for a round that doesn't exist yet", async function () {
      const { oracle } = await networkHelpers.loadFixture(
        deployMockOracleFixture,
      );

      await expect(oracle.getRoundData(99n)).to.be.revertedWith(
        "MockGoldReserveOracle: no data present",
      );
    });
  });

  describe("Ownable2Step ownership transfer", function () {
    it("requires the new owner to accept before ownership actually transfers", async function () {
      const { oracle, admin, other } = await networkHelpers.loadFixture(
        deployMockOracleFixture,
      );

      await oracle.connect(admin).transferOwnership(other.address);
      expect(await oracle.owner()).to.equal(admin.address);
      expect(await oracle.pendingOwner()).to.equal(other.address);

      await oracle.connect(other).acceptOwnership();
      expect(await oracle.owner()).to.equal(other.address);
    });
  });

  describe("simulateReserveDrop", function () {
    it("is callable by anyone and shrinks the reserve by the given bps", async function () {
      const { oracle, other } = await networkHelpers.loadFixture(
        deployMockOracleFixture,
      );

      await oracle.connect(other).simulateReserveDrop(1_000n); // 10%

      const [, answer] = await oracle.latestRoundData();
      const expected =
        INITIAL_RESERVE_GRAMS - (INITIAL_RESERVE_GRAMS * 1_000n) / 10_000n;
      expect(answer).to.equal(expected);
    });

    it("reverts for a bps value of zero", async function () {
      const { oracle } = await networkHelpers.loadFixture(
        deployMockOracleFixture,
      );

      await expect(
        oracle.simulateReserveDrop(0n),
      ).to.be.revertedWith("MockGoldReserveOracle: invalid bps");
    });

    it("reverts for a bps value above the 50% cap", async function () {
      const { oracle } = await networkHelpers.loadFixture(
        deployMockOracleFixture,
      );

      await expect(
        oracle.simulateReserveDrop(5_001n),
      ).to.be.revertedWith("MockGoldReserveOracle: invalid bps");
    });
  });
});
