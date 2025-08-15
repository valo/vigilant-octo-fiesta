pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {EnumerableSet} from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {SavingsRateModule} from "./SavingsRateModule.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";

/// @title nUSD
/// @custom:security-contact security@euler.xyz
/// @author Valentin Mihov (valentin.mihpv@gmail.com)
/// @notice A syntetix USD token which is backed by over collateralized assets.
// SPDX-License-Identifier: GPL-2.0-or-later
contract nUSD is ERC20, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    SavingsRateModule public dsrVault;
    mapping(address => uint256) public allocations;

    // Fee for interest withdrawal, expressed in basis points (1e4 = 100%)
    uint16 internal _interestFee;
    uint16 public constant MAX_INTEREST_FEE = 1e4; // 100% in basis points

    struct MinterData {
        uint128 capacity;
        uint128 minted;
    }

    /// @notice contains the minting capacity and minted amount for each minter.
    mapping(address => MinterData) public minters;
    /// @notice contains the list of addresses to ignore for the total supply.
    EnumerableSet.AddressSet internal ignoredForTotalSupply;

    /// @notice Emitted when the minting capacity for a minter is set.
    /// @param minter The address of the minter.
    /// @param capacity The capacity set for the minter.
    event MinterCapacitySet(address indexed minter, uint256 capacity);

    error E_CapacityReached();
    error E_InvalidInterestFee();

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) Ownable(msg.sender) {
        ignoredForTotalSupply.add(address(this));
    }

    function interestFee() public view returns (uint16) {
        return _interestFee;
    }

    function setInterestFee(uint16 interestFee_) external onlyOwner {
        if (interestFee_ > MAX_INTEREST_FEE) {
            revert E_InvalidInterestFee();
        }
        _interestFee = interestFee_;
    }

    function setDsrVault(SavingsRateModule dsrVault_) external onlyOwner {
        dsrVault = dsrVault_;
    }

    /// @notice Sets the minting capacity for a minter.
    /// @dev Can only be called by the owner of the contract.
    /// @param minter The address of the minter to set the capacity for.
    /// @param capacity The capacity to set for the minter.
    function setCapacity(address minter, uint128 capacity) external onlyOwner {
        minters[minter].capacity = capacity;
        emit MinterCapacitySet(minter, capacity);
    }

    /// @notice Mints a certain amount of tokens to the account.
    /// @param account The account to mint the tokens to.
    /// @param amount The amount of tokens to mint.
    function mint(address account, uint256 amount) external {
        address sender = _msgSender();
        MinterData memory minterCache = minters[sender];

        // Return early if the amount is 0 to prevent emitting possible spam events.
        if (amount == 0) {
            return;
        }

        if (
            amount > type(uint128).max - minterCache.minted
                || minterCache.capacity < uint256(minterCache.minted) + amount
        ) {
            revert E_CapacityReached();
        }

        minterCache.minted += uint128(amount); // safe to down-cast because amount <= capacity <= max uint128
        minters[sender] = minterCache;

        _mint(account, amount);
    }

    /// @notice Burns a certain amount of tokens from the accounts balance. Requires the account, except the owner to
    /// have an allowance for the sender.
    /// @param burnFrom The account to burn the tokens from.
    /// @param amount The amount of tokens to burn.
    function burn(address burnFrom, uint256 amount) external {
        address sender = _msgSender();
        MinterData memory minterCache = minters[sender];

        if (amount == 0) {
            return;
        }

        // The allowance check should be performed if the spender is not the account with the exception of the owner
        // burning from this contract.
        if (burnFrom != sender && !(burnFrom == address(this) && sender == owner())) {
            _spendAllowance(burnFrom, sender, amount);
        }

        // If burning more than minted, reset minted to 0
        unchecked {
            // down-casting is safe because amount < minted <= max uint128
            minterCache.minted = minterCache.minted > amount ? minterCache.minted - uint128(amount) : 0;
        }
        minters[sender] = minterCache;

        _burn(burnFrom, amount);
    }

    /// @notice Deposit cash from this contract into the attached vault.
    /// @dev Adds the vault to the list of accounts to ignore for the total supply.
    /// @param vault The vault to deposit the cash in.
    /// @param amount The amount of cash to deposit.
    /// @notice Deposit cash from this contract into the specified ERC4626 vault.
    /// @param vault The ERC4626-compliant vault to deposit into.
    /// @param amount The amount of cash to deposit.
    function allocate(address vault, uint256 amount) external onlyOwner {
        ignoredForTotalSupply.add(vault);
        allocations[vault] += amount;

        _approve(address(this), vault, amount);
        IERC4626(vault).deposit(amount, address(this));
    }

    /// @notice Withdraw cash from the attached vault to this contract.
    /// @param vault The vault to withdraw the cash from.
    /// @param amount The amount of cash to withdraw.
    /// @notice Withdraw cash from the specified ERC4626 vault back to this contract.
    /// @param vault The ERC4626-compliant vault to withdraw from.
    /// @param amount The amount of cash to withdraw.
    function deallocate(address vault, uint256 amount) external onlyOwner {
        allocations[vault] -= amount;

        IERC4626(vault).withdraw(amount, address(this), address(this));
    }

    /// @notice Returns accumulated interest in the specified ERC4626 vault.
    /// @param vault The ERC4626-compliant vault to query.
    function accumulatedInterest(address vault) external view returns (uint256) {
        uint256 currentShares = IERC4626(vault).balanceOf(address(this));

        require(currentShares > 0, "No shares in the vault");

        uint256 underlyingBalance = IERC4626(vault).convertToAssets(currentShares);
        uint256 allocatedAmount = allocations[vault];

        return underlyingBalance > allocatedAmount ? underlyingBalance - allocatedAmount : 0;
    }

    function withdrawInterest(uint256 interestToWithdraw, address vault) internal returns (uint256) {
        uint256 maxInterestToWithdraw = this.accumulatedInterest(vault);

        require(interestToWithdraw <= maxInterestToWithdraw, "Can't withdraw more than accumulated interest");

        IERC4626(vault).withdraw(interestToWithdraw, address(this), address(this));

        return interestToWithdraw;
    }

    function depositInterestInDSR(uint256 interestToWithdraw, address vault, address feesReceiver) external onlyOwner {
        require(allocations[vault] > 0, "No allocations for the vault");

        uint256 interestWithdrawn = withdrawInterest(interestToWithdraw, vault);
        if (interestWithdrawn == 0) {
            return; // No interest to deposit
        }

        uint256 fee = (interestWithdrawn * _interestFee) / MAX_INTEREST_FEE;
        uint256 netInterest = interestWithdrawn - fee;

        this.transfer(address(dsrVault), netInterest);
        dsrVault.gulp();

        this.transfer(feesReceiver, fee);
    }

    /// @notice Retrieves the message sender in the context of the EVC.
    /// @dev Overridden due to the conflict with the Context definition.
    /// @dev This function returns the account on behalf of which the current operation is being performed, which is
    /// either msg.sender or the account authenticated by the EVC.
    /// @return msgSender The address of the message sender.

    // -------- TotalSupply Management --------

    /// @notice Adds an account to the list of accounts to ignore for the total supply.
    /// @param account The account to add to the list.
    /// @return success True when the account was not on the list and was added. False otherwise.
    function addIgnoredForTotalSupply(address account) external onlyOwner returns (bool success) {
        return ignoredForTotalSupply.add(account);
    }

    /// @notice Removes an account from the list of accounts to ignore for the total supply.
    /// @param account The account to remove from the list.
    /// @return success True when the account was on the list and was removed. False otherwise.
    function removeIgnoredForTotalSupply(address account) external onlyOwner returns (bool success) {
        return ignoredForTotalSupply.remove(account);
    }

    /// @notice Checks if an account is ignored for the total supply.
    /// @param account The account to check.
    /// @return isIgnored True if the account is ignored for the total supply. False otherwise.
    function isIgnoredForTotalSupply(address account) external view returns (bool isIgnored) {
        return ignoredForTotalSupply.contains(account);
    }

    /// @notice Retrieves all the accounts ignored for the total supply.
    /// @return accounts List of accounts ignored for the total supply.
    function getAllIgnoredForTotalSupply() external view returns (address[] memory accounts) {
        return ignoredForTotalSupply.values();
    }

    /// @notice Retrieves the total supply of the token.
    /// @dev Overridden to exclude the ignored accounts from the total supply.
    /// @return total Total supply of the token.
    function totalSupply() public view override returns (uint256 total) {
        total = super.totalSupply();

        uint256 ignoredLength = ignoredForTotalSupply.length(); // cache for efficiency
        for (uint256 i = 0; i < ignoredLength; ++i) {
            total -= balanceOf(ignoredForTotalSupply.at(i));
        }
        return total;
    }
}
