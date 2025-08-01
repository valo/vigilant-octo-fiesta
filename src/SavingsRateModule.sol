// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

/// @title SavingsRateModule
/// @notice ERC4626 vault that drips donated tokens to depositors over time. Based on the Ethena
/// savings vault pattern where donations are streamed at a constant rate.
/// @dev Do NOT use with fee on transfer or rebasing tokens.
contract SavingsRateModule is ERC4626 {
    using Math for uint256;

    uint8 internal constant UNLOCKED = 1;
    uint8 internal constant LOCKED = 2;

    /// @notice Virtual shares and assets to avoid fee on the first deposit.
    uint256 internal constant VIRTUAL_AMOUNT = 1e6;
    /// @notice Minimum shares required before donations can be gulped.
    uint256 internal constant MIN_SHARES_FOR_GULP = VIRTUAL_AMOUNT * 10;

    /// @notice Duration over which each donation is streamed.
    uint256 public smearDuration;

    /// @notice Last timestamp when interest was dripped into the vault.
    uint256 public lastDrip;
    /// @notice Amount of tokens left to distribute.
    uint256 public undistributed;
    /// @notice Current distribution rate per second.
    uint256 public dripRate;

    /// @notice Reentrancy lock.
    uint8 internal locked;

    /// @notice Total assets accounted for excluding undistributed interest.
    uint256 internal _totalAssetsStored;

    /// ERRORS ///
    error Reentrancy();

    /// EVENTS ///
    event Gulped(uint256 donated, uint256 undistributed);
    event Dripped(uint256 accrued, uint256 undistributed);

    constructor(IERC20 asset_, string memory name_, string memory symbol_, uint256 _smearDuration)
        ERC20(name_, symbol_)
        ERC4626(asset_)
    {
        smearDuration = _smearDuration;
        lastDrip = block.timestamp;
        locked = UNLOCKED;
    }

    /// @notice Total assets including any accrued interest.
    function totalAssets() public view override returns (uint256) {
        return _totalAssetsStored + interestAccrued();
    }

    modifier nonReentrant() {
        if (locked == LOCKED) revert Reentrancy();
        locked = LOCKED;
        _;
        locked = UNLOCKED;
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256) {
        return assets.mulDiv(totalSupply() + VIRTUAL_AMOUNT, totalAssets() + VIRTUAL_AMOUNT, rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256) {
        return shares.mulDiv(totalAssets() + VIRTUAL_AMOUNT, totalSupply() + VIRTUAL_AMOUNT, rounding);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        _totalAssetsStored += assets;
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        _totalAssetsStored -= assets;
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256) {
        _updateDrip();
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256) {
        _updateDrip();
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256) {
        _updateDrip();
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public override nonReentrant returns (uint256) {
        _updateDrip();
        return super.redeem(shares, receiver, owner);
    }

    /// @notice Add any donated tokens to the streaming balance and update the drip rate.
    function gulp() public nonReentrant {
        _updateDrip();
        if (totalSupply() < MIN_SHARES_FOR_GULP) return;

        uint256 bal = IERC20(asset()).balanceOf(address(this));
        uint256 donated = bal - _totalAssetsStored - undistributed;
        if (donated == 0) return;

        undistributed += donated;
        dripRate = undistributed / smearDuration;
        lastDrip = block.timestamp;

        emit Gulped(donated, undistributed);
    }

    function _updateDrip() internal {
        if (block.timestamp <= lastDrip) return;
        uint256 elapsed = block.timestamp - lastDrip;
        uint256 accrued = elapsed * dripRate;
        if (accrued > undistributed) accrued = undistributed;
        if (accrued > 0) {
            undistributed -= accrued;
            _totalAssetsStored += accrued;
            emit Dripped(accrued, undistributed);
        }
        lastDrip = block.timestamp;
    }

    /// @notice Pending interest that has not yet been accounted for.
    function interestAccrued() public view returns (uint256) {
        if (block.timestamp <= lastDrip) return 0;
        uint256 elapsed = block.timestamp - lastDrip;
        uint256 accrued = elapsed * dripRate;
        if (accrued > undistributed) accrued = undistributed;
        return accrued;
    }
}
