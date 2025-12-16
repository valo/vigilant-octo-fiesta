# DIBOR Protocol

This GitBook is the canonical, user-facing documentation for the DIBOR protocol implemented in this repository.

The protocol issues an over‑collateralized synthetic USD asset (`nUSD`) and wires it into the Euler Vault Kit (EVK)
stack to support collateralized borrowing, modular interest rate policies, and operational automation via a Gnosis
Safe.

## What you can do with the protocol

- **Borrow `nUSD` against collateral** using EVK vaults (e.g. WETH, WBTC) once governance has enabled them as
  collateral for the `nUSD` debt vault.
- **Swap between `nUSD` and the backing asset** (e.g. USDC) via a Peg Stability Module (PSM) with configurable fees.
- **Earn streaming yield on `nUSD`** using the Savings Rate Module (an ERC‑4626 vault that drips donated tokens).
- **Rebalance positions** across two Euler accounts (same owner) using the `Rebalancer`.

## Quick links

- Protocol overview: `docs/gitbook/overview.md`
- Architecture: `docs/gitbook/architecture.md`
- Contracts reference: `docs/gitbook/contracts/`
- Governance & ops: `docs/gitbook/governance.md`
- Deployment: `docs/gitbook/deployment.md`
- Contract addresses: `docs/gitbook/addresses.md`

## Scope and guarantees (draft)

This is an early draft. It aims to document:

- The current code in `src/` and how it is deployed/configured via `script/` and `ops/`.
- The assumptions the system makes about external dependencies (EVK, EVC, price oracles).

It does **not** yet include:

- Formal economic analysis, audits, or an exhaustive threat model.
- Mainnet deployment details (unless explicitly added to `docs/gitbook/addresses.md`).
