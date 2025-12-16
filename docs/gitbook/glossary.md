# Glossary

## CDP
Collateralized debt position: a position where a user deposits collateral and borrows a debt asset against it.

## dfUSD
DIBOR’s synthetic USD stablecoin. In this repository, the onchain ERC-20 contract implementing dfUSD is named `nUSD`.

## sdfUSD
The staked/savings representation of dfUSD (dfUSD deposited into the Savings Module). In this repository, this role is
implemented by the Savings Rate Module (an ERC-4626 vault for dfUSD) where users receive ERC-4626 shares.

## EVK / EVault
Euler Vault Kit is the lending stack used by this repo. An `EVault` is an ERC‑4626-like vault that supports lending and
borrowing with risk configuration.

## EVC
Ethereum Vault Connector: the account and execution layer used by EVK to coordinate operations across multiple vaults.

## IRM
Interest Rate Model: a contract that computes a borrow rate for a vault.

## PSM
Peg Stability Module: a swap module that exchanges `dfUSD` with an underlying asset at a configured conversion price and
fees.

## SRM / Savings Rate Module
An ERC‑4626 vault that drips donated tokens to depositors over time.

## TWAR
Time‑weighted average reserves: an oracle pattern computing the average reserve level over a lookback window.
