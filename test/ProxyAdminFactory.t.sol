// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {ITransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import {ProxyAdminFactory} from "src/ProxyAdminFactory.sol";

contract ProxyAdminFactoryTest is Test {
    ProxyAdminFactory internal factory;

    function setUp() public {
        factory = new ProxyAdminFactory();
    }

    function testOwnerIsDeployer() public {
        assertEq(factory.owner(), address(this));
    }

    function testDeployAndInitializeProxy() public {
        SimpleMock impl = new SimpleMock();
        bytes memory initData = abi.encodeWithSelector(SimpleMock.initialize.selector, 123);
        address proxyAddr = factory.deployProxy(address(impl), initData);

        // Check that the proxy delegates calls correctly
        SimpleMock proxyMock = SimpleMock(proxyAddr);
        assertEq(proxyMock.value(), 123);
    }

    function testUpgradeAndCall() public {
        SimpleMock implV1 = new SimpleMock();
        bytes memory initData = abi.encodeWithSelector(SimpleMock.initialize.selector, 1);
        address proxyAddr = factory.deployProxy(address(implV1), initData);
        SimpleMock proxyMock = SimpleMock(proxyAddr);
        assertEq(proxyMock.value(), 1);

        // Deploy new implementation and upgrade via factory
        SimpleMock implV2 = new SimpleMock();
        bytes memory upgradeData = abi.encodeWithSelector(SimpleMock.initialize.selector, 2);
        factory.upgradeAndCall(ITransparentUpgradeableProxy(payable(proxyAddr)), address(implV2), upgradeData);
        assertEq(proxyMock.value(), 2);
    }
}

/// @notice Simple mock contract for initialization testing
contract SimpleMock is Initializable {
    uint256 public value;

    /// @notice Sets initial value; only callable once via initializer
    function initialize(uint256 _value) external initializer {
        value = _value;
    }
}
