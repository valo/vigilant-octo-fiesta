# Peg Stability Module (PSM)

Source: `src/PegStabilityModule.sol` and `src/PegStabilityModuleYield.sol`

The Peg Stability Module provides a simple swap interface between `dfUSD` and an underlying token (typically USDC),
charging configurable fees in basis points.

## Core parameters

- `synth`: `dfUSD` token address (immutable)
- `underlying`: swap backing asset (immutable)
- `CONVERSION_PRICE`: price of 1 `dfUSD` denominated in underlying, scaled to `1e18` (immutable)
- `toUnderlyingFeeBPS`: fee for `dfUSD → underlying`
- `toSynthFeeBPS`: fee for `underlying → dfUSD`
- `feeRecipient`: receiver for collected fees

The PSM uses integer math with explicit rounding choices to make swap quotes deterministic.

## Swap functions

- `swapToSynthGivenIn(amountInUnderlying, receiver) -> amountOutSynth`
- `swapToSynthGivenOut(amountOutSynth, receiver) -> amountInUnderlying`
- `swapToUnderlyingGivenIn(amountInSynth, receiver) -> amountOutUnderlying`
- `swapToUnderlyingGivenOut(amountOutUnderlying, receiver) -> amountInSynth`

### `underlying → dfUSD`

On `swapToSynth...`, the PSM:

1. Pulls `underlying` from the caller
2. Keeps the “minted underlying” portion as reserves
3. Sends the remainder to `feeRecipient`
4. Calls `mint(receiver, amountOutSynth)` on the dfUSD token contract (`nUSD`)

This requires the PSM to have been granted the dfUSD token contract's `MINTER_ROLE` and sufficient minting `capacity`.

### `dfUSD → underlying`

On `swapToUnderlying...`, the PSM:

1. Calls `burn(caller, amountInSynth)` on the dfUSD token contract (`nUSD`)
2. Decreases its accounted reserves by the amount leaving the module
3. Transfers `underlying` to `receiver` and fee to `feeRecipient`

## Reserves oracle (TWAR)

The PSM maintains an internal notion of “accounted reserves” and a ring buffer of observations:

- `accountedReserves`: tracked reserves in underlying units (not derived from `balanceOf()`).
- `reserveCumulative`: cumulative sum of `accountedReserves * time` used for TWAR calculations.
- `observe(secondsAgo)` / `getAverageReserves(secondsAgo)`: Uniswap-style time-weighted observations.

An owner can call `syncReserves()` to reconcile `accountedReserves` with the actual token balance (for donations or
manual transfers).

## Yield variant: `PegStabilityModuleYield`

`PegStabilityModuleYield` extends the base PSM to stake excess underlying into a yield vault with cooldown withdrawals:

- `liquidTarget`: target amount of underlying to keep liquid for redemptions
- `stakeExcess()`: deposits balance above `liquidTarget` into `stakingVault`
- `startUnstake(assets)` / `finalizeUnstake()`: manage cooldown and withdrawals

This variant is intended for underlying assets like staked USDe with a cooldown-based unstake flow.

## Roadmap notes

The long-term plan describes a PSM where users deposit USDe to access the Savings Module and where the PSM reserve coverage ratio feeds into the borrowing rate. Current deployments in this repo are configured via `.env` and described in `docs/gitbook/addresses.md`.

