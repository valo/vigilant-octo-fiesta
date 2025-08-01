// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {PegStabilityModule} from "../src/PegStabilityModule.sol";
import {nUSD} from "../src/nUSD.sol";
import {TestERC20} from "../lib/euler-vault-kit/test/mocks/TestERC20.sol";

contract PegStabilityModuleTest is Test {
    uint256 constant CONVERSION_PRICE = 1e18;
    uint256 constant TO_UNDERLYING_FEE = 100; // 1%
    uint256 constant TO_SYNTH_FEE = 50; // 0.5%

    nUSD synth;
    TestERC20 underlying;
    PegStabilityModule psm;

    address owner = makeAddr("owner");
    address user = makeAddr("user");
    address receiver = makeAddr("receiver");
    address feeRecipient = makeAddr("feeRecipient");

    function setUp() public {
        startHoax(owner);
        synth = new nUSD(address(1), "Synth", "SYN");
        vm.label(address(synth), "USDfi");

        underlying = new TestERC20("Underlying", "UND", 18, false);
        vm.label(address(underlying), "Underlying");

        psm = new PegStabilityModule(
            address(synth), address(underlying), feeRecipient, TO_UNDERLYING_FEE, TO_SYNTH_FEE, CONVERSION_PRICE
        );
        vm.label(address(psm), "PSM");

        underlying.mint(address(psm), 1000 ether);
        underlying.mint(user, 1000 ether);

        vm.startPrank(owner);
        synth.setCapacity(address(psm), type(uint128).max);
        synth.setCapacity(owner, type(uint128).max);
        synth.mint(user, 1000 ether);
        vm.stopPrank();

        startHoax(user);

        synth.approve(address(psm), type(uint256).max);
        underlying.approve(address(psm), type(uint256).max);
    }

    function testFuzz_swapToUnderlyingFunnelFee(uint96 amountIn) public {
        amountIn = uint96(bound(amountIn, 1e18, synth.balanceOf(user)));
        uint256 expectedOut = psm.quoteToUnderlyingGivenIn(amountIn);
        uint256 totalUnderlying = (amountIn * CONVERSION_PRICE) / psm.PRICE_SCALE();
        uint256 fee = totalUnderlying - expectedOut;

        startHoax(user);
        psm.swapToUnderlyingGivenIn(amountIn, receiver);

        assertEq(underlying.balanceOf(receiver), expectedOut);
        assertEq(underlying.balanceOf(feeRecipient), fee);
    }

    function testFuzz_swapToSynthFunnelFee(uint96 amountIn) public {
        amountIn = uint96(bound(amountIn, 1e18, underlying.balanceOf(user)));
        uint256 expectedOut = psm.quoteToSynthGivenIn(amountIn);
        uint256 mintedUnderlying = (expectedOut * psm.PRICE_SCALE()) / CONVERSION_PRICE;
        uint256 fee = amountIn - mintedUnderlying; // 1:1 price

        startHoax(user);
        psm.swapToSynthGivenIn(amountIn, receiver);

        assertEq(synth.balanceOf(receiver), expectedOut);
        assertEq(underlying.balanceOf(feeRecipient), fee);
    }

    function testFuzz_swapToSynthGivenOut(uint96 amountOut) public {
        uint256 maxOut = psm.quoteToSynthGivenIn(underlying.balanceOf(user));
        amountOut = uint96(bound(amountOut, 1e18, maxOut));

        uint256 expectedIn = psm.quoteToSynthGivenOut(amountOut);
        uint256 totalUnderlying = (expectedIn * psm.PRICE_SCALE()) / CONVERSION_PRICE;
        uint256 fee = totalUnderlying - amountOut;

        startHoax(user);
        uint256 actualIn = psm.swapToSynthGivenOut(amountOut, receiver);

        assertEq(actualIn, expectedIn);
        assertEq(synth.balanceOf(receiver), amountOut);
        assertEq(underlying.balanceOf(feeRecipient), fee);
    }

    function testFuzz_swapToUnderlyingGivenOut(uint96 amountOut) public {
        uint256 maxOut = psm.quoteToUnderlyingGivenIn(synth.balanceOf(user));
        amountOut = uint96(bound(amountOut, 1e18, maxOut));

        uint256 expectedIn = psm.quoteToUnderlyingGivenOut(amountOut);
        uint256 totalUnderlying = (expectedIn * CONVERSION_PRICE) / psm.PRICE_SCALE();
        uint256 fee = totalUnderlying - amountOut;

        startHoax(user);
        uint256 actualIn = psm.swapToUnderlyingGivenOut(amountOut, receiver);

        assertEq(actualIn, expectedIn);
        assertEq(underlying.balanceOf(receiver), amountOut);
        assertEq(underlying.balanceOf(feeRecipient), fee);
    }

    function testFuzz_setFees(uint256 uFee, uint256 sFee) public {
        uFee = bound(uFee, 0, psm.MAX_FEE_BPS());
        sFee = bound(sFee, 0, psm.MAX_FEE_BPS());
        startHoax(owner);
        psm.setFees(uFee, sFee);

        assertEq(psm.toUnderlyingFeeBPS(), uFee);
        assertEq(psm.toSynthFeeBPS(), sFee);
    }
}
