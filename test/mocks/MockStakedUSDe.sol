// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IStakedUSDeCooldown} from "../../src/interfaces/IStakedUSDeCooldown.sol";

contract MockStakedUSDe is IStakedUSDeCooldown {
    IERC20 public immutable token;
    uint256 public immutable cooldownPeriod;

    struct Cooldown {
        uint256 end;
        uint256 amount;
    }

    mapping(address => uint256) public override balanceOf;
    mapping(address => Cooldown) public cooldowns;

    constructor(IERC20 _token, uint256 _cooldownPeriod) {
        token = _token;
        cooldownPeriod = _cooldownPeriod;
    }

    function deposit(uint256 assets, address receiver) external override returns (uint256 shares) {
        token.transferFrom(msg.sender, address(this), assets);
        shares = assets;
        balanceOf[receiver] += shares;
    }

    function cooldownAssets(uint256 assets) public override returns (uint256 shares) {
        require(balanceOf[msg.sender] >= assets, "insufficient");
        balanceOf[msg.sender] -= assets;
        shares = assets;
        Cooldown storage cd = cooldowns[msg.sender];
        cd.end = block.timestamp + cooldownPeriod;
        cd.amount += assets;
    }

    function cooldownShares(uint256 shares) external override returns (uint256 assets) {
        assets = cooldownAssets(shares);
    }

    function unstake(address receiver) external override {
        Cooldown storage cd = cooldowns[msg.sender];
        require(block.timestamp >= cd.end, "cooldown");
        uint256 amount = cd.amount;
        cd.amount = 0;
        token.transfer(receiver, amount);
    }
}
