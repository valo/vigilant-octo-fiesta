# Glossary

## CDP
Collateralized debt position: a position where a user deposits collateral and borrows a debt asset against it.

## EVK / EVault
Euler Vault Kit is the lending stack used by this repo. An `EVault` is an ERC‑4626-like vault that supports lending and
borrowing with risk configuration.

## EVC
Ethereum Vault Connector: the account and execution layer used by EVK to coordinate operations across multiple vaults.

## IRM
Interest Rate Model: a contract that computes a borrow rate for a vault.

## PSM
Peg Stability Module: a swap module that exchanges `nUSD` with an underlying asset at a configured conversion price and
fees.

## SRM / Savings Rate Module
An ERC‑4626 vault that drips donated tokens to depositors over time.

## TWAR
Time‑weighted average reserves: an oracle pattern computing the average reserve level over a lookback window.
