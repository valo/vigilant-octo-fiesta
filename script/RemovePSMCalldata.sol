// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PegStabilityModule} from "../src/PegStabilityModule.sol";

/// @title DeployPSM
/// @notice Script to deploy the PSM contract with a Gnosis Safe owner.
contract DeployPSM is Script {
    address public feeRecipient;
    PegStabilityModule public psm;

    function setUp() public {
        psm = PegStabilityModule(vm.envAddress("PSM_ADDRESS"));
    }

    function run() external view {
        console2.log("Remove the PSM as a minter calldata:");
        console.logBytes(abi.encodeCall(psm.synth().revokeRole, (psm.synth().MINTER_ROLE(), address(psm))));
        console2.log("Set the capacity of the PSM to be 0 calldata:");
        console.logBytes(abi.encodeCall(psm.synth().setCapacity, (address(psm), 0)));
    }
}
