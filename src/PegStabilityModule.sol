pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
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
    uint256 public immutable CONVERSION_PRICE;

    address public feeRecipient;
    uint256 public toUnderlyingFeeBPS;
    uint256 public toSynthFeeBPS;

    error E_ZeroAddress();
    error E_FeeExceedsBPS();
    error E_ZeroConversionPrice();

    constructor(
        address _synth,
        address _underlying,
        address _feeRecipient,
        uint256 _toUnderlyingFeeBPS,
        uint256 _toSynthFeeBPS,
        uint256 _conversionPrice
    ) Ownable(msg.sender) {
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
        feeRecipient = _feeRecipient;
        toUnderlyingFeeBPS = _toUnderlyingFeeBPS;
        toSynthFeeBPS = _toSynthFeeBPS;
        CONVERSION_PRICE = _conversionPrice;
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
        uint256 amountOut = quoteToUnderlyingGivenIn(amountIn);
        if (amountIn == 0 || amountOut == 0) {
            return 0;
        }

        uint256 totalUnderlying = Math.mulDiv(amountIn, CONVERSION_PRICE, PRICE_SCALE);
        uint256 fee = totalUnderlying - amountOut;

        synth.burn(_msgSender(), amountIn);
        underlying.safeTransfer(receiver, amountOut);
        if (fee > 0) underlying.safeTransfer(feeRecipient, fee);

        return amountOut;
    }

    function swapToUnderlyingGivenOut(uint256 amountOut, address receiver) external returns (uint256) {
        uint256 amountIn = quoteToUnderlyingGivenOut(amountOut);
        if (amountIn == 0 || amountOut == 0) {
            return 0;
        }

        uint256 totalUnderlying = Math.mulDiv(amountIn, CONVERSION_PRICE, PRICE_SCALE);
        uint256 fee = totalUnderlying - amountOut;

        synth.burn(_msgSender(), amountIn);
        underlying.safeTransfer(receiver, amountOut);
        if (fee > 0) underlying.safeTransfer(feeRecipient, fee);

        return amountIn;
    }

    function swapToSynthGivenIn(uint256 amountIn, address receiver) public virtual returns (uint256) {
        uint256 amountOut = quoteToSynthGivenIn(amountIn);
        if (amountIn == 0 || amountOut == 0) {
            return 0;
        }

        underlying.safeTransferFrom(_msgSender(), address(this), amountIn);

        uint256 mintedUnderlying = Math.mulDiv(amountOut, CONVERSION_PRICE, PRICE_SCALE);
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

        uint256 mintedUnderlying = Math.mulDiv(amountOut, CONVERSION_PRICE, PRICE_SCALE);
        uint256 fee = amountIn - mintedUnderlying;
        if (fee > 0) underlying.safeTransfer(feeRecipient, fee);

        synth.mint(receiver, amountOut);

        return amountIn;
    }

    function quoteToUnderlyingGivenIn(uint256 amountIn) public view returns (uint256) {
        return amountIn.mulDiv(
            (BPS_SCALE - toUnderlyingFeeBPS) * CONVERSION_PRICE, BPS_SCALE * PRICE_SCALE, Math.Rounding.Floor
        );
    }

    function quoteToUnderlyingGivenOut(uint256 amountOut) public view returns (uint256) {
        return amountOut.mulDiv(
            BPS_SCALE * PRICE_SCALE, (BPS_SCALE - toUnderlyingFeeBPS) * CONVERSION_PRICE, Math.Rounding.Ceil
        );
    }

    function quoteToSynthGivenIn(uint256 amountIn) public view returns (uint256) {
        return amountIn.mulDiv(
            (BPS_SCALE - toSynthFeeBPS) * PRICE_SCALE, BPS_SCALE * CONVERSION_PRICE, Math.Rounding.Floor
        );
    }

    function quoteToSynthGivenOut(uint256 amountOut) public view returns (uint256) {
        return amountOut.mulDiv(
            BPS_SCALE * CONVERSION_PRICE, (BPS_SCALE - toSynthFeeBPS) * PRICE_SCALE, Math.Rounding.Ceil
        );
    }
}
