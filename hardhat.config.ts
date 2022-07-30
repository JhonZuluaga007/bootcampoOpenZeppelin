import * as dotenv from "dotenv";

import { HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-ethers";
import "hardhat-gas-reporter";


import { accounts } from "./utils/network";

dotenv.config();

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

const config: HardhatUserConfig = {
  solidity: "0.8.9",
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      accounts: accounts()
    },
    ropsten: {
      url: process.env.ROPSTEN_URL || "",
      accounts: accounts("ropsten"),
    },
    mumbai: {
      url: process.env.MUMBAI_URL || "",
      accounts: accounts("mumbai"),
    },
    goerli: {
      url: process.env.GOERLI_URL || "",
			accounts: accounts("goerli"),
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

export default config;
