# `nUSD`

Source: `src/nUSD.sol`

`nUSD` is the protocol’s synthetic USD token. It is an `ERC20` with role-based controls (`AccessControl`) and a “minting
capacity” system per minter.

## Roles

- `DEFAULT_ADMIN_ROLE`: can set minter capacities, set DSR vault, set interest fee, and manage ignored supply accounts.
- `MINTER_ROLE`: can call `mint(...)` subject to `capacity`.
- `ALLOCATOR_ROLE`: can allocate/deallocate `nUSD` into ERC‑4626 vaults owned by the `nUSD` contract.
- `KEEPER_ROLE`: can deposit accrued interest into the Savings Rate Module (DSR vault).

## Minting and capacity

Each minter address has:

- `capacity`: maximum allowed minted amount
- `minted`: current outstanding minted balance attributable to that minter

`mint(...)` increases `minted`; `burn(...)` decreases it (down to zero).

This enables governance to grant “unlimited” minting to a module (e.g. the PSM) while preserving the ability to cap or
remove minters.

## Allocations to ERC‑4626 vaults

`allocate(vault, amount)` deposits `nUSD` owned by the `nUSD` contract into an ERC‑4626 vault. This supports protocol
treasury strategies where `nUSD` is deployed into yield sources.

To avoid inflating circulating supply metrics, allocated vault addresses can be excluded from `totalSupply()` via the
“ignored for total supply” set.

## Savings Rate Module integration

`nUSD` can be configured with a `dsrVault` (a `SavingsRateModule` instance). A keeper can withdraw accrued interest from
an allocated ERC‑4626 vault and stream it into the savings vault via `depositInterestInDSR(...)`.

Operationally, this call:

1. Withdraws interest from an ERC‑4626 vault back to `nUSD`
2. Splits interest into `fee` + `netInterest`
3. Transfers `netInterest` into `dsrVault` and calls `gulp()` (starts/updates streaming)
4. Transfers `fee` to a `feesReceiver`
