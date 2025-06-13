// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IEVault} from "euler-vault-kit/EVault/IEVault.sol";
import {EulerSavingsRate} from "euler-vault-kit/Synths/EulerSavingsRate.sol";
import {TestERC20} from "../lib/euler-vault-kit/test/mocks/TestERC20.sol";
import {IRMTestDefault} from "../lib/euler-vault-kit/test/mocks/IRMTestDefault.sol";
import {MockHook, EVaultTestBase} from "../lib/euler-vault-kit/test/unit/evault/EVaultTestBase.t.sol";
import {TypesLib} from "../lib/euler-vault-kit/src/EVault/shared/types/Types.sol";

import {nUSD} from "../src/nUSD.sol";

contract ESVaultTestAllocate is EVaultTestBase {
    using TypesLib for uint256;

    address borrower;
    TestERC20 collateralAsset;
    IEVault collateralVault;
    EulerSavingsRate DSR;
    nUSD assetTSTAsSynth;

    function setUp() public virtual override {
        super.setUp();

        assetTSTAsSynth = nUSD(address(new nUSD(address(evc), "Test Synth", "TST")));
        assetTST = TestERC20(address(assetTSTAsSynth));

        eTST = createSynthEVault(address(assetTST));

        assetTSTAsSynth = nUSD(address(new nUSD(address(evc), "Test Synth", "TST")));
        assetTST = TestERC20(address(assetTSTAsSynth));
        eTST = createSynthEVault(address(assetTSTAsSynth));
        eTST.setHookConfig(address(0), 0);
        eTST.setInterestFee(0.1e4);

        DSR = new EulerSavingsRate(address(evc), address(assetTSTAsSynth), "Euler Savings Vault", "ESR");

        assetTSTAsSynth.setCapacity(address(this), 10000e18);
        assetTSTAsSynth.setInterestFee(0.1e4);
        assetTSTAsSynth.setDsrVault(DSR);
        assetTSTAsSynth.mint(address(assetTSTAsSynth), 10000e18);

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
        assetTSTAsSynth.allocate(address(eTST), 100e18);

        // assertEq(assetTSTAsSynth.isIgnoredForTotalSupply(address(eTST)), true);
        assertEq(assetTST.balanceOf(address(eTST)), 100e18);
        assertEq(eTST.balanceOf(address(assetTSTAsSynth)), 100e18);
    }

    function test_accumulate_interest() public {
        assetTSTAsSynth.allocate(address(eTST), 100e18);

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

        uint256 interest = assetTSTAsSynth.accumulatedInterest(eTST);
        assertApproxEqAbs(interest, netInterest, 0.0001e18);

        uint256 DSRfee = netInterest * assetTSTAsSynth.interestFee() / 1e4;
        uint256 netDSRInterest = netInterest - DSRfee;
        // Withdraw the interest to the ESR
        assetTSTAsSynth.depositInterestInDSR(eTST, address(this));

        assertApproxEqAbs(assetTSTAsSynth.balanceOf(address(this)), DSRfee, 0.0001e18);

        // After 2 weeks all the interest should be accumulated in the deposit
        skip(14 days);

        uint256 esrBalance = DSR.balanceOf(borrower);
        uint256 esrInterest = DSR.convertToAssets(esrBalance);
        assertApproxEqAbs(esrInterest, 5e18 + netDSRInterest, 0.0001e18);
    }
}
