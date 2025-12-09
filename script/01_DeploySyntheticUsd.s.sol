// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import {nUSD} from "../src/nUSD.sol";
import {DeterministicCreate3Script} from "./DeploymentHelpers.s.sol";

/// @title DeploySyntheticUsd
/// @notice Deploys the nUSD synth deterministically using CREATE3 with a Gnosis Safe owner.
contract DeploySyntheticUsd is DeterministicCreate3Script {
    bytes32 internal constant DEFAULT_SALT =
        0x43f4600d98ae531d7e5f1f8ff68ef97779d3164100187164606b5864019587be;

    address public defaultOwner;
    bytes32 public deploymentSalt;
    string public synthName;
    string public synthSymbol;

    function setUp() public withCreateX {
        defaultOwner = vm.envAddress("GNOSIS_SAFE_ADMIN");
        deploymentSalt = resolveSalt("SYNTH_DEPLOY_SALT", DEFAULT_SALT);
        synthName = vm.envOr("SYNTH_NAME", string("nUSD"));
        synthSymbol = vm.envOr("SYNTH_SYMBOL", string("nUSD"));
    }

    function run() external {
        vm.startBroadcast();

        console2.log("Deployer:", msg.sender);
        console2.log("Owner (Gnosis Safe):", defaultOwner);
        console2.log(string.concat("Token name: ", synthName));
        console2.log(string.concat("Token symbol: ", synthSymbol));

        bytes memory initCode =
            abi.encodePacked(type(nUSD).creationCode, abi.encode(defaultOwner, synthName, synthSymbol));

        (address deployedAddress, address predictedAddress, bool freshlyDeployed) =
            deployDeterministic(deploymentSalt, initCode);

        console2.log("nUSD address (predicted):", predictedAddress);
        console2.log("nUSD address (deployed):", deployedAddress);
        console2.log("Deployment executed:", freshlyDeployed);

        vm.stopBroadcast();
    }
}
