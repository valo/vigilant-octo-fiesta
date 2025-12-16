// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import {Rebalancer} from "../src/Rebalancer.sol";
import {IEVault} from "euler-vault-kit/EVault/IEVault.sol";
import {CFG_EVC_COMPATIBLE_ASSET} from "euler-vault-kit/EVault/shared/Constants.sol";
import {EVaultTestBase} from "../lib/euler-vault-kit/test/unit/evault/EVaultTestBase.t.sol";
import {IRMTestDefault} from "../lib/euler-vault-kit/test/mocks/IRMTestDefault.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

contract RebalancerTest is EVaultTestBase {
    uint16 internal constant FEE_BPS = 25;

    Rebalancer rebalancer;
    IEVault debtA;
    IEVault debtB;
    IEVault collateralVault;

    uint256 userPk;
    address user;
    address userSub;
    address lp;
    address keeper;
    address rebalanceFeeRecipient;

    bytes4 internal constant BORROW_SELECTOR = bytes4(keccak256("borrow(uint256,address)"));

    function setUp() public override {
        super.setUp();

        // Shared debt asset: assetTST (configured in EVaultTestBase)
        debtA = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        debtB = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );

        _configureDebtVault(debtA);
        _configureDebtVault(debtB);

        collateralVault = eTST2; // uses assetTST2

        // Price everything at 1 for simpler health math.
        oracle.setPrice(address(assetTST), unitOfAccount, 1e18);
        oracle.setPrice(address(assetTST2), unitOfAccount, 1e18);

        // LTVs for collateral.
        debtA.setLTV(address(collateralVault), 0.5e4, 0.6e4, 0);
        debtB.setLTV(address(collateralVault), 0.5e4, 0.6e4, 0);

        rebalanceFeeRecipient = makeAddr("rebalanceFeeRecipient");
        rebalancer = new Rebalancer(admin, address(evc), rebalanceFeeRecipient, FEE_BPS);

        userPk = 0xA11CE;
        user = vm.addr(userPk);
        userSub = getSubAccount(user, 1);

        lp = makeAddr("lp");
        keeper = makeAddr("keeper");

        // Fund the owner with collateral (sub-accounts are not EOAs; owner deposits on their behalf).
        assetTST2.mint(user, 400e18);
        assetTST.mint(lp, 500e18);

        _provideLiquidity(lp, debtA, 250e18);
        _provideLiquidity(lp, debtB, 250e18);

        _enableAndDepositCollateral(user, user, debtA, 100e18);
        _enableAndDepositCollateral(user, userSub, debtB, 120e18);

        // Authorize the rebalancer for both accounts.
        vm.prank(user);
        evc.setAccountOperator(user, address(rebalancer), true);
        vm.prank(user);
        evc.setAccountOperator(userSub, address(rebalancer), true);
    }

    function testFuzz_rebalance_equalizes_health(uint256 borrowASeed, uint256 borrowBSeed) public {
        uint256 maxBorrowA = _maxHealthyBorrowAssets(debtA, user);
        uint256 maxBorrowB = _maxHealthyBorrowAssets(debtB, userSub);

        uint256 borrowA = bound(borrowASeed, 1e18, maxBorrowA);
        uint256 borrowB = bound(borrowBSeed, 1e18, maxBorrowB);

        vm.prank(user);
        debtA.borrow(borrowA, user);

        // Borrow on behalf of the sub-account through the owner via EVC.
        vm.prank(user);
        evc.call(address(debtB), userSub, 0, abi.encodeWithSelector(BORROW_SELECTOR, borrowB, user));

        uint256 hfA = _health(user, debtA);
        uint256 hfB = _health(userSub, debtB);
        vm.assume(hfA != hfB);

        (uint256 hfLow, uint256 hfHigh) = hfA < hfB ? (hfA, hfB) : (hfB, hfA);
        vm.assume(hfLow + 2 < hfHigh);

        uint256 trigger = (hfLow + hfHigh) / 2;

        uint256 totalDebtBefore = debtA.debtOf(user) + debtB.debtOf(userSub);
        uint256 feeBalBefore = assetTST.balanceOf(rebalanceFeeRecipient);

        Rebalancer.RebalanceParams memory params = Rebalancer.RebalanceParams({
            accountA: user,
            accountB: userSub,
            vaultA: debtA,
            vaultB: debtB,
            maxBorrow: type(uint256).max,
            minHealthFactor: 1e18
        });

        (uint256 repaid, uint256 feePaid) = _rebalanceWithSig(params, trigger, FEE_BPS);

        uint256 hfAfterA = _health(user, debtA);
        uint256 hfAfterB = _health(userSub, debtB);

        assertGe(hfAfterA, params.minHealthFactor);
        assertGe(hfAfterB, params.minHealthFactor);
        assertApproxEqRel(hfAfterA, hfAfterB, 5e15);

        uint256 expectedFee = Math.mulDiv(repaid, FEE_BPS, 10_000, Math.Rounding.Ceil);
        assertEq(feePaid, expectedFee);

        uint256 totalDebtAfter = debtA.debtOf(user) + debtB.debtOf(userSub);
        assertEq(totalDebtAfter, totalDebtBefore + feePaid);

        assertEq(assetTST.balanceOf(rebalanceFeeRecipient), feeBalBefore + feePaid);
    }

    function testFuzz_rebalance_respects_cap(uint256 borrowASeed, uint256 borrowBSeed, uint256 capSeed) public {
        uint256 maxBorrowA = _maxHealthyBorrowAssets(debtA, user);
        uint256 maxBorrowB = _maxHealthyBorrowAssets(debtB, userSub);

        uint256 borrowA = bound(borrowASeed, 1e18, maxBorrowA);
        uint256 borrowB = bound(borrowBSeed, 1e18, maxBorrowB);

        vm.prank(user);
        debtA.borrow(borrowA, user);

        vm.prank(user);
        evc.call(address(debtB), userSub, 0, abi.encodeWithSelector(BORROW_SELECTOR, borrowB, user));

        uint256 hfA = _health(user, debtA);
        uint256 hfB = _health(userSub, debtB);
        vm.assume(hfA != hfB);

        (uint256 hfLow, uint256 hfHigh) = hfA < hfB ? (hfA, hfB) : (hfB, hfA);
        vm.assume(hfLow + 2 < hfHigh);

        uint256 trigger = (hfLow + hfHigh) / 2;

        Rebalancer.RebalanceParams memory previewParams = Rebalancer.RebalanceParams({
            accountA: user,
            accountB: userSub,
            vaultA: debtA,
            vaultB: debtB,
            maxBorrow: type(uint256).max,
            minHealthFactor: 0
        });

        Rebalancer.PreviewResult memory preview = rebalancer.preview(previewParams);
        vm.assume(preview.moveAmount > 2e18);

        uint256 cap = bound(capSeed, 1e18, preview.moveAmount - 1);

        Rebalancer.RebalanceParams memory params = Rebalancer.RebalanceParams({
            accountA: user,
            accountB: userSub,
            vaultA: debtA,
            vaultB: debtB,
            maxBorrow: cap,
            minHealthFactor: 1e18
        });

        uint256 diffBefore = _absDiff(hfA, hfB);

        (uint256 repaid,) = _rebalanceWithSig(params, trigger, FEE_BPS);
        assertLe(repaid, cap);

        uint256 hfAfterA = _health(user, debtA);
        uint256 hfAfterB = _health(userSub, debtB);
        uint256 diffAfter = _absDiff(hfAfterA, hfAfterB);

        assertLe(diffAfter, diffBefore);
    }

    function test_invalidateNonce_disables_signature() public {
        vm.prank(user);
        debtA.borrow(40e18, user);

        vm.prank(user);
        evc.call(address(debtB), userSub, 0, abi.encodeWithSelector(BORROW_SELECTOR, 10e18, user));

        uint256 hfA = _health(user, debtA);
        uint256 hfB = _health(userSub, debtB);
        (uint256 hfLow, uint256 hfHigh) = hfA < hfB ? (hfA, hfB) : (hfB, hfA);
        vm.assume(hfLow + 2 < hfHigh);
        uint256 trigger = (hfLow + hfHigh) / 2;

        Rebalancer.RebalanceParams memory params = Rebalancer.RebalanceParams({
            accountA: user,
            accountB: userSub,
            vaultA: debtA,
            vaultB: debtB,
            maxBorrow: type(uint256).max,
            minHealthFactor: 1e18
        });

        uint256 nonce = rebalancer.nonces(user);
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = rebalancer.hashAuthorization(params, trigger, FEE_BPS, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(user);
        rebalancer.invalidateNonce(nonce + 1);

        vm.prank(keeper);
        vm.expectRevert(Rebalancer.E_InvalidNonce.selector);
        rebalancer.rebalanceWithSig(params, trigger, FEE_BPS, nonce, deadline, sig);
    }

    function test_rebalance_reverts_on_mismatched_assets() public {
        Rebalancer.RebalanceParams memory params = Rebalancer.RebalanceParams({
            accountA: user,
            accountB: userSub,
            vaultA: debtA,
            vaultB: collateralVault, // different asset
            maxBorrow: type(uint256).max,
            minHealthFactor: 0
        });

        vm.expectRevert(Rebalancer.DifferentDebtAsset.selector);
        rebalancer.preview(params);
    }

    function _rebalanceWithSig(Rebalancer.RebalanceParams memory params, uint256 triggerHealthFactor, uint16 maxFeeBps)
        internal
        returns (uint256 repaid, uint256 feePaid)
    {
        uint256 nonce = rebalancer.nonces(user);
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = rebalancer.hashAuthorization(params, triggerHealthFactor, maxFeeBps, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(keeper);
        (repaid, feePaid) = rebalancer.rebalanceWithSig(params, triggerHealthFactor, maxFeeBps, nonce, deadline, sig);
    }

    function _configureDebtVault(IEVault vault) internal {
        vault.setHookConfig(address(0), 0);
        vault.setInterestRateModel(address(new IRMTestDefault()));
        vault.setMaxLiquidationDiscount(0.2e4);
        vault.setFeeReceiver(feeReceiver);
        vault.setConfigFlags(CFG_EVC_COMPATIBLE_ASSET);
    }

    function _provideLiquidity(address provider, IEVault vault, uint256 amount) internal {
        vm.startPrank(provider);
        assetTST.approve(address(vault), amount);
        vault.deposit(amount, provider);
        vm.stopPrank();
    }

    function _enableAndDepositCollateral(address owner, address account, IEVault controller, uint256 amount) internal {
        vm.startPrank(owner);
        evc.enableController(account, address(controller));
        evc.enableCollateral(account, address(collateralVault));
        assetTST2.approve(address(collateralVault), amount);
        collateralVault.deposit(amount, account);
        vm.stopPrank();
    }

    function _maxHealthyBorrowAssets(IEVault vault, address account) internal view returns (uint256) {
        // unitOfAccount == debt asset in this test setup => collateralValue is directly comparable to debt asset units.
        (uint256 collateralValue, uint256 liabilityValue) = vault.accountLiquidity(account, false);
        assertEq(liabilityValue, 0);
        vm.assume(collateralValue > 1e18);
        return collateralValue - 1;
    }

    function _health(address account, IEVault vault) internal view returns (uint256) {
        (uint256 collateralValue, uint256 liabilityValue) = vault.accountLiquidity(account, false);
        if (liabilityValue == 0) return type(uint256).max;
        return collateralValue * 1e18 / liabilityValue;
    }

    function _absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
