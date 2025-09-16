// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {PegStabilityModule} from "../src/PegStabilityModule.sol";
import {nUSD} from "../src/nUSD.sol";
import {TestERC20} from "../lib/euler-vault-kit/test/mocks/TestERC20.sol";

contract PegStabilityModuleTest is Test {
    uint256 constant CONVERSION_PRICE = 1e18; // 1:1 price
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
        synth = new nUSD(owner, "Synth", "SYN");
        vm.label(address(synth), "USDfi");

        // Note: the underlying has 6 decimals
        underlying = new TestERC20("Underlying", "UND", 6, false);
        vm.label(address(underlying), "Underlying");

        psm = new PegStabilityModule(
            owner, address(synth), address(underlying), feeRecipient, TO_UNDERLYING_FEE, TO_SYNTH_FEE, CONVERSION_PRICE
        );
        vm.label(address(psm), "PSM");
        synth.grantRole(synth.MINTER_ROLE(), address(psm));

        underlying.mint(address(psm), 1000 * 1e6); // Fund the PSM with some underlying
        underlying.mint(user, 1000 * 1e6);

        synth.grantRole(synth.MINTER_ROLE(), owner);
        synth.setCapacity(address(psm), type(uint128).max);
        synth.setCapacity(owner, type(uint128).max);
        synth.mint(user, 1000 ether);
        vm.stopPrank();

        startHoax(user);

        synth.approve(address(psm), type(uint256).max);
        underlying.approve(address(psm), type(uint256).max);
    }

    function testFuzz_swapToUnderlyingFunnelFee(uint96 amountIn) public {
        amountIn = uint96(bound(amountIn, 1, synth.balanceOf(user)));
        uint256 expectedOut = psm.quoteToUnderlyingGivenIn(amountIn);
        uint256 totalUnderlying = _denormalize((amountIn * CONVERSION_PRICE) / psm.PRICE_SCALE());
        uint256 fee = totalUnderlying - expectedOut;

        startHoax(user);
        psm.swapToUnderlyingGivenIn(amountIn, receiver);

        assertEq(underlying.balanceOf(receiver), expectedOut);
        assertEq(underlying.balanceOf(feeRecipient), fee);
    }

    function testFuzz_swapToSynthFunnelFee(uint96 amountIn) public {
        amountIn = uint96(bound(amountIn, 1, underlying.balanceOf(user)));
        uint256 expectedOut = psm.quoteToSynthGivenIn(amountIn);
        uint256 mintedUnderlying = _denormalize((expectedOut * CONVERSION_PRICE) / psm.PRICE_SCALE());
        uint256 fee = amountIn - mintedUnderlying;

        startHoax(user);
        psm.swapToSynthGivenIn(amountIn, receiver);

        assertEq(synth.balanceOf(receiver), expectedOut);
        assertEq(underlying.balanceOf(feeRecipient), fee);
    }

    function testFuzz_swapToSynthGivenOut(uint96 amountOut) public {
        uint256 maxOut = psm.quoteToSynthGivenIn(underlying.balanceOf(user));
        amountOut = uint96(bound(amountOut, 1e18, maxOut));

        uint256 expectedIn = psm.quoteToSynthGivenOut(amountOut);
        uint256 mintedUnderlying = _denormalize((amountOut * CONVERSION_PRICE) / psm.PRICE_SCALE());
        uint256 fee = expectedIn - mintedUnderlying;

        startHoax(user);
        uint256 actualIn = psm.swapToSynthGivenOut(amountOut, receiver);

        assertEq(actualIn, expectedIn);
        assertEq(synth.balanceOf(receiver), amountOut);
        assertEq(underlying.balanceOf(feeRecipient), fee);
    }

    function testFuzz_swapToUnderlyingGivenOut(uint96 amountOut) public {
        uint256 maxOut = psm.quoteToUnderlyingGivenIn(synth.balanceOf(user));
        uint256 minOut = 10 ** uint256(underlying.decimals());
        if (maxOut < minOut) {
            amountOut = uint96(maxOut);
        } else {
            amountOut = uint96(bound(amountOut, minOut, maxOut));
        }

        uint256 expectedIn = psm.quoteToUnderlyingGivenOut(amountOut);
        uint256 totalUnderlying = _denormalize((expectedIn * CONVERSION_PRICE) / psm.PRICE_SCALE());
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

    function test_constructor_rejectsUnderlyingWithMoreThan18Decimals() public {
        TestERC20 highPrecisionUnderlying = new TestERC20("High", "HIGH", 19, false);

        vm.expectRevert(PegStabilityModule.E_UnsupportedDecimals.selector);
        new PegStabilityModule(
            owner,
            address(synth),
            address(highPrecisionUnderlying),
            feeRecipient,
            TO_UNDERLYING_FEE,
            TO_SYNTH_FEE,
            CONVERSION_PRICE
        );
    }

    function _denormalize(uint256 amount) internal view returns (uint256) {
        uint8 decimals = underlying.decimals();
        if (decimals < 18) {
            return amount / 10 ** uint256(18 - decimals);
        }
        return amount;
    }
}
