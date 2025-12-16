# Savings Rate Module

Source: `src/SavingsRateModule.sol`

The Savings Rate Module (SRM) is an ERC‑4626 vault for a single ERC‑20 asset (intended to be `nUSD`). It implements a
“drip” mechanism where donated tokens are streamed to depositors at a constant rate over a configured duration.

## Key ideas

- Depositors receive shares (standard ERC‑4626).
- Donations (tokens transferred directly to the SRM) do not instantly increase `totalAssets()`.
- Instead, a `gulp()` call detects donated tokens and starts streaming them into `_totalAssetsStored` over
  `smearDuration`.

## Operational behavior

- `gulp()`:
  - Updates accrued drip (`_updateDrip()`)
  - Detects newly donated tokens (`balanceOf - _totalAssetsStored - undistributed`)
  - Increases `undistributed`, computes `dripRate`, and resets `lastDrip`
- `deposit/mint/withdraw/redeem`:
  - Call `_updateDrip()` first so users transact against up-to-date accounting

## Safety notes

- The SRM is not designed for fee-on-transfer or rebasing assets.
- Uses a lightweight reentrancy lock for public entrypoints.
