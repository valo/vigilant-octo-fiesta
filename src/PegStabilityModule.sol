pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {nUSD} from "./nUSD.sol";

/// @title PegStabilityModule
/// @notice Simplified PegStabilityModule with configurable fees and fee receiver.
contract PegStabilityModule is Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public constant BPS_SCALE = 100_00;
    uint256 public constant MAX_FEE_BPS = 50_00; // 50% in basis points
    uint256 public constant PRICE_SCALE = 1e18;

    nUSD public immutable synth;
    IERC20 public immutable underlying;
    /// @notice Price of one synth denominated in underlying, scaled by PRICE_SCALE regardless of token decimals.
    uint256 public immutable CONVERSION_PRICE;
    uint8 public immutable underlyingDecimals;

    address public feeRecipient;
    uint256 public toUnderlyingFeeBPS;
    uint256 public toSynthFeeBPS;

    uint256 internal immutable underlyingTo18Scale;

    error E_ZeroAddress();
    error E_FeeExceedsBPS();
    error E_ZeroConversionPrice();
    error E_UnsupportedDecimals();

    constructor(
        address _owner,
        address _synth,
        address _underlying,
        address _feeRecipient,
        uint256 _toUnderlyingFeeBPS,
        uint256 _toSynthFeeBPS,
        uint256 _conversionPrice
    ) Ownable(_owner) {
        if (_synth == address(0) || _underlying == address(0) || _feeRecipient == address(0)) {
            revert E_ZeroAddress();
        }
        if (_toUnderlyingFeeBPS > MAX_FEE_BPS || _toSynthFeeBPS > MAX_FEE_BPS) {
            revert E_FeeExceedsBPS();
        }
        if (_conversionPrice == 0) {
            revert E_ZeroConversionPrice();
        }

        synth = nUSD(_synth);
        underlying = IERC20(_underlying);
        underlyingDecimals = IERC20Metadata(_underlying).decimals();
        if (underlyingDecimals > 18) {
            revert E_UnsupportedDecimals();
        }
        feeRecipient = _feeRecipient;
        toUnderlyingFeeBPS = _toUnderlyingFeeBPS;
        toSynthFeeBPS = _toSynthFeeBPS;
        CONVERSION_PRICE = _conversionPrice;

        underlyingTo18Scale = 10 ** uint256(18 - underlyingDecimals);
    }

    function setFees(uint256 _toUnderlyingFeeBPS, uint256 _toSynthFeeBPS) external onlyOwner {
        if (_toUnderlyingFeeBPS > MAX_FEE_BPS || _toSynthFeeBPS > MAX_FEE_BPS) {
            revert E_FeeExceedsBPS();
        }
        toUnderlyingFeeBPS = _toUnderlyingFeeBPS;
        toSynthFeeBPS = _toSynthFeeBPS;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) revert E_ZeroAddress();
        feeRecipient = _feeRecipient;
    }

    function swapToUnderlyingGivenIn(uint256 amountIn, address receiver) external returns (uint256) {
        if (amountIn == 0) {
            return 0;
        }

        uint256 amountOut = quoteToUnderlyingGivenIn(amountIn);

        uint256 totalUnderlying = _denormalizeUnderlying(
            Math.mulDiv(amountIn, CONVERSION_PRICE, PRICE_SCALE, Math.Rounding.Floor), Math.Rounding.Floor
        );
        uint256 fee = totalUnderlying - amountOut;

        synth.burn(_msgSender(), amountIn);
        underlying.safeTransfer(receiver, amountOut);
        if (fee > 0) underlying.safeTransfer(feeRecipient, fee);

        return amountOut;
    }

    function swapToUnderlyingGivenOut(uint256 amountOut, address receiver) external returns (uint256) {
        if (amountOut == 0) {
            return 0;
        }
        uint256 amountIn = quoteToUnderlyingGivenOut(amountOut);

        uint256 totalUnderlying = _denormalizeUnderlying(
            Math.mulDiv(amountIn, CONVERSION_PRICE, PRICE_SCALE, Math.Rounding.Floor), Math.Rounding.Floor
        );
        uint256 fee = totalUnderlying - amountOut;

        synth.burn(_msgSender(), amountIn);
        underlying.safeTransfer(receiver, amountOut);
        if (fee > 0) underlying.safeTransfer(feeRecipient, fee);

        return amountIn;
    }

    function swapToSynthGivenIn(uint256 amountIn, address receiver) public virtual returns (uint256) {
        if (amountIn == 0) {
            return 0;
        }

        uint256 amountOut = quoteToSynthGivenIn(amountIn);

        underlying.safeTransferFrom(_msgSender(), address(this), amountIn);

        uint256 mintedUnderlying = _denormalizeUnderlying(
            Math.mulDiv(amountOut, CONVERSION_PRICE, PRICE_SCALE, Math.Rounding.Floor), Math.Rounding.Floor
        );
        uint256 fee = amountIn - mintedUnderlying;
        if (fee > 0) underlying.safeTransfer(feeRecipient, fee);

        synth.mint(receiver, amountOut);

        return amountOut;
    }

    function swapToSynthGivenOut(uint256 amountOut, address receiver) public virtual returns (uint256) {
        uint256 amountIn = quoteToSynthGivenOut(amountOut);
        if (amountIn == 0 || amountOut == 0) {
            return 0;
        }

        underlying.safeTransferFrom(_msgSender(), address(this), amountIn);

        uint256 mintedUnderlying = _denormalizeUnderlying(
            Math.mulDiv(amountOut, CONVERSION_PRICE, PRICE_SCALE, Math.Rounding.Floor), Math.Rounding.Floor
        );
        uint256 fee = amountIn - mintedUnderlying;
        if (fee > 0) underlying.safeTransfer(feeRecipient, fee);

        synth.mint(receiver, amountOut);

        return amountIn;
    }

    function quoteToUnderlyingGivenIn(uint256 amountIn) public view returns (uint256) {
        uint256 synthAfterFee = amountIn.mulDiv(BPS_SCALE - toUnderlyingFeeBPS, BPS_SCALE, Math.Rounding.Floor);
        uint256 normalizedUnderlying = synthAfterFee.mulDiv(CONVERSION_PRICE, PRICE_SCALE, Math.Rounding.Floor);
        return _denormalizeUnderlying(normalizedUnderlying, Math.Rounding.Floor);
    }

    function quoteToUnderlyingGivenOut(uint256 amountOut) public view returns (uint256) {
        uint256 normalizedUnderlying = _normalizeUnderlying(amountOut, Math.Rounding.Ceil);
        uint256 synthAfterFee = normalizedUnderlying.mulDiv(PRICE_SCALE, CONVERSION_PRICE, Math.Rounding.Ceil);
        return synthAfterFee.mulDiv(BPS_SCALE, BPS_SCALE - toUnderlyingFeeBPS, Math.Rounding.Ceil);
    }

    function quoteToSynthGivenIn(uint256 amountIn) public view returns (uint256) {
        uint256 normalizedUnderlying = _normalizeUnderlying(amountIn, Math.Rounding.Floor);
        uint256 normalizedAfterFee =
            normalizedUnderlying.mulDiv(BPS_SCALE - toSynthFeeBPS, BPS_SCALE, Math.Rounding.Floor);
        return normalizedAfterFee.mulDiv(PRICE_SCALE, CONVERSION_PRICE, Math.Rounding.Floor);
    }

    function quoteToSynthGivenOut(uint256 amountOut) public view returns (uint256) {
        uint256 normalizedUnderlying = amountOut.mulDiv(CONVERSION_PRICE, PRICE_SCALE, Math.Rounding.Ceil);
        uint256 normalizedBeforeFee = normalizedUnderlying.mulDiv(BPS_SCALE, BPS_SCALE - toSynthFeeBPS, Math.Rounding.Ceil);
        return _denormalizeUnderlying(normalizedBeforeFee, Math.Rounding.Ceil);
    }

    function _normalizeUnderlying(uint256 amount, Math.Rounding rounding) internal view returns (uint256) {
        if (underlyingTo18Scale == 1) {
            return amount;
        }

        return Math.mulDiv(amount, underlyingTo18Scale, 1, rounding);
    }

    function _denormalizeUnderlying(uint256 amount, Math.Rounding rounding) internal view returns (uint256) {
        if (underlyingTo18Scale == 1) {
            return amount;
        }

        return Math.mulDiv(amount, 1, underlyingTo18Scale, rounding);
    }
}
