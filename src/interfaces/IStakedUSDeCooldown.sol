pragma solidity ^0.8.0;

interface IStakedUSDeCooldown {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function cooldownAssets(uint256 assets) external returns (uint256 shares);
    function cooldownShares(uint256 shares) external returns (uint256 assets);
    function unstake(address receiver) external;
    function balanceOf(address account) external view returns (uint256);
}
