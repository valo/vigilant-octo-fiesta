// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import {PegStabilityModule} from "../src/PegStabilityModule.sol";
import {DeterministicCreate3Script} from "./DeploymentHelpers.s.sol";

/// @title DeployPSM
/// @notice Deploys the PegStabilityModule deterministically and prints governance calldata for synth permissions.
contract DeployPSM is DeterministicCreate3Script {
    address public mainGnosisSafe;
    address public underlying;
    address public synth;
    address public feeRecipient;
    bytes32 public deploymentSalt;
    uint256 public toUnderlyingFeeBps;
    uint256 public toSynthFeeBps;
    uint256 public conversionPrice;

    function setUp() public withCreateX {
        mainGnosisSafe = vm.envAddress("GNOSIS_SAFE_ADMIN");
        underlying = vm.envAddress("USDC_ADDRESS");
        synth = vm.envAddress("SYNTH_ADDRESS");
        feeRecipient = vm.envOr("PSM_FEE_RECIPIENT", mainGnosisSafe);
        toUnderlyingFeeBps = vm.envOr("PSM_TO_UNDERLYING_FEE_BPS", uint256(10));
        toSynthFeeBps = vm.envOr("PSM_TO_SYNTH_FEE_BPS", uint256(10));
        conversionPrice = vm.envOr("PSM_CONVERSION_PRICE_WAD", uint256(1e18));
    }

    function run() external {
        vm.startBroadcast();

        address deployer = msg.sender;
        deploymentSalt = resolveSalt(
            "PSM_DEPLOY_SALT", bytes32(abi.encodePacked(deployer, hex"00", bytes11(keccak256("PSM/USDC Deployment"))))
        );

        console2.log("Deployer:", deployer);
        console2.log("Underlying:", underlying);
        console2.log("Synth:", synth);
        console2.log("Fee recipient:", feeRecipient);
        console2.log("To underlying fee (bps):", toUnderlyingFeeBps);
        console2.log("To synth fee (bps):", toSynthFeeBps);
        console2.log("Conversion price (WAD):", conversionPrice);

        bytes memory encodedParams = abi.encode(
            mainGnosisSafe,
            synth,
            underlying,
            feeRecipient,
            toUnderlyingFeeBps,
            toSynthFeeBps,
            conversionPrice
        );
        console2.log("Constructor arguments:");
        console2.logBytes(encodedParams);

        bytes memory initCode = abi.encodePacked(type(PegStabilityModule).creationCode, encodedParams);
        (address deployedAddress,, bool freshlyDeployed) = deployDeterministic(deploymentSalt, initCode);

        PegStabilityModule psm = PegStabilityModule(deployedAddress);
        console2.log("Deployed PSM at:", deployedAddress);
        console2.log("Deployment executed:", freshlyDeployed);
        console2.log("PSM synth:", address(psm.synth()));
        console2.log("PSM underlying:", address(psm.underlying()));
        console2.log("PSM fee recipient:", psm.feeRecipient());

        console2.log("Make the PSM a minter of the synth token calldata:");
        console2.logBytes(abi.encodeCall(psm.synth().grantRole, (psm.synth().MINTER_ROLE(), deployedAddress)));
        console2.log("Set the capacity of the PSM to be unlimited calldata:");
        console2.logBytes(abi.encodeCall(psm.synth().setCapacity, (deployedAddress, type(uint128).max)));

        vm.stopBroadcast();
    }
}
