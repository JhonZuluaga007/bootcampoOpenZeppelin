import hre, { network } from "hardhat";
import { upgrades as upgradesFactory } from "@openzeppelin/hardhat-upgrades";
import { INITIAL_RESERVE_GRAMS, TOKEN_NAME, TOKEN_SYMBOL } from "./constants.js";

const connection = await network.create();

export const { ethers, networkHelpers } = connection;
export const upgrades = await upgradesFactory(hre, connection);

export async function deployAuroPegFixture() {
  const [admin, other, monitor] = await ethers.getSigners();

  const MockGoldReserveOracle = await ethers.getContractFactory(
    "MockGoldReserveOracle",
  );
  const goldReserveOracle = await MockGoldReserveOracle.deploy(
    INITIAL_RESERVE_GRAMS,
    admin.address,
  );

  // Stand-in for the real Chainlink XAU/USD feed: shares the exact same
  // AggregatorV3Interface ABI, so it's enough to satisfy AuroPeg's
  // non-zero address check during deployment/initialization tests. Wired
  // up for real (`getGoldPriceUSD()`) in a later phase.
  const xauUsdPriceFeed = await MockGoldReserveOracle.deploy(
    INITIAL_RESERVE_GRAMS,
    admin.address,
  );

  const AuroPeg = await ethers.getContractFactory("AuroPeg");
  const auroPeg = await upgrades.deployProxy(
    AuroPeg,
    [
      TOKEN_NAME,
      TOKEN_SYMBOL,
      admin.address,
      await goldReserveOracle.getAddress(),
      await xauUsdPriceFeed.getAddress(),
    ],
    { kind: "uups" },
  );

  return { auroPeg, goldReserveOracle, xauUsdPriceFeed, admin, other, monitor };
}
