// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IEVault} from "euler-vault-kit/EVault/IEVault.sol";
import {IIRM} from "euler-vault-kit/InterestRateModels/IIRM.sol";
import {RPow} from "euler-vault-kit/EVault/shared/lib/RPow.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {TestERC20} from "../lib/euler-vault-kit/test/mocks/TestERC20.sol";
import {IRMTestFixed} from "../lib/euler-vault-kit/test/mocks/IRMTestFixed.sol";
import {MockHook, EVaultTestBase} from "../lib/euler-vault-kit/test/unit/evault/EVaultTestBase.t.sol";
import {TypesLib} from "../lib/euler-vault-kit/src/EVault/shared/types/Types.sol";

import {SavingsRateModule} from "../src/SavingsRateModule.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {nUSD} from "../src/nUSD.sol";

contract ESVaultTestAllocate is EVaultTestBase {
    using TypesLib for uint256;

    uint128 immutable MAX_MINT_AMOUNT = 1000000000000e18;

    address borrower;
    TestERC20 collateralAsset;
    IEVault collateralVault;
    SavingsRateModule DSR;
    nUSD assetTSTAsSynth;

    function setUp() public virtual override {
        super.setUp();

        assetTSTAsSynth = new nUSD("Test Synth", "TST");
        assetTST = TestERC20(address(assetTSTAsSynth));
        eTST = createSynthEVault(address(assetTSTAsSynth));
        eTST.setInterestRateModel(address(new IRMTestFixed()));
        eTST.setHookConfig(address(0), 0);
        eTST.setInterestFee(0.1e4);

        DSR = new SavingsRateModule(IERC20(address(assetTST)), "Savings Vault", "SV", 2 weeks);

        assetTSTAsSynth.setCapacity(address(this), MAX_MINT_AMOUNT);
        assetTSTAsSynth.setInterestFee(0.1e4);
        assetTSTAsSynth.setDsrVault(DSR);
        assetTSTAsSynth.mint(address(assetTSTAsSynth), MAX_MINT_AMOUNT);

        // Set up borrower and the collateral vault
        borrower = makeAddr("borrower");

        collateralAsset = new TestERC20("Collateral Token", "COLAT", 18, false);

        collateralVault = IEVault(
            factory.createProxy(
                address(0), true, abi.encodePacked(address(collateralAsset), address(oracle), unitOfAccount)
            )
        );
        collateralVault.setHookConfig(address(0), 0);
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

    function testFuzz_allocate_from_synth(uint256 vaultCap) public {
        vm.assume(vaultCap > 0 && vaultCap <= MAX_MINT_AMOUNT);

        assetTSTAsSynth.allocate(address(eTST), vaultCap);

        assertEq(assetTST.balanceOf(address(eTST)), vaultCap);
        assertEq(eTST.balanceOf(address(assetTSTAsSynth)), vaultCap);
    }

    function testFuzz_accumulate_interest(uint256 vaultCap, uint256 borrowAmount) public {
        vm.assume(vaultCap > 0 && vaultCap <= MAX_MINT_AMOUNT && borrowAmount < vaultCap);
        assetTSTAsSynth.allocate(address(eTST), vaultCap);

        startHoax(borrower);

        evc.enableCollateral(borrower, address(collateralVault));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(borrowAmount, borrower);

        assetTST.approve(address(DSR), borrowAmount);
        DSR.deposit(borrowAmount, borrower);

        vm.stopPrank();

        skip(365 days);

        startHoax(address(eTST));
        uint256 interestRate =
            IIRM(eTST.interestRateModel()).computeInterestRateView(address(eTST), eTST.cash(), eTST.totalBorrows());
        (uint256 multiplier, bool overflow) = RPow.rpow(interestRate + 1e27, 365 days, 1e27);
        assertFalse(overflow, "Overflow in interest rate calculation");
        vm.stopPrank();

        uint256 currDebt = eTST.debtOf(borrower);
        uint256 expectedDebt = Math.mulDiv(borrowAmount, multiplier, 1e27);
        assertApproxEqAbs(currDebt, expectedDebt, 0.0001e18);

        uint256 interest = assetTSTAsSynth.accumulatedInterest(address(eTST));

        uint256 interestToWithdraw = interest > eTST.cash() ? eTST.cash() : interest;

        uint256 DSRfee = interestToWithdraw * assetTSTAsSynth.interestFee() / 1e4;
        uint256 netDSRInterest = interestToWithdraw - DSRfee;
        // Withdraw the interest to the ESR
        assetTSTAsSynth.depositInterestInDSR(interestToWithdraw, address(eTST), address(this));

        assertApproxEqAbs(assetTSTAsSynth.balanceOf(address(this)), DSRfee, 0.0001e18);

        // Wait for the DSR to drip the interest
        skip(DSR.smearDuration());
        DSR.gulp();

        // All undistributed interest should be dripped and cleared after gulp
        assertApproxEqAbs(DSR.undistributed(), 0, 0.0001e18, "Interest left should be zero after update");

        uint256 esrBalance = DSR.balanceOf(borrower);
        uint256 esrInterest = DSR.convertToAssets(esrBalance);
        assertApproxEqAbs(esrInterest, borrowAmount + netDSRInterest, 0.0001e18);
    }
}
