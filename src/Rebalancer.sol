// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {IEVault} from "euler-vault-kit/EVault/IEVault.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {EIP712} from "openzeppelin-contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";

/// @title Rebalancer
/// @notice Shifts debt between two Euler vault accounts so their health factors converge.
/// @dev Designed for accounts sharing the same owner (EVC owner address), and the same debt asset.
///      Borrowing is performed on behalf of the safer account and repayment is performed by this contract.
contract Rebalancer is Ownable, EIP712 {
    using SafeERC20 for IERC20;

    uint256 public constant HF_SCALE = 1e18;
    uint16 public constant BPS_SCALE = 10_000;
    uint16 public constant MAX_FEE_BPS = 1_000;

    bytes4 internal constant BORROW_SELECTOR = bytes4(keccak256("borrow(uint256,address)"));
    bytes4 internal constant REPAY_SELECTOR = bytes4(keccak256("repay(uint256,address)"));

    bytes32 internal constant REBALANCE_AUTH_TYPEHASH = keccak256(
        "RebalanceAuthorization(address accountA,address accountB,address vaultA,address vaultB,uint256 maxBorrow,uint256 minHealthFactor,uint256 triggerHealthFactor,uint16 maxFeeBps,uint256 nonce,uint256 deadline)"
    );

    IEVC public immutable evc;

    address public feeRecipient;
    uint16 public feeBps;

    mapping(address owner => uint256 nonce) public nonces;

    error DifferentDebtAsset();
    error DifferentUnitOfAccount();
    error NoCommonOwner();
    error OwnerNotRegistered();
    error NoDebt();
    error NothingToDo();
    error HealthBelowMin();
    error TriggerNotMet();

    error E_ZeroAddress();
    error E_FeeExceedsMax();
    error E_FeeTooHigh();

    error E_SignatureExpired();
    error E_InvalidSignature();
    error E_InvalidNonce();

    error E_NotOwner();

    error E_UnexpectedRepay();

    event FeeConfigUpdated(address indexed feeRecipient, uint16 feeBps);
    event NonceInvalidated(address indexed owner, uint256 newNonce);

    event Rebalanced(
        address indexed initiator,
        address indexed fromAccount,
        address indexed toAccount,
        address fromVault,
        address toVault,
        uint256 amountMoved,
        uint256 feePaid
    );

    struct RebalanceParams {
        address accountA;
        address accountB;
        IEVault vaultA;
        IEVault vaultB;
        /// @notice Upper bound on the amount of debt to move. If zero, no cap is applied.
        uint256 maxBorrow;
        /// @notice Minimum post-rebalance health factor (scaled by 1e18). If zero, defaults to 1e18.
        uint256 minHealthFactor;
    }
    struct Position {
        uint256 collateralValue;
        uint256 liabilityValue;
        uint256 debtAssets;
        uint256 health;
    }

    struct Plan {
        IEVault riskyVault;
        IEVault safeVault;
        address riskyAccount;
        address safeAccount;
        uint256 delta;
    }

    struct PreviewResult {
        address riskyAccount;
        address safeAccount;
        IEVault riskyVault;
        IEVault safeVault;
        uint256 moveAmount;
        uint256 riskyHealth;
        uint256 safeHealth;
        uint256 targetHealth;
    }

    constructor(address owner_, address evc_, address feeRecipient_, uint16 feeBps_)
        Ownable(owner_)
        EIP712("DIBOR Rebalancer", "1")
    {
        if (evc_ == address(0) || feeRecipient_ == address(0)) revert E_ZeroAddress();
        if (feeBps_ > MAX_FEE_BPS) revert E_FeeExceedsMax();

        evc = IEVC(evc_);
        feeRecipient = feeRecipient_;
        feeBps = feeBps_;

        emit FeeConfigUpdated(feeRecipient_, feeBps_);
    }

    /// @notice Admin function to configure fees.
    function setFeeConfig(address feeRecipient_, uint16 feeBps_) external onlyOwner {
        if (feeRecipient_ == address(0)) revert E_ZeroAddress();
        if (feeBps_ > MAX_FEE_BPS) revert E_FeeExceedsMax();

        feeRecipient = feeRecipient_;
        feeBps = feeBps_;

        emit FeeConfigUpdated(feeRecipient_, feeBps_);
    }

    /// @notice Invalidate previously signed authorizations by setting a new nonce.
    function invalidateNonce(uint256 newNonce) external {
        nonces[msg.sender] = newNonce;
        emit NonceInvalidated(msg.sender, newNonce);
    }

    /// @notice Computes the EIP-712 digest for a rebalance authorization.
    function hashAuthorization(
        RebalanceParams calldata params,
        uint256 triggerHealthFactor,
        uint16 maxFeeBps,
        uint256 nonce,
        uint256 deadline
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                REBALANCE_AUTH_TYPEHASH,
                params.accountA,
                params.accountB,
                address(params.vaultA),
                address(params.vaultB),
                params.maxBorrow,
                params.minHealthFactor,
                triggerHealthFactor,
                maxFeeBps,
                nonce,
                deadline
            )
        );

        return _hashTypedDataV4(structHash);
    }

    /// @notice Purely computes the suggested movement between two positions without mutating state.

    function preview(RebalanceParams calldata params) external view returns (PreviewResult memory result) {
        _validateSharedConfig(params);

        (uint8 status, Plan memory plan, Position memory risky, Position memory safe) = _analyze(params);

        result.riskyAccount = plan.riskyAccount;
        result.safeAccount = plan.safeAccount;
        result.riskyVault = plan.riskyVault;
        result.safeVault = plan.safeVault;
        result.riskyHealth = risky.health;
        result.safeHealth = safe.health;

        if (status != ANALYSIS_OK) return result;

        result.moveAmount = plan.delta;

        uint256 targetLiabilityValue = Math.mulDiv(
            risky.liabilityValue, risky.debtAssets - plan.delta, risky.debtAssets, Math.Rounding.Ceil
        );
        result.targetHealth = _health(risky.collateralValue, targetLiabilityValue);
    }

    /// @notice Borrow from the safer account and repay the riskier one to equalize health factors.
    /// @dev Callable only by the EVC owner (registered owner address) of both accounts.
    function rebalance(RebalanceParams calldata params, uint256 triggerHealthFactor, uint16 maxFeeBps)
        external
        returns (uint256 repaid, uint256 feePaid)
    {
        address owner = _requireRegisteredCommonOwner(params);
        if (msg.sender != owner) revert E_NotOwner();

        return _rebalance(params, triggerHealthFactor, maxFeeBps);
    }

    /// @notice Execute a rebalance using a user-signed authorization.
    /// @dev Anyone can submit; signature authorizes the action and can be invalidated via `invalidateNonce`.
    function rebalanceWithSig(
        RebalanceParams calldata params,
        uint256 triggerHealthFactor,
        uint16 maxFeeBps,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external returns (uint256 repaid, uint256 feePaid) {
        if (deadline < block.timestamp) revert E_SignatureExpired();

        address owner = _requireRegisteredCommonOwner(params);

        if (nonce != nonces[owner]) revert E_InvalidNonce();

        bytes32 digest = hashAuthorization(params, triggerHealthFactor, maxFeeBps, nonce, deadline);
        if (!SignatureChecker.isValidSignatureNow(owner, digest, signature)) revert E_InvalidSignature();

        unchecked {
            nonces[owner] = nonce + 1;
        }

        return _rebalance(params, triggerHealthFactor, maxFeeBps);
    }

    uint8 internal constant ANALYSIS_OK = 0;
    uint8 internal constant ANALYSIS_EQUAL_HEALTH = 1;
    uint8 internal constant ANALYSIS_NO_DEBT = 2;
    uint8 internal constant ANALYSIS_ZERO_DELTA = 3;

    function _analyze(RebalanceParams calldata params)
        internal
        view
        returns (uint8 status, Plan memory plan, Position memory risky, Position memory safe)
    {
        Position memory posA = _position(params.vaultA, params.accountA);
        Position memory posB = _position(params.vaultB, params.accountB);

        bool aIsRiskier = posA.health < posB.health;

        if (aIsRiskier) {
            plan.riskyAccount = params.accountA;
            plan.safeAccount = params.accountB;
            plan.riskyVault = params.vaultA;
            plan.safeVault = params.vaultB;
            risky = posA;
            safe = posB;
        } else {
            plan.riskyAccount = params.accountB;
            plan.safeAccount = params.accountA;
            plan.riskyVault = params.vaultB;
            plan.safeVault = params.vaultA;
            risky = posB;
            safe = posA;
        }

        if (posA.health == posB.health) return (ANALYSIS_EQUAL_HEALTH, plan, risky, safe);

        if (risky.debtAssets == 0 || safe.debtAssets == 0) return (ANALYSIS_NO_DEBT, plan, risky, safe);

        uint256 delta = _computeDelta(risky, safe);

        uint256 cap = params.maxBorrow;
        if (cap == 0) cap = type(uint256).max;

        if (delta > cap) delta = cap;
        if (delta > risky.debtAssets) delta = risky.debtAssets;

        plan.delta = delta;

        if (delta == 0) return (ANALYSIS_ZERO_DELTA, plan, risky, safe);

        return (ANALYSIS_OK, plan, risky, safe);
    }

    function _plan(RebalanceParams calldata params, uint256 triggerHealthFactor) internal view returns (Plan memory plan) {
        (uint8 status, Plan memory computed, Position memory risky, Position memory safe) = _analyze(params);

        if (status == ANALYSIS_EQUAL_HEALTH || status == ANALYSIS_ZERO_DELTA) revert NothingToDo();
        if (status == ANALYSIS_NO_DEBT) revert NoDebt();

        if (!(risky.health < triggerHealthFactor && safe.health > triggerHealthFactor)) {
            revert TriggerNotMet();
        }

        plan = computed;
    }

    function _rebalance(RebalanceParams calldata params, uint256 triggerHealthFactor, uint16 maxFeeBps)
        internal
        returns (uint256 repaid, uint256 feePaid)
    {
        _validateSharedConfig(params);

        uint16 currentFeeBps = feeBps;
        if (currentFeeBps > maxFeeBps) revert E_FeeTooHigh();

        Plan memory plan = _plan(params, triggerHealthFactor);

        feePaid = currentFeeBps == 0
            ? 0
            : Math.mulDiv(plan.delta, currentFeeBps, BPS_SCALE, Math.Rounding.Ceil);

        _borrow(plan.safeVault, plan.safeAccount, plan.delta + feePaid);

        IERC20 debtAsset = IERC20(plan.riskyVault.asset());
        debtAsset.safeIncreaseAllowance(address(plan.riskyVault), plan.delta);

        repaid = _repay(plan.riskyVault, plan.riskyAccount, plan.delta);
        if (repaid != plan.delta) revert E_UnexpectedRepay();

        if (feePaid != 0) {
            debtAsset.safeTransfer(feeRecipient, feePaid);
        }

        uint256 minHealthFactor = params.minHealthFactor == 0 ? HF_SCALE : params.minHealthFactor;
        if (_position(plan.riskyVault, plan.riskyAccount).health < minHealthFactor) revert HealthBelowMin();
        if (_position(plan.safeVault, plan.safeAccount).health < minHealthFactor) revert HealthBelowMin();

        emit Rebalanced(
            msg.sender,
            plan.riskyAccount,
            plan.safeAccount,
            address(plan.riskyVault),
            address(plan.safeVault),
            repaid,
            feePaid
        );
    }


    function _borrow(IEVault vault, address account, uint256 amount) internal {
        evc.call(address(vault), account, 0, abi.encodeWithSelector(BORROW_SELECTOR, amount, address(this)));
    }

    function _repay(IEVault vault, address debtAccount, uint256 amount) internal returns (uint256 repaid) {
        bytes memory result =
            evc.call(address(vault), address(this), 0, abi.encodeWithSelector(REPAY_SELECTOR, amount, debtAccount));
        repaid = abi.decode(result, (uint256));
    }

    function _position(IEVault vault, address account) internal view returns (Position memory pos) {
        (pos.collateralValue, pos.liabilityValue) = vault.accountLiquidity(account, false);
        pos.debtAssets = vault.debtOf(account);
        pos.health = _health(pos.collateralValue, pos.liabilityValue);
    }

    function _health(uint256 collateralValue, uint256 liabilityValue) internal pure returns (uint256) {
        return liabilityValue == 0 ? type(uint256).max : Math.mulDiv(collateralValue, HF_SCALE, liabilityValue);
    }

    function _computeDelta(Position memory risky, Position memory safe) internal pure returns (uint256) {
        uint256 left = Math.mulDiv(safe.collateralValue, risky.debtAssets, 1);
        uint256 right = Math.mulDiv(risky.collateralValue, safe.debtAssets, 1);
        if (left <= right) return 0;

        uint256 numerator = left - right;
        uint256 denom = risky.collateralValue + safe.collateralValue;
        if (denom == 0) return 0;

        return numerator / denom;
    }

    function _requireRegisteredCommonOwner(RebalanceParams calldata params) internal view returns (address owner) {
        owner = evc.getAccountOwner(params.accountA);
        address ownerB = evc.getAccountOwner(params.accountB);

        if (owner == address(0) || ownerB == address(0)) revert OwnerNotRegistered();
        if (owner != ownerB) revert NoCommonOwner();
    }

    function _validateSharedConfig(RebalanceParams calldata params) internal view {
        if (params.vaultA.asset() != params.vaultB.asset()) revert DifferentDebtAsset();
        if (params.vaultA.unitOfAccount() != params.vaultB.unitOfAccount()) revert DifferentUnitOfAccount();
        if (!evc.haveCommonOwner(params.accountA, params.accountB)) revert NoCommonOwner();
    }
}
