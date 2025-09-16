// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import {nUSD} from "../src/nUSD.sol";

/// @title DeploySynteticUSD
/// @notice Script to deploy the Synthetic USD contract with a Gnosis Safe owner.
contract DeploySynteticUSD is Script, CreateXScript {
    address public defaultOwner;

    function setUp() public withCreateX {
        defaultOwner = vm.envAddress("GNOSIS_SAFE_ADMIN");
    }

    function run() external {
        vm.startBroadcast();

        address deployer = msg.sender;

        console2.log("Deployer:", deployer);

        // Prepare the salt
        bytes32 salt = bytes32(abi.encodePacked(deployer, hex"00", bytes11(uint88(1985))));
        bytes memory initCode = abi.encodePacked(type(nUSD).creationCode, abi.encode(defaultOwner, "nUSD", "nUSD"));

        // Calculate the predetermined address of the contract
        address computedAddress = computeCreate3Address(salt, deployer);

        // Deploy using CREATE3
        address deployedAddress = create3(salt, initCode);

        // Check to make sure that contract is on the expected address
        require(computedAddress == deployedAddress);

        vm.stopBroadcast();
    }
}
