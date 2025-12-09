// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {GenericFactory} from "euler-vault-kit/GenericFactory/GenericFactory.sol";
import {IEVault} from "euler-vault-kit/EVault/IEVault.sol";
import {EulerRouterFactory} from "evk-periphery/EulerRouterFactory/EulerRouterFactory.sol";
import {EulerRouter} from "euler-price-oracle/EulerRouter.sol";
import {ChainlinkOracle} from "euler-price-oracle/adapter/chainlink/ChainlinkOracle.sol";

/// @title DeployWBTCVault
/// @notice Deploys a WBTC EVault with a Chainlink BTC/USD oracle for collateral use only.
contract DeployWBTCVault is Script {
    address public factory;
    address public unitOfAccount;
    address public gnosisSafe;
    address public wbtcAddress;
    address public usdcAddress;
    address public oracleRouterFactoryAddress;
    address public existingOracleRouter;
    address public btcUsdChainlinkFeedAddress;

    function setUp() public virtual {
        factory = vm.envAddress("EVK_FACTORY_ADDRESS");
        unitOfAccount = vm.envAddress("USDC_ADDRESS");
        gnosisSafe = vm.envAddress("GNOSIS_SAFE_ADMIN");
        oracleRouterFactoryAddress = vm.envAddress("EULER_ROUTER_FACTORY_ADDRESS");
        existingOracleRouter = vm.envOr("EULER_ORACLE_ROUTER_ADDRESS", address(0));
        wbtcAddress = vm.envAddress("WBTC_ADDRESS");
        usdcAddress = vm.envAddress("USDC_ADDRESS");
        btcUsdChainlinkFeedAddress = vm.envAddress("BTC_USD_CHAINLINK_FEED_ADDRESS");
    }

    function run() external {
        vm.startBroadcast();

        address deployer = msg.sender;
        console2.log("Deployer:", deployer);
        console2.log("Using factory:", factory);
        console2.log("Unit of account (USDC):", unitOfAccount);
        console2.log("Gnosis Safe governor:", gnosisSafe);
        console2.log("WBTC asset:", wbtcAddress);
        console2.log("BTC/USD Chainlink feed:", btcUsdChainlinkFeedAddress);

        EulerRouter oracleRouter;
        if (existingOracleRouter != address(0)) {
            oracleRouter = EulerRouter(existingOracleRouter);
            console2.log("Reusing EulerRouter:", address(oracleRouter));
        } else {
            EulerRouterFactory oracleRouterFactory = EulerRouterFactory(oracleRouterFactoryAddress);
            oracleRouter = EulerRouter(oracleRouterFactory.deploy(deployer));
            console2.log("Deployed EulerRouter:", address(oracleRouter));
        }

        ChainlinkOracle priceOracle =
            new ChainlinkOracle(wbtcAddress, usdcAddress, btcUsdChainlinkFeedAddress, 60 minutes);
        console2.log("Deployed ChainlinkOracle for BTC/USDC:", address(priceOracle));
        oracleRouter.govSetConfig(wbtcAddress, usdcAddress, address(priceOracle));

        console2.log("Current price of BTC in USDC:", oracleRouter.getQuote(1e8, wbtcAddress, usdcAddress) / 1e6);

        bytes memory trailingData = abi.encodePacked(wbtcAddress, address(oracleRouter), unitOfAccount);
        console2.log("Proxy metadata:");
        console2.logBytes(trailingData);

        address vaultAddress = GenericFactory(factory).createProxy(address(0), true, trailingData);
        IEVault vault = IEVault(vaultAddress);
        console2.log("WBTC Vault deployed at:", vaultAddress);

        // Allow all operations on the vault and disable the hook
        vault.setHookConfig(address(0x0), 0);

        vault.setGovernorAdmin(gnosisSafe);
        oracleRouter.transferGovernance(gnosisSafe);
        console2.log("Governor admin updated to:", gnosisSafe);

        console2.log("Run ops script to propose LTV on nUSD vault via Safe:");
        console2.log("pnpm --dir ops run propose:ltv --", vaultAddress, "800 850 1800");

        vm.stopBroadcast();
    }
}
