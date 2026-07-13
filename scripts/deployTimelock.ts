import { network } from "hardhat";

// Mitigates the centralization finding from the Phase 5.5 audit (I-01):
// DEFAULT_ADMIN_ROLE — upgrades and role administration — moves from the
// EOA deployer to a TimelockController. MINTER_ROLE, PAUSER_ROLE, and
// UNPAUSER_ROLE are untouched, so day-to-day mint/pause/unpause stays
// instant; only upgrades and role changes gain a mandatory delay.
const DEFAULT_MIN_DELAY_SECONDS = 2 * 24 * 60 * 60; // 2 days

async function main() {
  const auroPegAddress = requireEnv("AUROPEG_ADDRESS");
  const minDelay = process.env.TIMELOCK_MIN_DELAY_SECONDS
    ? BigInt(process.env.TIMELOCK_MIN_DELAY_SECONDS)
    : BigInt(DEFAULT_MIN_DELAY_SECONDS);

  const { ethers } = await network.create();
  const [deployer] = await ethers.getSigners();
  const proposerAddress = process.env.TIMELOCK_PROPOSER_ADDRESS ?? deployer.address;
  const executorAddress = process.env.TIMELOCK_EXECUTOR_ADDRESS ?? deployer.address;

  console.log(`Deploying AuroPegTimelock (minDelay=${minDelay}s)...`);
  console.log(`  Proposer/canceller: ${proposerAddress}`);
  console.log(`  Executor: ${executorAddress}`);

  const AuroPegTimelock = await ethers.getContractFactory("AuroPegTimelock");
  const timelock = await AuroPegTimelock.deploy(
    minDelay,
    [proposerAddress],
    [executorAddress],
    ethers.ZeroAddress, // no separate optional admin — the timelock self-administers
  );
  await timelock.waitForDeployment();
  const timelockAddress = await timelock.getAddress();
  console.log(`  AuroPegTimelock: ${timelockAddress}`);

  const auroPeg = await ethers.getContractAt("AuroPeg", auroPegAddress, deployer);
  const defaultAdminRole = await auroPeg.DEFAULT_ADMIN_ROLE();

  console.log(`\nGranting DEFAULT_ADMIN_ROLE on AuroPeg (${auroPegAddress}) to the timelock...`);
  await (await auroPeg.grantRole(defaultAdminRole, timelockAddress)).wait();

  console.log("Revoking DEFAULT_ADMIN_ROLE from the deployer...");
  await (await auroPeg.revokeRole(defaultAdminRole, deployer.address)).wait();

  console.log("\nHandover complete. From now on, upgrading AuroPeg or changing its roles");
  console.log("requires the timelock's schedule()/execute() flow (with a");
  console.log(`${minDelay}s delay). MINTER_ROLE, PAUSER_ROLE, and UNPAUSER_ROLE are`);
  console.log("untouched by this script — day-to-day mint/pause/unpause stays instant.");
  console.log(`\nTIMELOCK_ADDRESS=${timelockAddress}`);
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
