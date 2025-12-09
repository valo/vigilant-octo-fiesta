// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";

/// @notice Shared helpers for CREATE3 deployments used by deterministic scripts.
abstract contract DeterministicCreate3Script is Script, CreateXScript {
    /// @dev Reads a salt from the env var `envVar` or falls back to `defaultSalt`.
    function resolveSalt(string memory envVar, bytes32 defaultSalt) internal returns (bytes32 salt) {
        salt = bytes32(vm.envOr(envVar, uint256(defaultSalt)));
        console2.log(envVar);
        console2.logBytes32(salt);
    }

    /// @dev Deploys `initCode` via CREATE3, optionally reusing an existing deployment at the predicted address.
    function deployDeterministic(bytes32 salt, bytes memory initCode)
        internal
        returns (address deployed, address predicted, bool freshlyDeployed)
    {
        address deployer = msg.sender;
        predicted = computeCreate3Address(salt, deployer);
        console2.log("Predicted CREATE3 address:", predicted);

        if (predicted.code.length == 0) {
            freshlyDeployed = true;
            deployed = create3(salt, initCode);
            console2.log("Deployed via CREATE3:", deployed);
        } else {
            deployed = predicted;
            console2.log("Existing deployment detected, skipping CREATE3:", deployed);
        }

        require(predicted == deployed, "CREATE3 address mismatch");
    }
}
