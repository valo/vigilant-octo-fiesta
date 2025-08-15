# DESIGN

This document captures the high-level design philosophy and architecture decisions for the CDP Protocol project.

## Deployment Strategy

The deployment workflow for the main contracts is as follows:

- Contracts are deployed using the OpenZeppelin transparent proxy pattern for upgradeability.
- Each proxy is managed by a central `ProxyAdmin` contract.
- The `ProxyAdmin` contract is owned by a Gnosis Safe multisig (the "ProxyAdmin Safe").
- Deployments are orchestrated through a Factory contract owned by the main Gnosis Safe (the "Main Safe").
- When a new deployment is required:
  1. Deployment steps (proxy creation, implementation initialization, etc.) are scheduled as transactions in the Main Safe.
  2. Safe signers review, sign, and execute the transactions atomically.

## Considerations and Open Questions

- Upgrade management: What process and guardrails do we put in place for future upgrades (e.g. timelocks, multisig modules)?
- Operational procedures: How do Safe signers handle testnet vs mainnet deployments and CI/CD integration?
- Verification: Contract verification on block explorers (Etherscan, etc.).
- Security: Emergency recovery, freeze mechanisms, and key rotation strategies.
- Gas optimization: Batching transactions, gas limit considerations.

## Development Guidelines

- **Explicit owner parameter**: Contracts should not implicitly set the owner to `msg.sender`. Instead, the owner address must be passed explicitly as a constructor or initializer parameter.
- **Proxy-friendly initialization**: Avoid putting initialization logic in constructors. All upgradeable contracts must expose a dedicated `initialize(...)` function for state setup, following the OpenZeppelin initializer pattern.
