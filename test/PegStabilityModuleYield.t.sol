// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {PegStabilityModuleYield} from "../src/PegStabilityModuleYield.sol";
import {nUSD} from "../src/nUSD.sol";
import {TestERC20} from "../lib/euler-vault-kit/test/mocks/TestERC20.sol";
import {MockStakedUSDe} from "./mocks/MockStakedUSDe.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

contract PegStabilityModuleYieldTest is Test {
    uint256 constant CONVERSION_PRICE = 1e18;
    uint256 constant TO_UNDERLYING_FEE = 100; // 1%
    uint256 constant TO_SYNTH_FEE = 50; // 0.5%
    uint256 constant LIQUID_TARGET = 100 ether;

    nUSD synth;
    TestERC20 underlying;
    MockStakedUSDe vault;
    PegStabilityModuleYield psm;

    address owner = makeAddr("owner");
    address user = makeAddr("user");
    address feeRecipient = makeAddr("feeRecipient");

    function setUp() public {
        vm.startPrank(owner);
        synth = new nUSD(address(1), "Synth", "SYN");
        underlying = new TestERC20("Underlying", "UND", 18, false);
        vault = new MockStakedUSDe(IERC20(address(underlying)), 3 days);

        psm = new PegStabilityModuleYield(
            address(synth),
            address(underlying),
            feeRecipient,
            TO_UNDERLYING_FEE,
            TO_SYNTH_FEE,
            CONVERSION_PRICE,
            address(vault),
            LIQUID_TARGET
        );

        underlying.mint(address(psm), 1000 ether);
        underlying.mint(user, 1000 ether);

        synth.setCapacity(address(psm), type(uint128).max);
        synth.setCapacity(owner, type(uint128).max);
        synth.mint(user, 1000 ether);

        vm.stopPrank();

        vm.startPrank(user);
        synth.approve(address(psm), type(uint256).max);
        underlying.approve(address(psm), type(uint256).max);
        vm.stopPrank();

        // stake initial excess
        vm.prank(owner);
        psm.stakeExcess();
    }

    function testFuzz_depositOverLiquidTarget(uint256 amountIn) public {
        amountIn = bound(amountIn, 1e6, underlying.balanceOf(user));

        uint256 minted = psm.quoteToSynthGivenIn(amountIn);

        vm.prank(user);
        psm.swapToSynthGivenIn(amountIn, user);

        // excess underlying should be staked keeping liquid balance at target
        assertEq(underlying.balanceOf(address(psm)), LIQUID_TARGET);
        // staked shares increase by the minted underlying
        assertEq(vault.balanceOf(address(psm)), 900 ether + minted);
    }

    function testFuzz_depositWithinLiquidTarget(uint256 withdrawSynth, uint256 depositUnderlying) public {
        // pull some liquidity out first so the PSM is below target
        withdrawSynth = bound(withdrawSynth, 1e6, LIQUID_TARGET);
        vm.prank(user);
        psm.swapToUnderlyingGivenIn(withdrawSynth, user);

        uint256 preBalance = underlying.balanceOf(address(psm));
        uint256 preShares = vault.balanceOf(address(psm));

        // deposit an amount that keeps us under the liquid target
        depositUnderlying = bound(depositUnderlying, 1e6, withdrawSynth);
        uint256 minted = psm.quoteToSynthGivenIn(depositUnderlying);

        vm.prank(user);
        psm.swapToSynthGivenIn(depositUnderlying, user);

        // no staking should occur
        assertEq(underlying.balanceOf(address(psm)), preBalance + minted);
        assertEq(vault.balanceOf(address(psm)), preShares);
    }

    function testFuzz_startUnstake(uint256 amount) public {
        amount = bound(amount, 1e6, 900 ether);

        vm.prank(owner);
        psm.startUnstake(amount);

        assertEq(psm.pendingCooldown(), amount);
        assertEq(vault.balanceOf(address(psm)), 900 ether - amount);
    }

    function testFuzz_finalizeUnstake(uint256 amount) public {
        amount = bound(amount, 1e6, 900 ether);

        vm.prank(owner);
        psm.startUnstake(amount);

        vm.warp(block.timestamp + 3 days);
        psm.finalizeUnstake();

        assertEq(psm.pendingCooldown(), 0);
        assertEq(underlying.balanceOf(address(psm)), LIQUID_TARGET + amount);
        assertEq(vault.balanceOf(address(psm)), 900 ether - amount);
    }

    function test_setLiquidTarget_changesLiquidTarget() public {
        uint256 newTarget = LIQUID_TARGET + 1 ether;
        // initial target is the constructor value
        assertEq(psm.liquidTarget(), LIQUID_TARGET);
        vm.prank(owner);
        psm.setLiquidTarget(newTarget);
        assertEq(psm.liquidTarget(), newTarget);
    }

    function test_setLiquidTarget_onlyOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        psm.setLiquidTarget(LIQUID_TARGET + 10);
    }

    /// @notice fuzz test donating staked assets and then staking excess liquidity above the target
    function testFuzz_donateStakedAssets(uint256 donation, uint256 gift) public {
        uint256 userBal = underlying.balanceOf(user);
        // ensure enough balance to donate and then gift underlying to PSM
        donation = bound(donation, 1e6, userBal - 1e6);
        gift = bound(gift, 1e6, userBal - donation);

        uint256 preVault = vault.balanceOf(address(psm));

        // user donates staked assets by depositing into vault for PSM
        vm.prank(user);
        underlying.approve(address(vault), donation);
        vm.prank(user);
        vault.deposit(donation, address(psm));

        // PSM receives extra underlying to exceed its liquid target (simulate user transfer)
        vm.prank(user);
        underlying.transfer(address(psm), gift);
        assertGt(underlying.balanceOf(address(psm)), LIQUID_TARGET);

        // staking excess should stake the gift amount; vault shares include donation + gift
        vm.prank(owner);
        psm.stakeExcess();
        assertEq(vault.balanceOf(address(psm)), preVault + donation + gift);
        assertEq(underlying.balanceOf(address(psm)), LIQUID_TARGET);
    }
}
