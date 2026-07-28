# AuroPeg Protocol

AuroPeg is a 1:1 gold-backed (grams), UUPS-upgradeable ERC-20 stablecoin
with an on-chain Proof-of-Reserve circuit breaker on minting. It replicates
a production stablecoin architecture (COPW, built for Wenia/Bancolombia)
using OpenZeppelin upgradeable contracts and a Chainlink-shaped
Proof-of-Reserve feed — but backed by gold instead of fiat.

It is Project 1 of a three-part open-source portfolio initiative:

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

## Architecture

```
 Off-chain custodian                  Chainlink (real, Sepolia)
 attests gold reserve                 XAU/USD spot price
        │                                     │
        │ latestRoundData()                   │ latestRoundData()
        ▼                                     ▼
 ┌─────────────────────┐             ┌──────────────────────┐
 │ MockGoldReserveOracle│             │  real XAU/USD feed    │
 │ (AggregatorV3Interface)            │  (informational only) │
 └──────────┬───────────┘             └───────────┬───────────┘
            │ gates mint()                         │ getGoldPriceUSD()
            │ (Secure-Mint / circuit breaker)       │ (display only, never
            ▼                                       │  gates mint)
 ┌──────────────────────────────────────────────────┴──────────┐
 │                        AuroPeg.sol                            │
 │            UUPS-upgradeable ERC-20, 18 decimals                │
 │  mint() ─ MINTER_ROLE, whenNotPaused, reserve-gated             │
 │  burn() ─ anyone, whole-gram only, never paused                 │
 │  pause() ─ PAUSER_ROLE      unpause() ─ UNPAUSER_ROLE            │
 └───────────────────────────────┬────────────────────────────────┘
                                  │ DEFAULT_ADMIN_ROLE (upgrades, role admin)
                                  ▼
                     ┌─────────────────────────────┐
                     │       AuroPegTimelock         │
                     │ TimelockController, delayed    │
                     │ schedule()/execute() only       │
                     └─────────────────────────────┘
```

`MINTER_ROLE`, `PAUSER_ROLE`, and `UNPAUSER_ROLE` are deliberately kept
outside the timelock — they're granted directly to operational addresses
(see `scripts/grantRoles.ts`) so day-to-day minting and the emergency pause
lever stay instant. Only upgrades and role administration go through the
timelock's mandatory delay.

## Design decisions

- **UUPS over Transparent Proxy** — cheaper to deploy per-instance and is
  OpenZeppelin's current recommendation; `_authorizeUpgrade` is restricted
  to `DEFAULT_ADMIN_ROLE`.
- **Mint circuit breaker (Secure-Mint pattern)** — `mint()` reverts with
  `InsufficientReserves` if `totalSupply() + amount` would exceed the
  reserve reported by `goldReserveOracle`, and reverts with
  `StaleReserveData` if that reserve reading is missing, non-positive, or
  older than `MAX_RESERVE_STALENESS` (1 day). This mirrors Chainlink's own
  Proof-of-Reserve "Secure Mint" guidance for collateralized stablecoins.
- **`pause()` only gates `mint()`** — it's the circuit breaker's "stop new
  issuance" lever, not a full token freeze. Transfers and `burn()` are
  never blocked, so holders can always exit during an incident.
- **A 4th role, `UNPAUSER_ROLE`** — kept separate from `DEFAULT_ADMIN_ROLE`
  and never granted to the off-chain monitor's keeper account (which may
  hold `PAUSER_ROLE` to auto-pause on a reserve drop). This makes "the
  monitor can never unpause" a testable access-control fact, not just a
  convention — see `test/AuroPeg.accessControl.test.ts` and
  `test/AuroPeg.pauseUnpause.test.ts`.
- **Whole-gram burns** — `burn()` requires `amount` to be a multiple of
  `1e18` (one full gram), reverting with `InvalidBurnAmount` otherwise.
  Physical redemption can't ship a fraction of a gram, so a sub-gram
  remainder is never accepted for burning; it stays transferable on-chain.
- **Non-reverting staleness flag on the informational price feed** —
  `getGoldPriceUSD()` returns `(price, updatedAt, isStale)` and never
  reverts, unlike `currentReserves()`. It's purely a display value (never
  consulted by the mint circuit breaker), so a stale reading is reported
  for the caller to handle, not hard-blocked.
- **`ReentrancyGuardTransient` instead of `ReentrancyGuardUpgradeable`** —
  no `ReentrancyGuardUpgradeable` variant is published for OpenZeppelin
  Contracts (Upgradeable) v5.x. `ReentrancyGuardTransient` (EIP-1153
  transient storage, from the plain non-upgradeable package) is the
  maintainers' current recommended replacement: it's stateless, so it
  carries no storage-layout risk and needs no initializer.
- **Storage gap** — `AuroPeg` reserves `uint256[50] private __gap` so a
  future upgrade that inserts (not just appends) a variable can't collide
  with the existing storage layout.
- **`TimelockController` for `DEFAULT_ADMIN_ROLE`** — after
  `scripts/deployTimelock.ts` runs, upgrading the contract or changing
  role membership requires a scheduled operation and a mandatory delay
  (2 days by default). This mitigates the single-EOA centralization risk
  flagged in the Phase 5.5 security audit without touching day-to-day
  operational roles.
- **The mock oracle mirrors `AggregatorV3Interface` exactly** —
  `MockGoldReserveOracle` implements the real Chainlink aggregator ABI, so
  swapping in a genuine Proof-of-Reserve feed later requires zero
  `AuroPeg.sol` changes, only a new constructor argument.

## Known limitations

- **Mocked Proof of Reserve.** No real on-chain PoR feed exists for a
  fictional grams-of-gold custodial asset on a public testnet, so
  `MockGoldReserveOracle` stands in for it. It mirrors the real interface
  exactly for this reason.
- **Single-source oracle trust model.** The circuit breaker trusts
  whoever owns `goldReserveOracle` to report honestly — there's no
  multi-source aggregation. This matches how real Chainlink Proof of
  Reserve itself works (attestation from a designated reporter/custodian),
  it isn't a shortcut specific to the mock.
- **Off-chain physical redemption.** `burn()` only destroys tokens
  on-chain and emits `RedemptionRequested`; actually shipping the physical
  gold is an entirely manual, off-chain process.
- **`getGoldPriceUSD()` is informational only.** It never affects mint
  eligibility — a stale or manipulated USD spot price cannot be used to
  under- or over-mint.
- **`simulateReserveDrop()` is a testnet-only demo helper**, callable by
  anyone on `MockGoldReserveOracle`. It exists purely so a live Sepolia
  demo (or a test) can trigger a reserve-drop scenario without owner keys.
  A production PoR oracle would never expose this.
- **The demo timelock defaults to a single EOA** as both proposer and
  executor for simplicity (`scripts/deployTimelock.ts`). A real production
  setup should use a multisig (e.g. Safe) in that role, not a single key.

## Security

A senior-level manual audit (SWC Registry / OWASP Smart Contract Top 10 /
2025-2026 OpenZeppelin·Trail of Bits·Consensys Diligence audit patterns)
was run in Phase 5.5, before any new functionality was added on top.

**Result: 0 Critical, 0 High, 1 Medium, 3 Low, 3 Informational.** Every
finding with contract-level impact was fixed in code; the two findings
whose correct mitigation is a deployment/governance concern
(centralization of `DEFAULT_ADMIN_ROLE`; the single-oracle trust model)
are addressed by the `AuroPegTimelock` handover and documented above,
respectively.

| ID | Severity | Finding | Resolution |
|---|---|---|---|
| M-01 | Medium | No storage gap on `AuroPeg`'s own variables | Added `uint256[50] private __gap` |
| L-01 | Low | `getGoldPriceUSD()` had no staleness signal | Added `MAX_PRICE_STALENESS` + non-reverting `isStale` flag |
| L-02 | Low | `burn()` could truncate `gramsOfGold` to 0 while destroying real value | `burn()` now requires whole-gram amounts |
| L-03 | Low | No events on oracle wiring | Added `GoldReserveOracleSet`/`PriceFeedSet` |
| I-01 | Informational | Centralized `DEFAULT_ADMIN_ROLE` | Mitigated via `AuroPegTimelock` (see Architecture) |
| I-02 | Informational | `MockGoldReserveOracle` used single-step `Ownable` | Switched to `Ownable2Step` |
| I-03 | Informational | Single-source oracle trust model | Documented above (matches real Chainlink PoR) |

Full findings and rationale: `docs/issues/phase-5-5-security-audit-hardening.md`
and `docs/prs/phase-5-5-security-audit-hardening.md`.

## Test suite

96 tests across 13 files (95 passing, 1 intentionally skipped by default).

| File | Covers | Tests |
|---|---|---|
| `AuroPeg.deployment.test.ts` | Deployment, initialization, zero-address guards, re-init protection | 11 |
| `AuroPeg.minting.test.ts` | Mint happy path, access control, input validation | 8 |
| `AuroPeg.circuitBreaker.test.ts` | Decimal conversion, reserve boundaries, staleness edge cases | 8 |
| `AuroPeg.reserveDrop.test.ts` | Reserve-drop scenario, manual incident response | 6 |
| `AuroPeg.pauseUnpause.test.ts` | Pause/unpause access control and effects on mint/burn/transfer | 11 |
| `AuroPeg.burnRedemption.test.ts` | Burn/redemption, whole-gram enforcement | 8 |
| `AuroPeg.accessControl.test.ts` | Full access-control sweep across every restricted function | 8 |
| `AuroPeg.upgrade.test.ts` | UUPS upgrade safety, storage preservation | 5 |
| `AuroPeg.e2e.test.ts` | Full multi-user, multi-incident narrative scenario | 1 |
| `AuroPeg.priceFeed.test.ts` | XAU/USD price feed (mock-backed, always runs) | 8 |
| `AuroPeg.priceFeed.fork.test.ts` | XAU/USD price feed against the real Sepolia feed (optional) | 1 (skipped by default) |
| `AuroPeg.timelock.test.ts` | `DEFAULT_ADMIN_ROLE` timelock handover and delayed execution | 9 |
| `MockGoldReserveOracle.test.ts` | Mock oracle unit tests | 12 |

```shell
npx hardhat test              # full suite, fork test skipped by default
npx hardhat coverage          # coverage report
SEPOLIA_RPC_URL=... npx hardhat test test/AuroPeg.priceFeed.fork.test.ts   # optional, against the real feed
```

## Deployment (Sepolia)

```shell
# 1. Deploy the full stack: reserve oracle + price feed + AuroPeg proxy.
npm run deploy:sepolia
# -> prints AUROPEG_ADDRESS, AUROPEG_IMPLEMENTATION_ADDRESS, and the oracle addresses.

# 2. Verify the implementation contract on Etherscan.
npx hardhat verify --network sepolia <AUROPEG_IMPLEMENTATION_ADDRESS>
# Etherscan auto-detects the ERC1967 proxy once the implementation is
# verified; if it doesn't, use the "Is this a proxy?" tool on the proxy
# address's Etherscan page to link them manually.

# 3. Delegate operational roles away from the deployer.
MINTER_ADDRESS=0x... MONITOR_PAUSER_ADDRESS=0x... AUROPEG_ADDRESS=<proxy> \
  npm run grant-roles:sepolia

# 4. Hand DEFAULT_ADMIN_ROLE to a timelock (mitigates I-01; see Security).
AUROPEG_ADDRESS=<proxy> npm run deploy-timelock:sepolia
# -> prints TIMELOCK_ADDRESS. From this point on, upgrades and role
#    changes must go through the timelock's schedule()/execute() flow.
```

Environment variables read by the scripts (all optional except
`AUROPEG_ADDRESS` where noted; unset ones fall back to sensible demo
defaults):

| Variable | Used by | Default |
|---|---|---|
| `ADMIN_ADDRESS` | `deploy.ts` | the deployer |
| `INITIAL_RESERVE_GRAMS` | `deploy.ts`, `deployMockOracle.ts` | 1,000,000 g |
| `PRICE_FEED_ADDRESS` | `deploy.ts` | real Chainlink XAU/USD on Sepolia, a mock elsewhere |
| `MINTER_ADDRESS`, `MONITOR_PAUSER_ADDRESS` | `grantRoles.ts` | unset (no-op if both unset) |
| `AUROPEG_ADDRESS` | `grantRoles.ts`, `deployTimelock.ts`, `upgrade.ts` | **required** |
| `TIMELOCK_MIN_DELAY_SECONDS` | `deployTimelock.ts` | 172800 (2 days) |
| `TIMELOCK_PROPOSER_ADDRESS`, `TIMELOCK_EXECUTOR_ADDRESS` | `deployTimelock.ts` | the deployer |
| `NEW_IMPLEMENTATION_NAME` | `upgrade.ts` | `AuroPeg` (edit before a real upgrade) |

Reconfirm the real Chainlink XAU/USD feed address
(`0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea`) against
[Chainlink's price feed directory](https://docs.chain.link/data-feeds/price-feeds/addresses)
before deploying — testnet addresses can change without notice.

### Sepolia addresses

_Not yet deployed. This section will be filled in with the live proxy,
implementation, oracle, and timelock addresses after the first Sepolia
deployment._

## Development process

Built in phases, each with a corresponding GitHub-issue-style spec and a
PR description under `docs/issues/` and `docs/prs/`, including a dedicated
security-audit phase (5.5) run before this final phase.

## License

MIT — see `LICENSE`.
