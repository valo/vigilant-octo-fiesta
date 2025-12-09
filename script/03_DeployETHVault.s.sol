// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {GenericFactory} from "euler-vault-kit/GenericFactory/GenericFactory.sol";
import {IEVault} from "euler-vault-kit/EVault/IEVault.sol";
import {HookTargetSynth} from "euler-vault-kit/Synths/HookTargetSynth.sol";
import {IRMStabilityFee} from "../src/IRMStabilityFee.sol";
import {
    OP_DEPOSIT, OP_MINT, OP_REDEEM, OP_SKIM, OP_REPAY_WITH_SHARES
} from "euler-vault-kit/EVault/shared/Constants.sol";
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
    address public nUSDVaultAddress;
    address public oracleRouterFactoryAddress;
    address public existingOracleRouter;
    address public ethUsdcChainlinkFeedAddress;

    function setUp() public virtual {
        factory = vm.envAddress("EVK_FACTORY_ADDRESS");
        unitOfAccount = vm.envAddress("USDC_ADDRESS");
        gnosisSafe = vm.envAddress("GNOSIS_SAFE_ADMIN");
        oracleRouterFactoryAddress = vm.envAddress("EULER_ROUTER_FACTORY_ADDRESS");
        existingOracleRouter = vm.envOr("EULER_ORACLE_ROUTER_ADDRESS", address(0));
        nUSDVaultAddress = vm.envAddress("NUSD_VAULT_ADDRESS");
        wethAddress = vm.envAddress("WETH_ADDRESS");
        usdcAddress = vm.envAddress("USDC_ADDRESS");
        ethUsdcChainlinkFeedAddress = vm.envAddress("ETH_USD_CHAINLINK_FEED_ADDRESS");
    }

    function run() external {
        vm.startBroadcast();

        address deployer = msg.sender;
        console2.log("Deployer:", deployer);
        console2.log("Using factory:", factory);
        console2.log("Unit of account (USDC):", unitOfAccount);
        console2.log("Gnosis Safe governor:", gnosisSafe);
        console2.log("Initial stability fee rate:", initialStabilityRate);

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

        bytes memory trailingData = abi.encodePacked(wethAddress, address(oracleRouter), unitOfAccount);
        console2.log("Proxy metadata:");
        console2.logBytes(trailingData);

        address vaultAddress = GenericFactory(factory).createProxy(address(0), true, trailingData);
        IEVault vault = IEVault(vaultAddress);
        console2.log("ETH Vault deployed at:", vaultAddress);

        // Allow all operations on the vault and disable the hook
        vault.setHookConfig(0x0, 0);

        // // Enable borrowing of nUSD against the ETH vault
        // IEVault nUSDVault = IEVault(nUSDVaultAddress);
        // nUSDVault.setLTV(vaultAddress, 800, 850, 30 minutes);

        vault.setGovernorAdmin(gnosisSafe);
        oracleRouter.transferGovernance(gnosisSafe);
        console2.log("Governor admin updated to:", gnosisSafe);

        vm.stopBroadcast();
    }

    // disable mint, redeem, skim and repayWithShares; restrict deposit to the synth contract
    // uint32 internal constant SYNTH_VAULT_HOOKED_OPS = OP_DEPOSIT | OP_MINT | OP_REDEEM | OP_SKIM | OP_REPAY_WITH_SHARES;
}
