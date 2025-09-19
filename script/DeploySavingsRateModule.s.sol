// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {SavingsRateModule} from "../src/SavingsRateModule.sol";

/// @title DeploySavingsRateModule
/// @notice Deploys the SavingsRateModule via CREATE3 so the address is deterministic.
contract DeploySavingsRateModule is Script, CreateXScript {
    address public asset;
    string public vaultName;
    string public vaultSymbol;
    uint256 public smearDuration;

    function setUp() public withCreateX {
        asset = vm.envAddress("SYNTH_ADDRESS");
        vaultName = vm.envString("SAVINGS_RATE_NAME");
        vaultSymbol = vm.envString("SAVINGS_RATE_SYMBOL");
        smearDuration = vm.envUint("SAVINGS_RATE_SMEAR_DURATION");
    }

    function run() external {
        vm.startBroadcast();

        address deployer = msg.sender;
        console2.log("Deployer:", deployer);
        console2.log("Savings asset:", asset);
        console2.log("Smear duration (s):", smearDuration);

        bytes32 salt = 0x43f4600d98ae531d7e5f1f8ff68ef97779d31641007fc2d8ee0a7f68002fc6b3;
        bytes memory constructorArgs = abi.encode(IERC20(asset), vaultName, vaultSymbol, smearDuration);
        console2.log("Constructor arguments:");
        console2.logBytes(constructorArgs);
        bytes memory initCode = abi.encodePacked(type(SavingsRateModule).creationCode, constructorArgs);

        address computedAddress = computeCreate3Address(salt, deployer);
        address deployedAddress = create3(salt, initCode);

        require(computedAddress == deployedAddress, "CREATE3 address mismatch");
        console2.log("Deployed SavingsRateModule at:", deployedAddress);

        SavingsRateModule srm = SavingsRateModule(deployedAddress);
        console2.log("Vault asset:", address(srm.asset()));
        console2.log("Vault name:", srm.name());
        console2.log("Vault symbol:", srm.symbol());

        vm.stopBroadcast();
    }
}
