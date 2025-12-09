// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import {PegStabilityModule} from "../src/PegStabilityModule.sol";

/// @title DeployPSM
/// @notice Script to deploy the PSM contract with a Gnosis Safe owner.
contract DeployPSM is Script, CreateXScript {
    address public mainGnosisSafe;
    address public underlying;
    address public synth;

    function setUp() public withCreateX {
        mainGnosisSafe = vm.envAddress("GNOSIS_SAFE_ADMIN");
        underlying = vm.envAddress("USDC_ADDRESS");
        synth = vm.envAddress("SYNTH_ADDRESS");
    }

    function run() external {
        vm.startBroadcast();

        address deployer = msg.sender;

        console2.log("Deployer:", deployer);

        // Prepare the salt
        bytes32 salt = bytes32(abi.encodePacked(deployer, hex"00", bytes11(keccak256("PSM/USDC Deployment"))));
        bytes memory encodedParams = abi.encode(
            mainGnosisSafe,
            synth,
            underlying,
            mainGnosisSafe,
            10, // 0.1% to underlying fee
            10, // 0.1% to synth fee
            1e18 // Conversion price 1:1
        );
        bytes memory initCode = abi.encodePacked(type(PegStabilityModule).creationCode, encodedParams);

        // Calculate the predetermined address of the contract
        address computedAddress = computeCreate3Address(salt, deployer);

        // Deploy using CREATE3
        address deployedAddress = create3(salt, initCode);

        // Check to make sure that contract is on the expected address
        require(computedAddress == deployedAddress);

        console2.log("Deployed PSM at:", deployedAddress);

        PegStabilityModule psm = PegStabilityModule(deployedAddress);
        console2.log("PSM synth:", address(psm.synth()));
        console2.log("PSM underlying:", address(psm.underlying()));
        console2.log("PSM fee recipient:", psm.feeRecipient());

        console2.log("Make the PSM a minter of the synth token calldata:");
        console.logBytes(abi.encodeCall(psm.synth().grantRole, (psm.synth().MINTER_ROLE(), deployedAddress)));
        console2.log("Set the capacity of the PSM to be unlimited calldata:");
        console.logBytes(abi.encodeCall(psm.synth().setCapacity, (deployedAddress, type(uint128).max)));

        vm.stopBroadcast();
    }
}
