# Architecture

This section describes how the repository’s contracts (`src/`) compose into an end-to-end protocol.

## High-level components

### 1) Synthetic asset: `dfUSD`

`dfUSD` is an ERC‑20 with role‑based permissions:

- `MINTER_ROLE`: entities that can mint `dfUSD` (e.g. the PSM)
- `ALLOCATOR_ROLE`: entities that can allocate `dfUSD` into ERC‑4626 vaults (protocol treasury operations)
- `KEEPER_ROLE`: entities that can move accrued interest into the Savings Rate Module

See `docs/gitbook/contracts/dfusd.md`.

### 2) Debt + collateral vaults: EVK `EVault`s

The protocol relies on EVK’s `EVault` abstraction for:

- Deposit/withdraw of collateral assets
- Borrow/repay of the debt asset (`dfUSD`)
- Risk controls (LTVs) and liquidity/accounting

In this repository, vaults are deployed through EVK’s `GenericFactory` and configured with:

- An oracle router (`EulerRouter`) and adapters (Chainlink / FixedRate)
- A unit of account (typically USDC)
- A governor admin (Gnosis Safe)
- An interest rate model (IRM) on the `dfUSD` vault

Configuration of collateral LTVs is performed via `ops/src/propose-synth-collateral.ts`.

### 3) Peg Stability Module (PSM)

The PSM is a swap module that allows users to mint/burn `dfUSD` against an underlying ERC‑20 (e.g. USDC) at a configured
conversion price and fees.

It also maintains a TWAR oracle over “accounted reserves” (a tracked reserve value, not `balanceOf()`).

See `docs/gitbook/contracts/psm.md`.

### 4) Savings Rate Module (SRM)

`SavingsRateModule` is an ERC‑4626 vault for `dfUSD` that streams donated `dfUSD` over time to depositors. It is intended
to be used as a “savings rate” primitive (similar to “dripping” vault patterns).

See `docs/gitbook/contracts/savings-rate-module.md`.

### 5) Automation: Rebalancer

`Rebalancer` is an optional utility contract that shifts debt between two Euler accounts (same registered owner) so their
health factors converge, with an explicit fee cap.

See `docs/gitbook/contracts/rebalancer.md`.

## Data flow diagram (conceptual)

```mermaid
flowchart LR
  User((User))
  CollVault[Collateral EVault\n(WETH/WBTC)]
  DebtVault[dfUSD EVault\n(debt vault)]
  PSM[Peg Stability Module\n(USDC ↔ dfUSD)]
  dfUSD[dfUSD token]
  Oracle[EulerRouter + adapters]
  Safe[Gnosis Safe\n(governor/admin)]

  User -->|deposit collateral| CollVault
  User -->|enable collateral (EVC)| DebtVault
  User -->|borrow dfUSD| DebtVault --> dfUSD --> User

  User -->|swap USDC→dfUSD| PSM --> dfUSD
  User -->|swap dfUSD→USDC| PSM

  DebtVault <-->|prices| Oracle
  CollVault <-->|prices| Oracle

  Safe -->|governance| DebtVault
  Safe -->|governance| PSM
  Safe -->|governance| Oracle
```

## Repository mapping

- Protocol contracts: `src/`
- Deploy scripts: `script/`
- Governance proposal automation: `ops/`
- Deployment traces: `broadcast/`
- EVK / oracle dependencies: `lib/` (vendored; do not modify)
