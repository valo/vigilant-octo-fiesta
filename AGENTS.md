# Repository Guidelines

This repository implements the DIBOR protocol with Foundry. Follow the rules below to keep deployments auditable and repeatable.

## Project Structure & Module Organization
- `src/` holds production Solidity (e.g. `nUSD.sol`, modules, `interfaces/` for shared types); keep upgradeable patterns there.
- `test/` stores Forge suites (`*.t.sol`) and `test/mocks/` fixtures.
- `script/` carries Forge deploy scripts; `broadcast/` preserves transaction traces.
- `ops/` hosts TypeScript Safe automation; treat it as the source for governance proposals.
- `docs/` (including `DESIGN.md`) records rationale; update when behaviour or architecture shifts.
- `lib/` contains vendored dependencies managed by Foundry.

All the solidity dependencies are included as git submodules and no changes should be made in them.

## Build, Test & Development Commands
- `forge build` compiles with solc 0.8.25 and verifies remappings.
- `forge test` runs the suite; add `--match-contract PegStabilityModule` for focused runs.
- `forge snapshot` refreshes gas baselines before merging stateful changes.
- `forge fmt` enforces 4-space indentation, SPDX headers, and import ordering.
- `anvil` launches a local testnet.
- `pnpm --dir ops install` boots the ops workspace; `pnpm --dir ops run propose:psm-fees` prepares a Safe proposal (requires `.env`).

## Coding Style & Naming Conventions
Stick to Solidity 0.8.25 defaults: contracts and libraries `CamelCase`, interfaces prefixed with `I`, storage vars `lowerCamelCase`, constants `ALL_CAPS`. Constructors must receive explicit admin addresses and delegate state setup to initializer functions. Prefer NatSpec for external functions and document non-obvious invariants. Run `forge fmt` before committing.

## Testing Guidelines
Place tests next to the target contract using the `ContractScenario.t.sol` naming pattern and lean on `forge-std` cheatcodes for setup. Cover revert paths and access control edges. Run `forge test --gas-report` to surface regressions and include key numbers in PRs. When touching `ops/`, dry-run scripts against Anvil and guard secrets via environment variables.

## Commit & Pull Request Guidelines
Repository history uses concise sentence-case subjects (e.g. `Add granular access control`); keep commits atomic and reference issues or safe txn IDs in the body when relevant. PRs should summarise functional impact, note storage layout or access-control changes, attach gas snapshots, and call out any required config updates. Request a security review whenever upgrade flow or multisig handling changes.

## Security & Ops Notes
Populate `SEPOLIA_RPC_URL` and `ETHERSCAN_API_KEY` in your shell or `.env`; Foundry reads them from `foundry.toml`. Never commit private keys or Safe signatures. For emergency runbooks or post-mortems, update `docs/` and retain associated `broadcast/` artifacts for traceability.
