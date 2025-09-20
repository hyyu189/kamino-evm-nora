// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UniswapV4StrategyTestHelper, MockPoolManager} from "./UniswapV4Strategy.t.sol";
import {KaminoVault} from "../src/KaminoVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";

contract KaminoVaultIntegrationTest is UniswapV4StrategyTestHelper {
    function test_FullFlow_Deposit_Invest_Compound_Withdraw() public {
        // 1. User deposits into the vault
        uint256 depositAmount = 100e18;
        token0.mint(USER, depositAmount);
        vm.startPrank(USER);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, USER);
        vm.stopPrank();

        assertEq(vault.balanceOf(USER), depositAmount, "User should have shares in the vault");
        assertEq(asset.balanceOf(address(vault)), depositAmount, "Vault should have the assets");

        // 2. Vault owner invests the assets into the strategy
        token1.mint(address(strategy), depositAmount); // Provide the other token for the pair
        vault.invest();

        assertTrue(strategy.liquidity() > 0, "Strategy should have liquidity");
        assertEq(asset.balanceOf(address(vault)), 0, "Vault asset balance should be zero after investing");

        // 3. Simulate fees being generated in the pool
        uint256 feeAmount0 = 10e18;
        uint256 feeAmount1 = 5e18;
        token0.mint(address(poolManager), feeAmount0);
        token1.mint(address(poolManager), feeAmount1);
        poolManager.setFeeBalance(poolKey.currency0, feeAmount0);
        poolManager.setFeeBalance(poolKey.currency1, feeAmount1);

        // 4. Strategy owner compounds the fees
        uint128 liquidityBeforeCompound = strategy.liquidity();
        strategy.compound();
        uint128 liquidityAfterCompound = strategy.liquidity();
        assertTrue(liquidityAfterCompound > liquidityBeforeCompound, "Liquidity should increase after compounding");

        // 5. User withdraws their assets
        uint256 shares = vault.balanceOf(USER);
        uint256 userBalanceBefore = asset.balanceOf(USER);
        
        vm.startPrank(USER);
        vault.withdraw(shares, USER, USER);
        vm.stopPrank();

        uint256 userBalanceAfter = asset.balanceOf(USER);
        
        // User should get their initial deposit back, plus a share of the fees earned.
        // The exact amount depends on the price movement and swap fees, but it should be more than the initial deposit.
        uint256 expectedReturn = depositAmount + feeAmount0; // Simplified expectation
        assertApproxEqAbs(userBalanceAfter - userBalanceBefore, expectedReturn, 1e12, "User should receive initial deposit plus fees");
        
        assertEq(vault.balanceOf(USER), 0, "User should have no shares left in the vault");
    }
}
