# Vision & Long-Term Plan

This page describes DIBOR’s intended long-term direction. It is forward-looking and may not be fully implemented in the
current repository.

## Product thesis

DIBOR (Decentralized Inter-Blockchain Offered Rate) aims to be a CDP-based stablecoin and credit primitive that extends
overcollateralized borrowing beyond ERC‑20-only collateral.

- **Stablecoin:** `dfUSD`
- **Savings representation:** `sdfUSD` (dfUSD deposited into the Savings Module, represented as ERC‑4626 shares)
- **Safety target:** conservative collateralization (e.g. ≥150% collateral-to-debt)

## Collateral roadmap

DIBOR’s collateral scope is designed to expand beyond typical DeFi CDP collateral sets:

- **Native BTC and ERC‑20 wrappers** (including institutional-grade custody-backed representations).
- **ETH liquid staking and restaking derivatives** (LST/LRT class collateral).
- **Large-cap non‑ERC20 assets** (e.g. XRP/ADA/LTC) tokenized via qualified custodians.
- **Tokenized securities** such as equities and corporate bonds.

### Custody-backed tokenization (non‑ERC20 assets)

A key mechanism is partnering with custodians who:

- Safeguard the underlying non‑ERC20 asset.
- Issue receivable tokens on an EVM-compatible chain (examples: `dfBTC`, `dfXRP`, `dfADA`).
- Provide 1:1 redeemability for the underlying asset.

## Tokenized TradFi collateral

DIBOR is intended to be an onchain leverage layer for the emerging “tokenized markets” ecosystem.

- Strategic priority: onboarding tokenized blue-chip equities and investment-grade bonds.
- Example partners/venues referenced in the longer-term plan include tokenized security issuers and platforms.
- Proposed initial launch assets include Strategy/MicroStrategy equity (`MSTR`) and preferred shares (subject to partner
  availability and jurisdictional constraints).

## Cross-margin / portfolio positions

DIBOR is intended to support cross-collateralized positions rather than siloed, per-asset vaults:

- A single position can be backed by a portfolio of eligible collateral types.
- A portfolio-level risk model computes an aggregate health factor.
- Borrowing rate can be expressed as a weighted blend driven by the collateral mix.

## “DIBOR rate”: automated interest rate setting

The long-term plan includes an algorithmic borrowing rate that draws from TradFi and DeFi benchmarks:

1. **Risk-free base rate** anchored to the 3‑month US Treasury bill yield.
2. **System leverage / market conditions** derived from the Peg Stability Module (PSM), where reserve coverage of
   circulating stablecoin supply informs a dynamic spread over the base rate.
3. **Collateral-quality premium** using a TradFi-style `beta` concept (systematic sensitivity vs Bitcoin as the
   benchmark).

The planned cadence for rate updates is biweekly, with protocol-governed parameters.

## Savings module and value distribution

DIBOR’s long-term plan includes a phased value distribution model centered around the Savings Module (`sdfUSD`):

- Phase 1: route 100% of borrowing interest revenue to the Savings Module to bootstrap adoption.
- Growth incentives: points programs / airdrops to incentivize non-yield-bearing dfUSD holders and increase PSM usage.
- Later: activate a governance “fee switch” to redirect a configurable portion of revenue to protocol-controlled
  buybacks.

## Multichain strategy

DIBOR’s multichain strategy goes beyond simple bridging by deploying canonical instances across selected L1/L2s with
chain-specific risk settings:

- Canonical deployments with native collateral per chain.
- More conservative parameters vs the primary deployment (lower debt ceilings, higher safety buffers).
- A chain-specific risk premium component in the interest rate model.
- Canonical mint/burn via a permissioned bridge inspired by Circle’s CCTP, including a 24‑hour cooldown buffer to
  quarantine potential bad debt and allow governance intervention if anomalies are detected.
- Circuit breakers such as per‑chain debt ceilings and emergency pausing to prevent cross-chain contagion.

## Go-to-market and partnerships (directional)

The long-term plan includes a distribution-heavy approach geared toward institutional and B2B channels:

- Potential distribution partners considered include large crypto lending desks (e.g. Galaxy) and institutional lenders (e.g. Nexo) acting as early/anchor users.
- Integration into lending desks as a distribution channel, potentially charging a distribution premium on top of the
  underlying protocol rate.
- Custody partners for non‑ERC20 collateral and optional participation in liquidation processes.
- Deal-flow partners for tokenized securities collateral (e.g. investment banks/advisors) to source issuers, large equity holders, and debt holders seeking lending facilities.
- A vetted network of liquidators (including TradFi participants) to support competitive auctions where applicable.
- Strategic partner incentives (e.g. token allocation, discounted strategic participation, liquidity mining).
- Examples of potential partner collateral mentioned in the plan include tokenized GLXY with an initial cap (e.g.
  $50M), subject to governance and risk review.

## Market rationale (summary)

The long-term plan is motivated by:

- Strong demand for BTC-collateralized borrowing across institutional and retail segments.
- Limited trust-minimized, composable options for BTC-backed borrowing in DeFi.
- The view that tokenized securities and custody-backed onchain representations can connect TradFi balance sheets and
  non‑EVM assets with DeFi-native risk and liquidity.
- A desire to avoid sudden, opaque governance-driven parameter shocks seen in some legacy CDP systems by making rate-setting more systematic and benchmark-anchored.

## How this maps to the current repository

This repository currently implements the onchain building blocks (token, PSM, savings vault, IRMs, ops tooling) that can
support the direction above.

The onchain ERC-20 contract implementing dfUSD in this repository is named `nUSD` (see `src/nUSD.sol`). Current
deployments and addresses are listed in `docs/gitbook/addresses.md`.
