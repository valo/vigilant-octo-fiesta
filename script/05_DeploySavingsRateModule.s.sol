// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SavingsRateModule} from "../src/SavingsRateModule.sol";
import {DeterministicCreate3Script} from "./DeploymentHelpers.s.sol";

/// @title DeploySavingsRateModule
/// @notice Deploys the SavingsRateModule via CREATE3 so the address is deterministic.
contract DeploySavingsRateModule is DeterministicCreate3Script {
    bytes32 internal constant DEFAULT_SALT =
        0x43f4600d98ae531d7e5f1f8ff68ef97779d31641007fc2d8ee0a7f68002fc6b3;

    address public asset;
    string public vaultName;
    string public vaultSymbol;
    uint256 public smearDuration;
    bytes32 public deploymentSalt;

    function setUp() public withCreateX {
        asset = vm.envAddress("SYNTH_ADDRESS");
        vaultName = vm.envOr("SAVINGS_RATE_NAME", string("nUSD Savings"));
        vaultSymbol = vm.envOr("SAVINGS_RATE_SYMBOL", string("nUSDS"));
        smearDuration = vm.envOr("SAVINGS_RATE_SMEAR_DURATION", uint256(0));
        deploymentSalt = resolveSalt("SAVINGS_RATE_DEPLOY_SALT", DEFAULT_SALT);
    }

    function run() external {
        vm.startBroadcast();

        address deployer = msg.sender;
        console2.log("Deployer:", deployer);
        console2.log("Savings asset:", asset);
        console2.log("Smear duration (s):", smearDuration);
        console2.log(string.concat("Vault name: ", vaultName));
        console2.log(string.concat("Vault symbol: ", vaultSymbol));

        bytes memory constructorArgs = abi.encode(IERC20(asset), vaultName, vaultSymbol, smearDuration);
        console2.log("Constructor arguments:");
        console2.logBytes(constructorArgs);
        bytes memory initCode = abi.encodePacked(type(SavingsRateModule).creationCode, constructorArgs);

        (address deployedAddress, address predictedAddress, bool freshlyDeployed) =
            deployDeterministic(deploymentSalt, initCode);
        console2.log("Predicted SavingsRateModule address:", predictedAddress);
        console2.log("Deployed SavingsRateModule at:", deployedAddress);
        console2.log("Deployment executed:", freshlyDeployed);

        SavingsRateModule srm = SavingsRateModule(deployedAddress);
        console2.log("Vault asset:", address(srm.asset()));
        console2.log("Vault name:", srm.name());
        console2.log("Vault symbol:", srm.symbol());

        vm.stopBroadcast();
    }
}
