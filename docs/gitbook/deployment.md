# Deployment

This repository uses Foundry scripts (`script/`) for deployments and an `ops/` TypeScript workspace for governance
proposal preparation.

## Networks

- Scripts are parameterized via `.env` / `.env.sepolia` style files.
- Broadcast traces are written to `broadcast/`.

## Deterministic deployments (CREATE3)

The following deployments are performed via CREATE3 using `createx-forge` helpers:

- `nUSD` token: `script/01_DeploySyntheticUsd.s.sol`
- PSM: `script/04_DeployPSM.s.sol`
- Savings Rate Module: `script/05_DeploySavingsRateModule.s.sol`

These scripts compute a predicted address before deploying and will reuse an existing deployment if code is already
present at the predicted address.

## EVK vault deployments

EVaults are deployed through EVK’s `GenericFactory`:

- `nUSD` vault: `script/02_DeploySynthEVault.s.sol`
- WETH vault: `script/03_DeployETHVault.s.sol`
- WBTC vault: `script/06_DeployWBTCVault.s.sol`

The scripts also configure:

- Oracle router (`EulerRouter`) and adapters (Chainlink / FixedRate)
- `GovernorAdmin` on the vault and governance on the oracle router
- IRM on the `nUSD` vault (`IRMStabilityFee` initially)

## Post-deploy governance wiring (required)

After deployment, governance typically performs:

- Grant PSM permission to mint `nUSD`:
  - `nUSD.grantRole(MINTER_ROLE, psm)`
  - `nUSD.setCapacity(psm, type(uint128).max)` (or a chosen cap)
- Enable collateral vaults on the `nUSD` vault via `ops/src/propose-synth-collateral.ts`
- (Optional) Set the `dsrVault` on `nUSD` to point to the Savings Rate Module

## Local development

- Build: `forge build`
- Test: `forge test`
- Format: `forge fmt`

For governance scripts:

- Install: `pnpm --dir ops install`
- Run a proposal script: `pnpm --dir ops run <script> -- ...`
