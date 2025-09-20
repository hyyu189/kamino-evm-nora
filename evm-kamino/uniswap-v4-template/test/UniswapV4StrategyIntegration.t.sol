// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseScript} from "../script/base/BaseScript.sol";
import {LiquidityHelpers} from "../script/base/LiquidityHelpers.sol";
import {UniswapV4Strategy} from "../src/UniswapV4Strategy.sol";
import {KaminoVault} from "../src/KaminoVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

contract UniswapV4StrategyIntegrationTest is BaseScript, LiquidityHelpers {
    using CurrencyLibrary for Currency;

    // sepolia fork
    uint256 FORK_BLOCK = 6189500;

    address internal constant USDC = 0x94A9d9AC8A22534E3FacA422DE466b95853ba249;
    address internal constant WETH = 0x7b79995E5f793A07bC00C21412e50EaAE098e7F9;

    UniswapV4Strategy public strategy;
    KaminoVault public vault;
    IERC20 public asset;
    IERC20 public token0;
    IERC20 public token1;
    IPoolManager public poolManager;
    PoolKey public poolKey;
    
    address internal constant ADMIN = address(0x2);

    function setUp() public {
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"), FORK_BLOCK);

        poolManager = IPoolManager(POOL_MANAGER);
        asset = IERC20(USDC);
        token0 = IERC20(USDC);
        token1 = IERC20(WETH);

        vm.prank(ADMIN);
        vault = new KaminoVault(ERC20(address(asset)), "Kamino Vault", "kVault", ADMIN);
        vm.prank(ADMIN);
        strategy = new UniswapV4Strategy(address(poolManager), address(vault), 10, ADMIN);
        
        vm.prank(ADMIN);
        vault.setStrategy(address(strategy));

        poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        vm.prank(ADMIN);
        strategy.setPool(poolKey);
        
        // Deal some tokens
        deal(address(USDC), ADMIN, 10_000e6);
        deal(address(WETH), ADMIN, 10e18);
    }

    function test_Integration_Rebalance_And_Compound() public {
        uint256 depositAmount = 1000e6; // 1000 USDC
        
        vm.startPrank(ADMIN);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, ADMIN);

        // Manually provide the other token to the strategy for the first investment
        token1.transfer(address(strategy), 1e18);

        vault.invest();
        vm.stopPrank();

        uint128 initialLiquidity = strategy.liquidity();
        assertTrue(initialLiquidity > 0, "Should have liquidity after investing");

        // Simulate a swap to generate fees
        address swapper = makeAddr("swapper");
        deal(address(USDC), swapper, 1_000_000e6);
        vm.prank(swapper);
        swap(poolKey, true, 1_000_000e6);

        vm.warp(block.timestamp + 1 days);

        uint256 assetsBeforeCompound = strategy.totalAssets();
        assertTrue(assetsBeforeCompound > depositAmount, "Assets should grow from fees");

        vm.prank(ADMIN);
        strategy.compound();

        uint128 liquidityAfterCompound = strategy.liquidity();
        assertTrue(liquidityAfterCompound > initialLiquidity, "Liquidity should increase after compounding");
    }
}
