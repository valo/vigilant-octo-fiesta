// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {GenericFactory} from "euler-vault-kit/GenericFactory/GenericFactory.sol";
import {IEVault} from "euler-vault-kit/EVault/IEVault.sol";
import {IRMStabilityFee} from "../src/IRMStabilityFee.sol";
import {EulerRouterFactory} from "evk-periphery/EulerRouterFactory/EulerRouterFactory.sol";
import {EulerRouter} from "euler-price-oracle/EulerRouter.sol";
import {ChainlinkOracle} from "euler-price-oracle/adapter/chainlink/ChainlinkOracle.sol";
import {FixedRateOracle} from "euler-price-oracle/adapter/fixed/FixedRateOracle.sol";

/// @title DeploySynthEVault
/// @notice Deploys and configures an EVault for the nUSD synth with a HookTargetSynth gate and stability fee IRM.
contract DeploySynthEVault is Script {
    address public factory;
    address public synthAsset;
    address public unitOfAccount;
    address public gnosisSafe;
    address public wethAddress;
    address public usdcAddress;
    uint256 public initialStabilityRate;
    // address public existingHookTarget;
    address public oracleRouterFactoryAddress;
    address public existingOracleRouter;
    address public ethUsdcChainlinkFeedAddress;

    function setUp() public virtual {
        factory = vm.envAddress("EVK_FACTORY_ADDRESS");
        synthAsset = vm.envAddress("SYNTH_ADDRESS");
        unitOfAccount = vm.envAddress("USDC_ADDRESS");
        gnosisSafe = vm.envAddress("GNOSIS_SAFE_ADMIN");
        oracleRouterFactoryAddress = vm.envAddress("EULER_ROUTER_FACTORY_ADDRESS");
        initialStabilityRate = vm.envUint("STABILITY_FEE_RATE"); // in basis points, e.g. 400 = 4% APR
        // existingHookTarget = vm.envOr("HOOK_TARGET_SYNTH_ADDRESS", address(0));
        existingOracleRouter = vm.envOr("EULER_ORACLE_ROUTER_ADDRESS", address(0));
        wethAddress = vm.envAddress("WETH_ADDRESS");
        usdcAddress = vm.envAddress("USDC_ADDRESS");
        ethUsdcChainlinkFeedAddress = vm.envAddress("ETH_USD_CHAINLINK_FEED_ADDRESS");
    }

    function run() external {
        vm.startBroadcast();

        address deployer = msg.sender;
        console2.log("Deployer:", deployer);
        console2.log("Using factory:", factory);
        console2.log("nUSD asset:", synthAsset);
        console2.log("Unit of account (USDC):", unitOfAccount);
        console2.log("Gnosis Safe governor:", gnosisSafe);
        console2.log("Initial stability fee rate:", initialStabilityRate);
        require(initialStabilityRate > 0, "STABILITY_FEE_RATE not set");

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
            new ChainlinkOracle(wethAddress, usdcAddress, ethUsdcChainlinkFeedAddress, 60 minutes);
        console2.log("Deployed ChainlinkOracle for ETH/USDC:", address(priceOracle));
        oracleRouter.govSetConfig(wethAddress, usdcAddress, address(priceOracle));

        console2.log("Current price of ETH in USDC:", oracleRouter.getQuote(1 ether, wethAddress, usdcAddress) / 1e6);

        // Add a Synth/USDC oracle to the EulerRouter
        FixedRateOracle synthUsdcOracle = new FixedRateOracle(synthAsset, usdcAddress, 1e6); // 1 nUSD = 1 USDC
        console2.log("Deployed FixedRateOracle for nUSD/USDC:", address(synthUsdcOracle));
        oracleRouter.govSetConfig(synthAsset, usdcAddress, address(synthUsdcOracle));

        // Add a ETH/synth oracle to the EulerRouter
        ChainlinkOracle ethSynthOracle =
            new ChainlinkOracle(wethAddress, synthAsset, ethUsdcChainlinkFeedAddress, 60 minutes);
        console2.log("Deployed ChainlinkOracle for ETH/nUSD:", address(ethSynthOracle));
        oracleRouter.govSetConfig(wethAddress, synthAsset, address(ethSynthOracle));

        console2.log("Current price of nUSD in USDC:", oracleRouter.getQuote(1e18, synthAsset, usdcAddress) / 1e6);
        console2.log("Current price of nUSD in ETH:", oracleRouter.getQuote(1e18, wethAddress, synthAsset) / 1e18);

        // Convert APR in basis points to per-second rate in ray (1e27)
        // formula: (1 + apr/10000)^(1/seconds_per_year)
        uint256 secondsPerYear = 365 days;
        uint256 apyWad = initialStabilityRate * 1e14; // bps -> 1e18 (APY)
        uint256 ratePerSecondWad = apyWad / secondsPerYear; // simple per-second rate
        uint256 ratePerSecondRay = ratePerSecondWad * 1e9; // WAD -> RAY
        console2.log("Initial stability fee rate per second in ray:", ratePerSecondRay);
        IRMStabilityFee irm = new IRMStabilityFee(ratePerSecondRay);
        console2.log("IRMStabilityFee deployed at:", address(irm));

        bytes memory trailingData = abi.encodePacked(synthAsset, address(oracleRouter), unitOfAccount);
        console2.log("Proxy metadata:");
        console2.logBytes(trailingData);

        address vaultAddress = GenericFactory(factory).createProxy(address(0), true, trailingData);
        IEVault vault = IEVault(vaultAddress);
        console2.log("EVault deployed at:", vaultAddress);

        vault.setInterestRateModel(address(irm));
        console2.log("Set IRM on vault:", address(irm));

        // HookTargetSynth hookTarget;
        // if (existingHookTarget != address(0)) {
        //     hookTarget = HookTargetSynth(existingHookTarget);
        //     console2.log("Reusing HookTargetSynth:", address(hookTarget));
        // } else {
        //     hookTarget = new HookTargetSynth();
        //     console2.log("Deployed HookTargetSynth:", address(hookTarget));
        // }

        // vault.setHookConfig(address(hookTarget), SYNTH_VAULT_HOOKED_OPS);
        // console2.log("Hook config ops:", uint256(SYNTH_VAULT_HOOKED_OPS));

        vault.setGovernorAdmin(gnosisSafe);
        oracleRouter.transferGovernance(gnosisSafe);
        irm.transferOwnership(gnosisSafe);
        console2.log("Governor admin updated to:", gnosisSafe);

        vm.stopBroadcast();
    }
}
