// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ESVaultTestBase, ESynth} from "../lib/euler-vault-kit/test/unit/esvault/ESVaultTestBase.t.sol";
import {IEVault} from "euler-vault-kit/EVault/IEVault.sol";
import {EulerSavingsRate} from "euler-vault-kit/Synths/EulerSavingsRate.sol";
import {TestERC20} from "../lib/euler-vault-kit/test/mocks/TestERC20.sol";
import {IRMTestDefault} from "../lib/euler-vault-kit/test/mocks/IRMTestDefault.sol";
import {MockHook} from "../lib/euler-vault-kit/test/unit/evault/EVaultTestBase.t.sol";
import {TypesLib} from "../lib/euler-vault-kit/src/EVault/shared/types/Types.sol";

import {nUSD} from "../src/nUSD.sol";
import {Allocator} from "../src/Allocator.sol";

contract ESVaultTestAllocate is ESVaultTestBase {
    using TypesLib for uint256;

    address borrower;
    TestERC20 collateralAsset;
    IEVault collateralVault;
    EulerSavingsRate DSR;
    Allocator allocator;
    nUSD synthUSD;

    function setUp() public override {
        super.setUp();

        synthUSD = nUSD(address(new nUSD(address(evc), "Test Synth", "TST")));
        assetTST = TestERC20(address(synthUSD));
        eTST = createSynthEVault(address(synthUSD));
        eTST.setHookConfig(address(0), 0);
        eTST.setInterestFee(0.1e4);

        DSR = new EulerSavingsRate(address(evc), address(synthUSD), "Euler Savings Vault", "ESR");

        // Allocator setup
        allocator = new Allocator(
            address(synthUSD),
            address(DSR),
            100 // 10% interest fee
        );
        synthUSD.setCapacity(address(allocator), 10000e18);
        synthUSD.transferOwnership(address(allocator));

        // Set up borrower and the collateral vault
        borrower = makeAddr("borrower");

        collateralAsset = new TestERC20("Collateral Token", "COLAT", 18, false);

        collateralVault = IEVault(
            factory.createProxy(
                address(0), true, abi.encodePacked(address(collateralAsset), address(oracle), unitOfAccount)
            )
        );
        collateralVault.setHookConfig(address(0), 0);
        collateralVault.setInterestRateModel(address(new IRMTestDefault()));
        collateralVault.setMaxLiquidationDiscount(0.2e4);
        collateralVault.setFeeReceiver(feeReceiver);

        collateralAsset.mint(borrower, 10000e18);

        // Setup

        oracle.setPrice(address(collateralAsset), unitOfAccount, 1e18);

        eTST.setLTV(address(collateralVault), 0.9e4, 0.9e4, 0);

        // Borrower

        startHoax(borrower);

        collateralAsset.approve(address(collateralVault), type(uint256).max);
        collateralVault.deposit(100e18, borrower);

        vm.stopPrank();
    }

    // function test_allocate_from_non_synth() public {
    //     vm.expectRevert(MockHook.E_OnlyAssetCanDeposit.selector);
    //     eTST.deposit(100, address(this));

    //     vm.expectRevert(MockHook.E_OperationDisabled.selector);
    //     eTST.mint(100, address(this));

    //     vm.expectRevert(MockHook.E_OperationDisabled.selector);
    //     eTST.skim(100, address(this));

    //     assertEq(eTST.maxDeposit(address(this)), type(uint112).max - eTST.cash());

    //     assertEq(eTST.maxMint(address(this)), type(uint112).max - eTST.totalSupply());

    //     assertEq(eTST.maxRedeem(address(this)), eTST.balanceOf(address(this)));
    // }

    function test_allocate_from_synth() public {
        allocator.allocate(address(eTST), 100e18);

        // assertEq(synthUSD.isIgnoredForTotalSupply(address(eTST)), true);
        assertEq(assetTST.balanceOf(address(eTST)), 100e18);
        assertEq(eTST.balanceOf(address(allocator)), 100e18);
    }

    function test_accumulate_interest() public {
        allocator.allocate(address(eTST), 100e18);

        startHoax(borrower);

        evc.enableCollateral(borrower, address(collateralVault));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(5e18, borrower);

        assetTST.approve(address(DSR), 5e18);
        DSR.deposit(5e18, borrower);

        vm.stopPrank();

        skip(365 days);

        uint256 currDebt = eTST.debtOf(borrower);
        assertApproxEqAbs(currDebt, 5.047850970117656981e18, 0.0001e18);

        uint256 totalInterest = currDebt - 5e18;
        uint256 govFee = totalInterest * eTST.interestFee() / 1e4;
        uint256 netInterest = totalInterest - govFee;

        uint256 interest = allocator.accumulatedInterest(address(eTST));
        assertApproxEqAbs(interest, netInterest, 0.0001e18);

        uint256 DSRfee = netInterest * allocator.interestFee() / 1e4;
        uint256 netDSRInterest = netInterest - DSRfee;
        // Withdraw the interest to the ESR
        allocator.depositInterestInDSR(address(eTST));

        // After 2 weeks all the interest should be accumulated in the deposit
        skip(14 days);

        uint256 esrBalance = DSR.balanceOf(borrower);
        uint256 esrInterest = DSR.convertToAssets(esrBalance);
        assertApproxEqAbs(esrInterest, 5e18 + netDSRInterest, 0.0001e18);
    }
}
