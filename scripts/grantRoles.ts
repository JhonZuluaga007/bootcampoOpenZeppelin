import { network } from "hardhat";

// Delegates operational roles away from the deployer, who holds every role
// right after scripts/deploy.ts (see AuroPeg.initialize()). Set
// MINTER_ADDRESS and/or MONITOR_PAUSER_ADDRESS to grant the corresponding
// role; either or both can be omitted.
//
// UNPAUSER_ROLE is deliberately never touched by this script: it must stay
// with human/multisig admins only, never the off-chain monitor's keeper
// account. See the README's "Design Decisions" section.
async function main() {
  const auroPegAddress = requireEnv("AUROPEG_ADDRESS");
  const minterAddress = process.env.MINTER_ADDRESS;
  const monitorPauserAddress = process.env.MONITOR_PAUSER_ADDRESS;

  if (!minterAddress && !monitorPauserAddress) {
    console.log("Nothing to do: set MINTER_ADDRESS and/or MONITOR_PAUSER_ADDRESS to grant roles.");
    return;
  }

  const { ethers } = await network.create();
  const [signer] = await ethers.getSigners();
  const auroPeg = await ethers.getContractAt("AuroPeg", auroPegAddress, signer);

  if (minterAddress) {
    console.log(`Granting MINTER_ROLE to ${minterAddress}...`);
    const tx = await auroPeg.grantRole(await auroPeg.MINTER_ROLE(), minterAddress);
    await tx.wait();
    console.log("  done.");
  }

  if (monitorPauserAddress) {
    console.log(`Granting PAUSER_ROLE to ${monitorPauserAddress} (the off-chain monitor keeper)...`);
    console.log(
      "  Note: UNPAUSER_ROLE is never granted here — unpausing stays a manual, human decision.",
    );
    const tx = await auroPeg.grantRole(await auroPeg.PAUSER_ROLE(), monitorPauserAddress);
    await tx.wait();
    console.log("  done.");
  }
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
