# AuroPeg Protocol

> 🚧 Under active development. This README is a skeleton for Phase 0 and will
> be filled in fully (architecture diagram, design decisions, known
> limitations, test breakdown, deployment instructions, Sepolia addresses) in
> the final implementation phase.

AuroPeg is a 1:1 gold-backed (grams), upgradeable ERC-20 stablecoin with an
on-chain Proof-of-Reserve circuit breaker on minting. It is Project 1 of a
three-part open-source portfolio initiative:

1. **`auropeg-protocol`** (this repo) — the smart contracts.
2. `auropeg-monitor` — off-chain monitoring service (OpenZeppelin Monitor)
   that watches reserves and calls `pause()` automatically. _Coming soon._
3. `auropeg-ui` — a Next.js frontend to mint, burn, and observe the circuit
   breaker live on Sepolia. _Coming soon._

## Requirements

- Node.js `>=22.13.0` (see `.nvmrc` — run `nvm use`)
- npm

## Setup

```shell
npm install
cp .env.example .env   # fill in SEPOLIA_RPC_URL, PRIVATE_KEY, ETHERSCAN_API_KEY
npx hardhat compile
npx hardhat test
```

## Sections coming in later phases

- Architecture overview
- Design decisions (UUPS, mint circuit breaker, manual-only `unpause()` +
  `UNPAUSER_ROLE`, why the mock oracle mirrors Chainlink's real interface)
- Known limitations (mocked Proof of Reserve, off-chain physical redemption)
- Test suite breakdown
- Deployment & Etherscan verification instructions
- Sepolia contract addresses
- Links to `auropeg-monitor` and `auropeg-ui`
