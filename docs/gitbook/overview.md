# Overview

DIBOR is a collateralized debt protocol that issues a synthetic USD token (`dfUSD`) backed by over‑collateralized
positions and integrated with the Euler Vault Kit (EVK) lending stack.

At a high level, the system consists of:

- `dfUSD`: the synthetic USD ERC‑20 token with controlled mint/burn via `AccessControl`.
- `EVault` instances (from EVK): vaults for `dfUSD` (debt) and for collateral assets (e.g. WETH/WBTC).
- A Peg Stability Module (PSM): swaps `dfUSD` ↔ underlying (e.g. USDC) at a configured conversion price + fees.
- Optional modules:
  - `SavingsRateModule`: ERC‑4626 vault for `dfUSD` that streams donated tokens to depositors.
  - `Rebalancer`: EIP‑712 authorized debt shifter between two Euler accounts sharing the same owner.

## Core user flows

### Borrow `dfUSD` (CDP)

1. Deposit collateral into a collateral `EVault` (e.g. WETH vault).
2. Enable that vault as collateral for your Euler account (via EVC).
3. Borrow from the `dfUSD` `EVault` up to governance-defined LTV limits.

The borrow rate is set by the configured interest rate model (IRM) on the `dfUSD` vault.

### Swap `dfUSD` ↔ USDC (PSM)

Users can swap:

- **USDC → `dfUSD`** (minting `dfUSD` to the receiver) with a fee.
- **`dfUSD` → USDC** (burning `dfUSD` from the caller) with a fee.

The PSM maintains an on-chain time-weighted average reserves (TWAR) oracle for its accounted reserves.

### Earn yield on `dfUSD` (Savings Rate)

The Savings Rate Module is an ERC‑4626 vault for `dfUSD` where donations are “smoothed” over a `smearDuration` and
accrue to depositors over time.

## Governance model (current)

Deployment and parameter updates are designed to be executed via a Gnosis Safe. The repository also includes an
`ops/` TypeScript workspace to prepare governance proposals (Safe transactions) for:

- Setting collateral LTVs on the `dfUSD` vault
- Setting PSM fees
- Updating an EVault’s IRM
- Assigning keepers for operational actions

See [governance.md](governance.md).

## Vision and roadmap

For the longer-term plan and roadmap (dfUSD, RWAs, multichain strategy), see [vision.md](vision.md).
