import "dotenv/config";
import { configVariable, defineConfig } from "hardhat/config";
import hardhatToolboxMochaEthers from "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import hardhatUpgrades from "@openzeppelin/hardhat-upgrades";

export default defineConfig({
  plugins: [hardhatToolboxMochaEthers, hardhatUpgrades],
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    sepolia: {
      type: "http",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("PRIVATE_KEY")],
    },
    // In-memory Hardhat Network forked from live Sepolia state. Only used
    // by the optional test/AuroPeg.priceFeed.fork.test.ts, which is
    // skipped unless SEPOLIA_RPC_URL is set — never part of the default
    // `npx hardhat test` run.
    sepoliaFork: {
      type: "edr-simulated",
      chainType: "l1",
      forking: {
        url: configVariable("SEPOLIA_RPC_URL"),
      },
    },
  },
  verify: {
    etherscan: {
      apiKey: configVariable("ETHERSCAN_API_KEY"),
    },
  },
});
