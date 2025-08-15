// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

/// @title Deployer
/// @notice Utility contract that can deploy arbitrary creation bytecode via CREATE2, so addresses are deterministic.
contract Deployer is Ownable(msg.sender) {
    /// @notice Emitted when a new contract is deployed.
    /// @param addr The address of the deployed contract.
    /// @param code The creation bytecode used.
    /// @param salt The salt that was used for CREATE2.
    event Deployed(address indexed addr, bytes code, bytes32 salt);

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
