# Interest Rate Models (IRMs)

This repository includes two IRM implementations for EVK vaults.

## `IRMStabilityFee`

Source: `src/IRMStabilityFee.sol`

A fixed interest rate model intended to represent a “stability fee”. It returns a constant `currentRate` (per-second,
ray/`1e27` scale as expected by EVK) and is updateable by its `owner`.

This IRM enforces EVK’s `IIRM` rule that `computeInterestRate(...)` can only be called by the vault itself.

## `IRMDependentVaults`

Source: `src/IRMDependentVaults.sol`

Computes the calling vault’s rate as a weighted average of a set of “dependent vault” rates.

Weighting:

- Each dependent vault contributes proportionally to the USD value of its `totalAssets()`, using the calling vault’s
  oracle and unit of account.
- The final rate is `weightedSum(value * rate) / totalValue`.

Operationally, this supports policies like: “set `nUSD`’s borrow rate based on the value‑weighted mix of collateral
vaults”.
