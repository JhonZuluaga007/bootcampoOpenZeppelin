import hre, { network } from "hardhat";
import { upgrades as upgradesFactory } from "@openzeppelin/hardhat-upgrades";

// Template for upgrading the AuroPeg proxy. Set NEW_IMPLEMENTATION_NAME to
// the actual new contract before running this for real — it defaults to
// "AuroPeg" only so the script is runnable out of the box against a local
// network for a no-op smoke test.
//
// If DEFAULT_ADMIN_ROLE has been handed to a timelock (see
// scripts/deployTimelock.ts), this script's direct upgradeProxy call will
// revert: the upgrade must instead be scheduled and executed through the
// timelock's schedule()/execute() flow, encoding a call to
// upgradeToAndCall on the proxy.
async function main() {
  const auroPegAddress = requireEnv("AUROPEG_ADDRESS");
  const newImplementationName = process.env.NEW_IMPLEMENTATION_NAME ?? "AuroPeg";

  const connection = await network.create();
  const { ethers } = connection;
  const upgrades = await upgradesFactory(hre, connection);

  console.log(`Upgrading AuroPeg proxy at ${auroPegAddress} to ${newImplementationName}...`);
  const NewImplementation = await ethers.getContractFactory(newImplementationName);
  const upgraded = await upgrades.upgradeProxy(auroPegAddress, NewImplementation);
  await upgraded.waitForDeployment();

  const implementationAddress = await upgrades.erc1967.getImplementationAddress(auroPegAddress);
  console.log(`Upgrade complete. New implementation: ${implementationAddress}`);
  console.log(`Verify it: npx hardhat verify --network sepolia ${implementationAddress}`);
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
