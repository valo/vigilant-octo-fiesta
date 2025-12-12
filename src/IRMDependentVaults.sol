// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.25;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IEVault} from "euler-vault-kit/EVault/IEVault.sol";
import {IIRM} from "euler-vault-kit/InterestRateModels/IIRM.sol";
import {IPriceOracle} from "euler-vault-kit/interfaces/IPriceOracle.sol";

/// @title IRMDependentVaults
/// @author Valentin Mihov (valentin.mihov@gmail.com)
/// @notice Interest Rate Model that derives the current rate from a weighted average of dependent vaults.
/// Each dependent vault contributes proportionally to the USD value of its deposits, using the caller's oracle.
contract IRMDependentVaults is IIRM, Ownable {
    struct DependentVaultConfig {
        uint256 interestRate;
        uint256 index;
        bool exists;
    }

    event DependentVaultAdded(address indexed vault, uint256 interestRate);
    event DependentVaultRemoved(address indexed vault);
    event DependentVaultInterestRateUpdated(address indexed vault, uint256 interestRate);

    error E_DependentVaultAlreadyExists();
    error E_DependentVaultNotFound();

    address[] public dependentVaults;
    mapping(address => DependentVaultConfig) public dependentVaultConfigs;

    constructor() Ownable(msg.sender) {}

    /// @inheritdoc IIRM
    function computeInterestRate(address vault, uint256, uint256) external view override returns (uint256) {
        if (msg.sender != vault) revert E_IRMUpdateUnauthorized();

        return _computeWeightedRate(vault);
    }

    /// @inheritdoc IIRM
    function computeInterestRateView(address vault, uint256, uint256) external view override returns (uint256) {
        return _computeWeightedRate(vault);
    }

    /// @notice Add a new dependent vault with its fixed interest rate.
    /// @param vault Address of the dependent vault.
    /// @param interestRate Interest rate for the dependent vault in SPY (1e27 scale).
    function addDependentVault(address vault, uint256 interestRate) external onlyOwner {
        if (vault == address(0)) revert E_DependentVaultNotFound();
        if (dependentVaultConfigs[vault].exists) revert E_DependentVaultAlreadyExists();

        dependentVaultConfigs[vault] = DependentVaultConfig({interestRate: interestRate, index: dependentVaults.length, exists: true});
        dependentVaults.push(vault);

        emit DependentVaultAdded(vault, interestRate);
    }

    /// @notice Update the interest rate of an existing dependent vault.
    /// @param vault Address of the dependent vault.
    /// @param interestRate New interest rate in SPY (1e27 scale).
    function updateDependentVaultInterestRate(address vault, uint256 interestRate) external onlyOwner {
        DependentVaultConfig storage config = dependentVaultConfigs[vault];
        if (!config.exists) revert E_DependentVaultNotFound();

        config.interestRate = interestRate;
        emit DependentVaultInterestRateUpdated(vault, interestRate);
    }

    /// @notice Remove a dependent vault from weighting.
    /// @param vault Address of the dependent vault to remove.
    function removeDependentVault(address vault) external onlyOwner {
        DependentVaultConfig storage config = dependentVaultConfigs[vault];
        if (!config.exists) revert E_DependentVaultNotFound();

        uint256 index = config.index;
        uint256 lastIndex = dependentVaults.length - 1;

        if (index != lastIndex) {
            address lastVault = dependentVaults[lastIndex];
            dependentVaults[index] = lastVault;
            dependentVaultConfigs[lastVault].index = index;
        }

        dependentVaults.pop();
        delete dependentVaultConfigs[vault];

        emit DependentVaultRemoved(vault);
    }

    /// @notice Return the number of dependent vaults.
    function dependentVaultsLength() external view returns (uint256) {
        return dependentVaults.length;
    }

    function _computeWeightedRate(address vault) internal view returns (uint256) {
        if (dependentVaults.length == 0) return 0;

        IEVault callingVault = IEVault(vault);
        IPriceOracle oracle = IPriceOracle(callingVault.oracle());
        address unitOfAccount = callingVault.unitOfAccount();

        uint256 totalValue;
        uint256 weightedSum;

        for (uint256 i; i < dependentVaults.length; ++i) {
            address dependentVault = dependentVaults[i];
            DependentVaultConfig memory config = dependentVaultConfigs[dependentVault];

            uint256 assets = IEVault(dependentVault).totalAssets();
            if (assets == 0) continue;

            address asset = IEVault(dependentVault).asset();
            uint256 valueInUnit = oracle.getQuote(assets, asset, unitOfAccount);
            if (valueInUnit == 0) continue;

            totalValue += valueInUnit;
            weightedSum += Math.mulDiv(valueInUnit, config.interestRate, 1);
        }

        if (totalValue == 0) return 0;

        return weightedSum / totalValue;
    }
}
