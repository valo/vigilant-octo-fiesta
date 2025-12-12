// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {IIRM} from "euler-vault-kit/InterestRateModels/IIRM.sol";
import {IRMDependentVaults} from "../src/IRMDependentVaults.sol";
import {IPriceOracle} from "euler-vault-kit/interfaces/IPriceOracle.sol";

contract MockPriceOracle is IPriceOracle {
    mapping(address => uint256) public prices;

    function name() external pure override returns (string memory) {
        return "MockPriceOracle";
    }

    function setPrice(address base, uint256 priceInQuote) external {
        prices[base] = priceInQuote;
    }

    function getQuote(uint256 inAmount, address base, address) external view override returns (uint256) {
        return Math.mulDiv(inAmount, prices[base], 1e18);
    }

    function getQuotes(uint256 inAmount, address base, address)
        external
        view
        override
        returns (uint256 bidOutAmount, uint256 askOutAmount)
    {
        uint256 quote = Math.mulDiv(inAmount, prices[base], 1e18);
        return (quote, quote);
    }
}

contract MockVault {
    address public asset;
    address public unitOfAccount;
    address public oracle;
    uint256 public totalAssets;

    constructor(address asset_, address unitOfAccount_, address oracle_) {
        asset = asset_;
        unitOfAccount = unitOfAccount_;
        oracle = oracle_;
    }

    function setAsset(address asset_) external {
        asset = asset_;
    }

    function setUnitOfAccount(address unitOfAccount_) external {
        unitOfAccount = unitOfAccount_;
    }

    function setOracle(address oracle_) external {
        oracle = oracle_;
    }

    function setTotalAssets(uint256 totalAssets_) external {
        totalAssets = totalAssets_;
    }
}

contract IRMDependentVaultsTest is Test {
    uint8 internal constant MAX_VAULTS = 8;

    IRMDependentVaults irm;
    MockPriceOracle oracle;
    MockVault mainVault;
    MockVault dependentVaultA;
    MockVault dependentVaultB;

    address unitOfAccount = address(0xA);
    address assetA = address(0xB);
    address assetB = address(0xC);

    function setUp() public {
        oracle = new MockPriceOracle();
        mainVault = new MockVault(address(0xD), unitOfAccount, address(oracle));
        dependentVaultA = new MockVault(assetA, unitOfAccount, address(oracle));
        dependentVaultB = new MockVault(assetB, unitOfAccount, address(oracle));

        irm = new IRMDependentVaults();

        oracle.setPrice(assetA, 2e18); // 2 USD
        oracle.setPrice(assetB, 1e18); // 1 USD
    }

    function test_computeWeightedRate() public {
        dependentVaultA.setTotalAssets(100e18); // $200
        dependentVaultB.setTotalAssets(50e18); // $50

        irm.addDependentVault(address(dependentVaultA), 1e27);
        irm.addDependentVault(address(dependentVaultB), 3e27);

        uint256 expectedWeighted = (Math.mulDiv(200e18, 1e27, 1) + Math.mulDiv(50e18, 3e27, 1)) / 250e18;

        vm.prank(address(mainVault));
        uint256 computed = irm.computeInterestRate(address(mainVault), 0, 0);

        assertEq(computed, expectedWeighted);
    }

    function testGas_computeWeightedRate() public {
        dependentVaultA.setTotalAssets(100e18);
        dependentVaultB.setTotalAssets(50e18);

        irm.addDependentVault(address(dependentVaultA), 1e27);
        irm.addDependentVault(address(dependentVaultB), 3e27);

        vm.prank(address(mainVault));
        uint256 g0 = gasleft();
        irm.computeInterestRateView(address(mainVault), 0, 0);
        uint256 gasUsed = g0 - gasleft();

        emit log_named_uint("gas _computeWeightedRate", gasUsed);
    }

    function testFuzz_weightedRate_multipleVaults(uint8 numVaults, uint256 seedAmount, uint256 seedRate) public {
        numVaults = uint8(bound(numVaults, 1, MAX_VAULTS));

        uint256 expectedWeightedSum;
        uint256 expectedTotalValue;

        for (uint8 i; i < numVaults; ++i) {
            address asset = address(uint160(0x100 + i));
            MockVault dependentVault = new MockVault(asset, unitOfAccount, address(oracle));

            // Pseudorandom amounts/rates derived from seeds, bounded for safety.
            uint256 amount = bound(uint256(keccak256(abi.encode(seedAmount, i))), 1e6, 1e24);
            uint256 rate = bound(uint256(keccak256(abi.encode(seedRate, i))), 1e12, 5e27);
            uint256 price = (uint256(i) + 1) * 1e18; // distinct, simple scaling

            dependentVault.setTotalAssets(amount);
            oracle.setPrice(asset, price);

            irm.addDependentVault(address(dependentVault), rate);

            uint256 value = Math.mulDiv(amount, price, 1e18);
            expectedTotalValue += value;
            expectedWeightedSum += value * rate;
        }

        vm.prank(address(mainVault));
        uint256 computed = irm.computeInterestRate(address(mainVault), 0, 0);

        uint256 expected = expectedTotalValue == 0 ? 0 : expectedWeightedSum / expectedTotalValue;
        assertEq(computed, expected);
    }

    function test_removeDependentVault() public {
        dependentVaultA.setTotalAssets(100e18);
        dependentVaultB.setTotalAssets(50e18);

        irm.addDependentVault(address(dependentVaultA), 1e27);
        irm.addDependentVault(address(dependentVaultB), 3e27);
        irm.removeDependentVault(address(dependentVaultB));

        vm.prank(address(mainVault));
        uint256 computed = irm.computeInterestRate(address(mainVault), 0, 0);

        assertEq(computed, 1e27);
        assertEq(irm.dependentVaultsLength(), 1);
    }

    function testFuzz_addAndRemove(uint8 numVaults, uint8 removeIndexSeed) public {
        numVaults = uint8(bound(numVaults, 1, MAX_VAULTS));
        uint8 removeIndex = uint8(bound(removeIndexSeed, 0, numVaults - 1));

        address[] memory vaults = new address[](numVaults);
        uint256[] memory rates = new uint256[](numVaults);

        uint256 expectedTotalValue;
        uint256 expectedWeightedSum;

        for (uint8 i; i < numVaults; ++i) {
            address asset = address(uint160(0x200 + i));
            MockVault dependentVault = new MockVault(asset, unitOfAccount, address(oracle));

            uint256 amount = (i + 1) * 1e18;
            uint256 rate = (i + 1) * 1e25;
            uint256 price = (i + 2) * 1e18;

            dependentVault.setTotalAssets(amount);
            oracle.setPrice(asset, price);

            irm.addDependentVault(address(dependentVault), rate);

            vaults[i] = address(dependentVault);
            rates[i] = rate;

            uint256 value = Math.mulDiv(amount, price, 1e18);
            expectedTotalValue += value;
            expectedWeightedSum += value * rate;
        }

        // Remove one vault and adjust expectations
        address removed = vaults[removeIndex];
        uint256 removedValue = Math.mulDiv((removeIndex + 1) * 1e18, (removeIndex + 2) * 1e18, 1e18);
        expectedTotalValue -= removedValue;
        expectedWeightedSum -= removedValue * rates[removeIndex];

        irm.removeDependentVault(removed);

        // Verify array packing and indexes remain consistent
        uint256 remaining = irm.dependentVaultsLength();
        assertEq(remaining, numVaults - 1);

        for (uint256 i; i < remaining; ++i) {
            address vaultAddr = irm.dependentVaults(i);
            (uint256 rate,, bool exists) = irm.dependentVaultConfigs(vaultAddr);
            (, uint256 index, bool existsAgain) = irm.dependentVaultConfigs(vaultAddr);
            assertTrue(exists && existsAgain);
            assertEq(index, i);
            assertGt(rate, 0);
        }

        vm.prank(address(mainVault));
        uint256 computed = irm.computeInterestRate(address(mainVault), 0, 0);

        uint256 expected = expectedTotalValue == 0 ? 0 : expectedWeightedSum / expectedTotalValue;
        assertEq(computed, expected);
    }

    function test_returnsZeroWhenNoValue() public {
        irm.addDependentVault(address(dependentVaultA), 5e25);

        vm.prank(address(mainVault));
        uint256 computed = irm.computeInterestRate(address(mainVault), 0, 0);

        assertEq(computed, 0);
    }

    function test_revertsWhenCallerNotVault() public {
        irm.addDependentVault(address(dependentVaultA), 5e25);

        vm.expectRevert(IIRM.E_IRMUpdateUnauthorized.selector);
        irm.computeInterestRate(address(mainVault), 0, 0);
    }
}
