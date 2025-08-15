// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ProxyAdmin} from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @title ProxyAdminFactory
/// @author Valentin Mihov (valentin.mihov@gmail.com)
/// @notice Combines OpenZeppelin's ProxyAdmin for upgrade management with a factory to deploy transparent proxies
contract ProxyAdminFactory is ProxyAdmin {
    /// @dev ProxyAdmin constructor sets the initial owner (e.g., Gnosis Safe)
    constructor() ProxyAdmin(msg.sender) {}
    /// @notice Emitted when a new proxy is deployed
    /// @param proxy The address of the deployed proxy contract

    event ProxyDeployed(address indexed proxy);

    /// @notice Deploys a new TransparentUpgradeableProxy and sets this contract as its admin
    /// @dev Only the owner (ProxyAdmin owner) can call this function
    /// @param implementation The address of the implementation contract
    /// @param data The initialization calldata for the proxy
    /// @return proxy The address of the newly created proxy
    function deployProxy(address implementation, bytes memory data) external onlyOwner returns (address proxy) {
        proxy = address(new TransparentUpgradeableProxy(implementation, address(this), data));
        emit ProxyDeployed(proxy);
    }
}
