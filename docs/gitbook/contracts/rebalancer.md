# Rebalancer

Source: `src/Rebalancer.sol`

`Rebalancer` is an optional utility that shifts debt between two Euler vault accounts so their health factors converge.
It is designed for accounts that:

- Share the same registered owner (via the EVC)
- Share the same debt asset / unit of account configuration

## How it works (high level)

Given two positions (`accountA` on `vaultA`, `accountB` on `vaultB`):

1. The contract computes each account’s health factor (`collateralValue / liabilityValue`).
2. It identifies the “risky” (lower health) and “safe” account.
3. It borrows from the safer account and repays the riskier account, moving `dfUSD` debt until health factors converge.
4. It charges a configurable fee (`feeBps`) capped by `maxFeeBps` provided by the caller/signer.

## Authorization modes

- `rebalance(...)`: callable only by the common owner.
- `rebalanceWithSig(...)`: callable by anyone, but requires an EIP‑712 authorization signed by the owner.
  - Owners can invalidate signatures by bumping a nonce (`invalidateNonce`).

## Governance controls

The contract is `Ownable` and the owner can set:

- `feeRecipient`
- `feeBps` (bounded by `MAX_FEE_BPS`)
