# Contract Addresses

This page centralizes protocol addresses by network.

The source of truth for testnet addresses in this repo is the environment configuration (`.env`, `.env.sepolia`) and the
Foundry broadcast artifacts (`broadcast/`).

## Sepolia (11155111)

### Governance

| Name | Env var | Address |
| --- | --- | --- |
| Gnosis Safe (admin/governor) | `GNOSIS_SAFE_ADMIN` | `0x693e444389F3cB953F8baD0EaC2CE2885df68De7` |

### Core protocol

| Name | Env var | Address |
| --- | --- | --- |
| `dfUSD` token | `SYNTH_ADDRESS` | `0xE59Fa551812209Ba9F78B536cB491343c4D4ceA3` |
| Peg Stability Module | `PSM_ADDRESS` | `0x47669519Dd036235480e94D495a1BD6F2A614dBA` |
| `dfUSD` EVault (debt vault) | `NUSD_VAULT_ADDRESS` | `0xA4947e33c94dC69943Fa86B1276a04966956B728` |

### Collateral vaults

| Asset | Env var | Address |
| --- | --- | --- |
| WETH EVault | `ETH_VAULT_ADDRESS` | `0x1B08a62B189D7e9813Ef456055f12c1E98E7b22D` |
| WBTC EVault | `WBTC_VAULT_ADDRESS` | `0x1820bD3Bed4E70cd9052DDCd6BE07eC249CE39e4` |

### External dependencies

| Name | Env var | Address |
| --- | --- | --- |
| USDC | `USDC_ADDRESS` | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` |
| WETH | `WETH_ADDRESS` | `0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14` |
| WBTC | `WBTC_ADDRESS` | `0x29f2D40B0605204364af54EC677bD022dA425d03` |
| EVK `GenericFactory` | `EVK_FACTORY_ADDRESS` | `0xEB07789D76392302dc9181Aca1e07836F9257B5a` |
| Oracle router factory | `EULER_ROUTER_FACTORY_ADDRESS` | `0xa01f7d87cD7e96294C6F9934aB3f8294037F275c` |
| Chainlink ETH/USD feed | `ETH_USD_CHAINLINK_FEED_ADDRESS` | `0x694AA1769357215DE4FAC081bf1f309aDC325306` |
| Chainlink BTC/USD feed | `BTC_USD_CHAINLINK_FEED_ADDRESS` | `0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43` |

## Adding more networks

For each network, include:

- Chain ID and block explorer
- Addresses for core protocol contracts
- Addresses for collateral vaults + oracle configuration
- Governance addresses (Safe, timelock/module if applicable)
