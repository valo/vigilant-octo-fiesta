// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {IRMDependentVaults} from "../src/IRMDependentVaults.sol";

/// @title DeployDependentIRM
/// @notice Deploys IRMDependentVaults and wires ETH/WBTC vaults with configured rates.
contract DeployDependentIRM is Script {
    address public gnosisSafe;
    address public ethVault;
    address public wbtcVault;
    address public synthVault;
    uint256 public ethAprBps;
    uint256 public wbtcAprBps;

    function setUp() public virtual {
        gnosisSafe = vm.envAddress("GNOSIS_SAFE_ADMIN");
        ethVault = vm.envAddress("ETH_VAULT_ADDRESS");
        wbtcVault = vm.envAddress("WBTC_VAULT_ADDRESS");
        synthVault = vm.envAddress("NUSD_VAULT_ADDRESS");
        ethAprBps = vm.envUint("ETH_IRM_APR_BPS");
        wbtcAprBps = vm.envUint("WBTC_IRM_APR_BPS");
    }

    function run() external {
        vm.startBroadcast();

        console2.log("Deploying IRMDependentVaults");
        console2.log("Gnosis Safe governor:", gnosisSafe);
        console2.log("ETH vault:", ethVault);
        console2.log("WBTC vault:", wbtcVault);
        console2.log("ETH APR (bps):", ethAprBps);
        console2.log("WBTC APR (bps):", wbtcAprBps);

        IRMDependentVaults irm = new IRMDependentVaults();

        uint256 ethRate = _aprBpsToSpy(ethAprBps);
        uint256 wbtcRate = _aprBpsToSpy(wbtcAprBps);

        irm.addDependentVault(ethVault, ethRate);
        irm.addDependentVault(wbtcVault, wbtcRate);

        console2.log("IRM deployed at:", address(irm));
        console2.log("ETH vault rate (SPY):", ethRate);
        console2.log("WBTC vault rate (SPY):", wbtcRate);

        irm.transferOwnership(gnosisSafe);
        console2.log("Ownership transferred to:", gnosisSafe);

        console2.log("Propose IRM update on synth vault via Safe:");
        console2.log("pnpm --dir ops run propose:irm", synthVault, address(irm));

        vm.stopBroadcast();
    }

    /// @notice Convert an APR in basis points to a per-second SPY (1e27) rate.
    function _aprBpsToSpy(uint256 aprBps) internal pure returns (uint256) {
        // APR (bps) -> APY wad -> per-second wad -> ray (SPY)
        uint256 apyWad = aprBps * 1e14; // bps -> wad
        uint256 ratePerSecondWad = apyWad / 365 days;
        return ratePerSecondWad * 1e9;
    }
}
