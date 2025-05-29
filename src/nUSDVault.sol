// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

import {VaultRegularBorrowable} from "evc-playground/vaults/open-zeppelin/VaultRegularBorrowable.sol";
import {IIRM} from "evc-playground/interfaces/IIRM.sol";
import {IPriceOracle} from "evc-playground/interfaces/IPriceOracle.sol";


/// @title nUSDVault
/// @custom:security-contact security@euler.xyz
/// @author Valentin Mihov (valentin.mihpv@gmail.com)
/// @notice A vault lending nUSD against over collateralized assets.
contract nUSDVault is VaultRegularBorrowable {
    constructor(        address _evc,
        IERC20 _asset,
        IIRM _irm,
        IPriceOracle _oracle,
        ERC20 _referenceAsset,
        string memory _name,
        string memory _symbol
    )
        VaultRegularBorrowable(
            _evc,
            _asset,
            _irm,
            _oracle,
            _referenceAsset,
            _name,
            _symbol
        )
    {
    }
}