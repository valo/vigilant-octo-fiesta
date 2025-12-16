# Governance & Ops

Governance in this repository is designed around a Gnosis Safe that acts as:

- The admin for protocol-owned contracts (e.g. `dfUSD` admin role, PSM owner)
- The governor/admin for EVK vaults
- The governor for the Euler oracle router (`EulerRouter`)

## Safe-based operations

The `ops/` directory contains TypeScript scripts that prepare Safe proposals (they do not execute them directly). These
scripts read configuration from environment variables and create a Safe transaction bundle.

Common actions:

- **Enable collateral on the `dfUSD` vault + configure oracles**
  - Script: `ops/src/propose-synth-collateral.ts`
  - Actions:
    - `EVault.setLTV(collateralVault, borrowLtvBps, liquidationLtvBps, rampDuration)`
    - `EulerRouter.govSetConfig(collateralAsset, unitOfAccount, priceOracle)`
    - `EulerRouter.govSetResolvedVault(collateralVault, true)`
- **Update PSM fees**
  - Script: `ops/src/propose-psm-fees.ts`
  - Action: `PegStabilityModule.setFees(toUnderlyingFeeBps, toSynthFeeBps)`
- **Update an EVault IRM**
  - Script: `ops/src/propose-irm.ts`
  - Action: `EVault.setInterestRateModel(irm)`
- **Grant keeper role on `dfUSD`**
  - Script: `ops/src/propose-synth-keeper.ts`
  - Action: `dfUSD.grantRole(KEEPER_ROLE, keeper)`

## Environment variables

The `ops/` scripts expect (at minimum):

- `CHAIN_ID`, `SAFE_ADDRESS` (in `ops/.env`)
- Contract addresses such as `NUSD_VAULT_ADDRESS` / `SYNTH_ADDRESS` (usually from repo root `.env`)

See `docs/gitbook/deployment.md` for the deployment-time configuration keys.

## Deployment traces

Foundry broadcast artifacts are stored under `broadcast/` and provide an audit trail of deployments and configuration
transactions for each script run.
