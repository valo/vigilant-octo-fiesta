// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ESynth} from "euler-vault-kit/Synths/ESynth.sol";
import {IEVault} from "euler-vault-kit/EVault/IEVault.sol";
import {EulerSavingsRate} from "euler-vault-kit/Synths/EulerSavingsRate.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

contract Allocator is Ownable {
    ESynth public esynth;
    EulerSavingsRate public dsrVault;
    mapping(address => uint256) public allocations;

    // Fee for interest withdrawal, expressed in basis points (1e4 = 100%)
    uint16 internal _interestFee;
    uint16 public constant MAX_INTEREST_FEE = 1e4; // 100% in basis points

    constructor(address _esynth, address _dsrVault, uint16 fee) Ownable(msg.sender) {
        esynth = ESynth(_esynth);
        dsrVault = EulerSavingsRate(_dsrVault);
        _interestFee = fee;
        esynth.approve(address(dsrVault), type(uint256).max);
    }

    function interestFee() public view returns (uint16) {
        return _interestFee;
    }

    function allocate(address vault, uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than zero");

        allocations[vault] += amount;

        esynth.mint(address(this), amount);
        esynth.approve(vault, amount);
        IEVault(vault).deposit(amount, address(this));
    }

    function deallocate(address vault, uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than zero");
        require(allocations[vault] >= amount, "Insufficient allocation");

        allocations[vault] -= amount;
        IEVault(vault).withdraw(amount, address(this), address(this));

        esynth.burn(address(this), amount);
    }


    function accumulatedInterest(address vault) external view returns (uint256) {
        IEVault esynthVault = IEVault(vault);

        uint256 currentShares = esynthVault.balanceOf(address(this));
        
        require(currentShares > 0, "No shares in the vault");

        uint256 underlyingBalance = esynthVault.convertToAssets(currentShares);
        uint256 allocatedAmount = allocations[vault];

        return underlyingBalance > allocatedAmount ? underlyingBalance - allocatedAmount : 0;
    }

    function withdrawInterest(address vault) internal returns (uint256) {
        uint256 interest = this.accumulatedInterest(vault);
        
        require(interest > 0, "No interest to withdraw");

        IEVault(vault).withdraw(interest, address(this), address(this));

        return interest;
    }

    function depositInterestInDSR(address vault) external onlyOwner {
        require(allocations[vault] > 0, "No allocations for the vault");

        uint256 interest = withdrawInterest(vault);
        uint256 fee = (interest * _interestFee) / MAX_INTEREST_FEE;
        uint256 netInterest = interest - fee;

        esynth.transfer(address(dsrVault), netInterest);
        dsrVault.gulp();
    }

    function withdrawFees(address to) external onlyOwner {
        uint256 balance = esynth.balanceOf(address(this));
        require(balance > 0, "No fees to withdraw");

        esynth.transfer(to, balance);
    }
}