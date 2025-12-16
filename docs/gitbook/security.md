# Security

This page captures current security-relevant notes and known limitations for the initial draft.

## Trust and permissions

- `nUSD` uses `AccessControl`. A privileged admin can:
  - Add/remove minters and set minting caps
  - Configure the Savings Rate Module address and interest fee
- The PSM is `Ownable` and the owner can:
  - Change fees and fee recipient
  - Call `syncReserves()` (reconciles oracle reserves to actual balance)
- EVK vaults are governed by a `GovernorAdmin` (intended to be a Gnosis Safe).

## Oracle assumptions

- Vault pricing depends on the configured `EulerRouter` oracle router and its adapters.
- Deploy scripts configure Chainlink adapters for ETH/USD and BTC/USD, plus a fixed rate oracle for `nUSD/USDC` (testnet).

## Known draft gaps

- No formal threat model documented yet.
- No documented emergency actions (pause/freeze) in this repo’s protocol-owned contracts.
- Upgradeability/immutability policy should be clarified (some contracts are deployed deterministically, not proxied).

## Reporting

The `nUSD` contract includes a `@custom:security-contact` tag. For repository-level security processes, align with the
Euler security program as applicable.
