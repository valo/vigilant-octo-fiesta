// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

/// @title Deployer
/// @notice Utility contract that can deploy arbitrary creation bytecode via CREATE2, so addresses are deterministic.
contract Deployer is Ownable {
    /// @notice Emitted when a new contract is deployed.
    /// @param addr The address of the deployed contract.
    /// @param code The creation bytecode used.
    /// @param salt The salt that was used for CREATE2.
    event Deployed(address indexed addr, bytes code, bytes32 salt);

    /// @notice Computes the address where a contract will be deployed with CREATE2.
    /// @param creationCode The creation bytecode used (constructor + code).
    /// @param salt The salt for deterministic deployment.
    /// @return addr The address at which the contract will be deployed.
    function computeAddress(bytes calldata creationCode, bytes32 salt) external view returns (address addr) {
        bytes32 codeHash = keccak256(creationCode);
        addr = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, codeHash)))));
    }

    /// @param owner_ The account that will become owner of this contract.
    constructor(address owner_) Ownable(owner_) {}

    /// @notice Deploys a contract using `CREATE2` with the given salt.
    /// @param creationCode The creation bytecode of the contract (including constructor args).
    /// @param salt A salt for deterministic deployment.
    /// @return addr The address of the deployed contract.
    function deploy(bytes calldata creationCode, bytes32 salt) external onlyOwner returns (address addr) {
        bytes memory code = creationCode;
        assembly {
            addr := create2(0, add(code, 0x20), mload(code), salt)
        }
        require(addr != address(0), "Deployer: CREATE2 failed");
        emit Deployed(addr, creationCode, salt);
    }
}
