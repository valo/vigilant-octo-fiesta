// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IIRM} from "euler-vault-kit/InterestRateModels/IIRM.sol";

/// @title IRMStabilityFee
/// @author Valentin Mihov (valentin.mihov@gmail.com)
/// @notice Implementation of an interest rate model, where interest is fixed and set by an administrator.
contract IRMStabilityFee is IIRM, Ownable {
    /// @notice Base interest rate applied when utilization is equal zero
    uint256 public currentRate;

    constructor(uint256 currentRate_) Ownable(msg.sender) {
        currentRate = currentRate_;
    }

    /// @inheritdoc IIRM
    function computeInterestRate(address vault, uint256 cash, uint256 borrows)
        external
        view
        override
        returns (uint256)
    {
        if (msg.sender != vault) revert E_IRMUpdateUnauthorized();

        return currentRate;
    }

    /// @inheritdoc IIRM
    function computeInterestRateView(address vault, uint256 cash, uint256 borrows)
        external
        view
        override
        returns (uint256)
    {
        return currentRate;
    }

    function setCurrentRate(uint256 currentRate_) external onlyOwner {
        currentRate = currentRate_;
    }
}
