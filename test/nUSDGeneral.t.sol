// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

import {Test} from "forge-std/Test.sol";
import {EVaultTestBase} from "../lib/euler-vault-kit/test/unit/evault/EVaultTestBase.t.sol";
import {MockWrongEVC} from "../lib/euler-vault-kit/test/mocks/MockWrongEVC.sol";

import {EthereumVaultConnector} from "ethereum-vault-connector/EthereumVaultConnector.sol";
import {IEVault} from "euler-vault-kit/EVault/IEVault.sol";
import {Errors} from "euler-vault-kit/EVault/shared/Errors.sol";
import {ESynth} from "euler-vault-kit/Synths/ESynth.sol";

import {nUSD} from "../src/nUSD.sol";
import {IRMStabilityFee} from "../src/IRMStabilityFee.sol";

contract nUSDGeneralTest is EVaultTestBase {
    uint128 constant MAX_ALLOWED = type(uint128).max;

    MockWrongEVC public wrongEVC = new MockWrongEVC();

    nUSD public nusd;
    address public user1;
    address public user2;

    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    function setUp() public override {
        super.setUp();

        nusd = nUSD(address(new nUSD(address(evc), "Euler Synth USD", "nUSD")));
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        eTST = createSynthEVault(address(nusd));
    }

    function testFuzz_mintShouldIncreaseTotalSupplyAndBalance(uint128 amount) public {
        amount = uint128(bound(amount, 0, MAX_ALLOWED));
        uint256 balanceBefore = nusd.balanceOf(user1);
        uint256 totalSupplyBefore = nusd.totalSupply();
        nusd.setCapacity(address(this), MAX_ALLOWED);

        nusd.mint(user1, amount);
        assertEq(nusd.balanceOf(user1), balanceBefore + amount);
        assertEq(nusd.totalSupply(), totalSupplyBefore + amount);
    }

    function testFuzz_burnShouldDecreaseTotalSupplyAndBalance(uint128 initialAmount, uint128 burnAmount) public {
        initialAmount = uint128(bound(initialAmount, 1, MAX_ALLOWED));
        nusd.setCapacity(address(this), MAX_ALLOWED);
        nusd.mint(user1, initialAmount);
        burnAmount = uint128(bound(burnAmount, 1, initialAmount));

        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, user2, 0, burnAmount));
        vm.prank(user2);
        nusd.burn(user1, burnAmount);

        vm.prank(user1);
        nusd.approve(user2, burnAmount);

        uint256 allowanceBefore = nusd.allowance(user1, user2);
        uint256 balanceBefore = nusd.balanceOf(user1);
        uint256 totalSupplyBefore = nusd.totalSupply();

        vm.prank(user2);
        nusd.burn(user1, burnAmount);

        assertEq(nusd.balanceOf(user1), balanceBefore - burnAmount);
        assertEq(nusd.totalSupply(), totalSupplyBefore - burnAmount);
        if (allowanceBefore != type(uint256).max) {
            assertEq(nusd.allowance(user1, address(this)), allowanceBefore - burnAmount);
        } else {
            assertEq(nusd.allowance(user1, address(this)), type(uint256).max);
        }
    }

    function testFuzz_mintCapacityReached(uint128 capacity, uint128 amount) public {
        capacity = uint128(bound(capacity, 0, MAX_ALLOWED));
        amount = uint128(bound(amount, 0, MAX_ALLOWED));
        vm.assume(capacity < amount);
        nusd.setCapacity(address(this), capacity);
        vm.expectRevert(ESynth.E_CapacityReached.selector);
        nusd.mint(user1, amount);
    }

    // burn of amount more then minted shoud reset minterCache.minted to 0
    function testFuzz_burnMoreThanMinted(uint128 amount) public {
        amount = uint128(bound(amount, 0, MAX_ALLOWED / 2));
        // one minter mints
        nusd.setCapacity(user2, amount); // we set the cap to less then
        vm.prank(user2);
        nusd.mint(address(nusd), amount);

        // another minter mints
        nusd.setCapacity(user1, amount); // we set the cap to less then
        vm.prank(user1);
        nusd.mint(address(nusd), amount);

        // the owner of the synth can always burn from synth
        nusd.burn(address(nusd), amount * 2);

        (, uint128 minted) = nusd.minters(address(this));
        assertEq(minted, 0);
    }

    function testFuzz_burnFromOwner(uint128 amount) public {
        amount = uint128(bound(amount, 1, MAX_ALLOWED));
        nusd.setCapacity(user1, MAX_ALLOWED);
        vm.prank(user1);
        nusd.mint(user1, amount);

        // the owner of the synth can always burn from synth but cannot from other accounts without allowance
        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(this), 0, amount));
        nusd.burn(user1, amount);

        vm.prank(user1);
        nusd.approve(address(this), amount);
        nusd.burn(user1, amount);

        assertEq(nusd.balanceOf(user1), 0);
    }

    function testFuzz_depositSimple(uint128 amount) public {
        amount = uint128(bound(amount, 1, type(uint112).max)); // amount needs to be less then MAX_SANE_AMOUNT
        nusd.setCapacity(address(this), MAX_ALLOWED);
        nusd.mint(address(nusd), amount); // address(this) should be owner
        nusd.allocate(address(eTST), amount);
    }

    function testFuzz_depositTooLarge(uint128 amount) public {
        amount = uint128(bound(amount, uint256(type(uint112).max) + 1, MAX_ALLOWED));
        nusd.setCapacity(address(this), MAX_ALLOWED);
        nusd.mint(address(nusd), amount);
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        nusd.allocate(address(eTST), amount);
    }

    function testFuzz_withdrawSimple(uint128 amount) public {
        amount = uint128(bound(amount, 1, type(uint112).max));
        nusd.setCapacity(address(this), MAX_ALLOWED);
        nusd.mint(address(nusd), amount);
        nusd.allocate(address(eTST), amount);
        nusd.deallocate(address(eTST), amount);
    }

    function test_AllocateInCompatibleVault() public {
        uint256 amount = 100e18;
        nusd.setCapacity(address(this), MAX_ALLOWED);
        nusd.mint(address(nusd), amount);
        vm.expectRevert(ESynth.E_NotEVCCompatible.selector);
        nusd.allocate(address(wrongEVC), amount);
    }

    function test_GovernanceModifiers(address owner, uint8 id, address nonOwner, uint128 amount) public {
        vm.assume(owner != address(0) && owner != address(evc));
        vm.assume(!evc.haveCommonOwner(owner, nonOwner) && nonOwner != address(evc));
        vm.assume(id != 0);

        vm.prank(owner);
        nusd = nUSD(address(new nUSD(address(evc), "Test Synth", "TST")));

        // succeeds if called directly by an owner
        vm.prank(owner);
        nusd.setCapacity(address(this), amount);

        // fails if called by a non-owner
        vm.prank(nonOwner);
        vm.expectRevert();
        nusd.setCapacity(address(this), amount);

        // succeeds if called by an owner through the EVC
        vm.prank(owner);
        evc.call(address(nusd), owner, 0, abi.encodeCall(nusd.setCapacity, (address(this), amount)));

        // fails if called by non-owner through the EVC
        vm.prank(nonOwner);
        vm.expectRevert();
        evc.call(address(nusd), nonOwner, 0, abi.encodeCall(nusd.setCapacity, (address(this), amount)));

        // fails if called by a sub-account of an owner through the EVC
        vm.prank(owner);
        vm.expectRevert();
        evc.call(
            address(nusd),
            address(uint160(owner) ^ id),
            0,
            abi.encodeCall(nusd.setCapacity, (address(this), amount))
        );

        // fails if called by the owner operator through the EVC
        vm.prank(owner);
        evc.setAccountOperator(owner, nonOwner, true);
        vm.prank(nonOwner);
        vm.expectRevert();
        evc.call(address(nusd), owner, 0, abi.encodeCall(nusd.setCapacity, (address(this), amount)));
    }

    function test_RenounceTransferOwnership() public {
        address OWNER = makeAddr("OWNER");
        address OWNER2 = makeAddr("OWNER2");
        address OWNER3 = makeAddr("OWNER3");

        vm.prank(OWNER);
        nusd = nUSD(address(new nUSD(address(evc), "Test Synth", "TST")));
        assertEq(nusd.owner(), OWNER);

        vm.prank(OWNER2);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OWNER2));
        nusd.renounceOwnership();

        vm.prank(OWNER2);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OWNER2));
        nusd.transferOwnership(OWNER2);

        vm.prank(OWNER);
        nusd.transferOwnership(OWNER2);
        assertEq(nusd.owner(), OWNER2);

        vm.prank(OWNER2);
        nusd.transferOwnership(OWNER3);
        assertEq(nusd.owner(), OWNER3);

        vm.prank(OWNER2);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OWNER2));
        nusd.renounceOwnership();

        vm.prank(OWNER3);
        nusd.renounceOwnership();
        assertEq(nusd.owner(), address(0));
    }
}
