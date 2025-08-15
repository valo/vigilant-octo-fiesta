// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deployer} from "../src/Deployer.sol";
import {nUSD} from "../src/nUSD.sol";
import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

contract DeployerTest is Test {
    Deployer public deployer;
    address public admin = address(0xABCD);

    function setUp() public {
        // Deploy Deployer under a specific admin
        vm.prank(admin);
        deployer = new Deployer();
    }

    function testDeployDeterministicAndAdmin() public {
        // Prepare nUSD creation bytecode with constructor args
        bytes memory creation = abi.encodePacked(type(nUSD).creationCode, abi.encode(address(admin), "Name", "SYM"));
        bytes32 salt = keccak256("TEST_SALT");

        // Deploy via deployer (must be called by admin)
        vm.prank(admin);
        address deployed = deployer.deploy(creation, salt);

        // Compute expected CREATE2 address
        bytes32 codeHash = keccak256(creation);
        address expected =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(deployer), salt, codeHash)))));
        assertEq(deployed, expected, "CREATE2 address mismatch");

        // The deployed nUSD should grant DEFAULT_ADMIN_ROLE to the deployer
        bytes32 DEFAULT_ADMIN_ROLE = AccessControl(deployed).DEFAULT_ADMIN_ROLE();
        assertTrue(AccessControl(deployed).hasRole(DEFAULT_ADMIN_ROLE, admin), "nUSD admin role not assigned");
    }
}
