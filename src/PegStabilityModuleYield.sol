// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {PegStabilityModule} from "./PegStabilityModule.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IStakedUSDeCooldown} from "./interfaces/IStakedUSDeCooldown.sol";

/// @title PegStabilityModuleYield
/// @notice PegStabilityModule that stakes unused underlying into a vault with cooldown withdrawals.
contract PegStabilityModuleYield is PegStabilityModule {
    using SafeERC20 for IERC20;

    /// @notice staking vault used to earn yield on idle underlying
    IStakedUSDeCooldown public immutable stakingVault;

    /// @notice target amount of underlying to keep liquid for instant redemptions
    uint256 public liquidTarget;

    /// @param _synth address of the synthetic token
    /// @param _underlying address of the underlying asset
    /// @param _feeRecipient address that will receive fees
    /// @param _toUnderlyingFeeBPS fee when swapping synth -> underlying
    /// @param _toSynthFeeBPS fee when swapping underlying -> synth
    /// @param _conversionPrice price used for conversions
    /// @param _stakingVault address of the staking vault to deposit unused underlying
    /// @param _liquidTarget amount of underlying to keep liquid
    constructor(
        address _synth,
        address _underlying,
        address _feeRecipient,
        uint256 _toUnderlyingFeeBPS,
        uint256 _toSynthFeeBPS,
        uint256 _conversionPrice,
        address _stakingVault,
        uint256 _liquidTarget
    ) PegStabilityModule(_synth, _underlying, _feeRecipient, _toUnderlyingFeeBPS, _toSynthFeeBPS, _conversionPrice) {
        if (_stakingVault == address(0)) revert E_ZeroAddress();
        stakingVault = IStakedUSDeCooldown(_stakingVault);
        liquidTarget = _liquidTarget;
        // allow staking vault to pull underlying for deposits
        underlying.approve(_stakingVault, type(uint256).max);
    }

    /// @notice set the desired liquid target
    function setLiquidTarget(uint256 target) external onlyOwner {
        liquidTarget = target;
    }

    /// @notice stake any underlying held above the liquid target
    function stakeExcess() public {
        uint256 balance = underlying.balanceOf(address(this));
        if (balance > liquidTarget) {
            uint256 amount = balance - liquidTarget;
            stakingVault.deposit(amount, address(this));
        }
    }

    /// @notice begin cooldown to unstake `assets` amount of underlying from the vault
    function startUnstake(uint256 assets) external onlyOwner {
        stakingVault.cooldownAssets(assets);
    }

    /// @notice finalize pending cooldown and pull any available assets back to this contract
    function finalizeUnstake() public {
        stakingVault.unstake(address(this));
    }

    /// @inheritdoc PegStabilityModule
    function swapToSynthGivenIn(uint256 amountIn, address receiver) public override returns (uint256) {
        uint256 amountOut = super.swapToSynthGivenIn(amountIn, receiver);
        // stake any new underlying above the liquidity target
        stakeExcess();
        return amountOut;
    }

    /// @inheritdoc PegStabilityModule
    function swapToSynthGivenOut(uint256 amountOut, address receiver) public override returns (uint256) {
        uint256 amountIn = super.swapToSynthGivenOut(amountOut, receiver);
        // stake any new underlying above the liquidity target
        stakeExcess();
        return amountIn;
    }
    /// @notice amount of underlying currently in cooldown awaiting withdrawal
    /// @return amount of underlying currently in cooldown awaiting withdrawal

    function pendingCooldown() public view returns (uint256) {
        (, uint256 amount) = stakingVault.cooldowns(address(this));
        return amount;
    }
}
