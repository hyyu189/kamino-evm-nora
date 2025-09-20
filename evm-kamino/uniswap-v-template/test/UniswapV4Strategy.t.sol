// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {UniswapV4Strategy} from "../src/UniswapV4Strategy.sol";
import {KaminoVault} from "../src/KaminoVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

// Mock PoolManager for testing purposes
contract MockPoolManager {
    mapping(address => bytes) public unlockData;
    mapping(Currency => uint256) public currencyBalances;
    mapping(Currency => uint256) public feeBalances; // Simulate fees

    function setFeeBalance(Currency currency, uint256 amount) public {
        feeBalances[currency] = amount;
    }

    function unlock(bytes calldata data) external {
        IUnlockCallback(msg.sender).unlockCallback(data);
    }

    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes calldata)
        external
        returns (BalanceDelta, BalanceDelta)
    {
        if (params.liquidityDelta > 0) {
            uint256 balance0 = IERC20(Currency.unwrap(key.currency0)).balanceOf(msg.sender);
            uint256 balance1 = IERC20(Currency.unwrap(key.currency1)).balanceOf(msg.sender);
            currencyBalances[key.currency0] += balance0;
            currencyBalances[key.currency1] += balance1;
            if (balance0 > 0) {
                IERC20(Currency.unwrap(key.currency0)).transferFrom(msg.sender, address(this), balance0);
            }
            if (balance1 > 0) {
                IERC20(Currency.unwrap(key.currency1)).transferFrom(msg.sender, address(this), balance1);
            }
        } else if (params.liquidityDelta < 0) {
            uint256 amount0 = currencyBalances[key.currency0];
            uint256 amount1 = currencyBalances[key.currency1];
            currencyBalances[key.currency0] = 0;
            currencyBalances[key.currency1] = 0;
            IERC20(Currency.unwrap(key.currency0)).transfer(msg.sender, amount0);
            IERC20(Currency.unwrap(key.currency1)).transfer(msg.sender, amount1);
        } else { // liquidityDelta == 0, simulate fee collection
            uint256 fee0 = feeBalances[key.currency0];
            uint256 fee1 = feeBalances[key.currency1];
            if (fee0 > 0) {
                IERC20(Currency.unwrap(key.currency0)).transfer(msg.sender, fee0);
                feeBalances[key.currency0] = 0;
            }
            if (fee1 > 0) {
                IERC20(Currency.unwrap(key.currency1)).transfer(msg.sender, fee1);
                feeBalances[key.currency1] = 0;
            }
        }
        return (BalanceDelta.wrap(0), BalanceDelta.wrap(0));
    }

    function getSlot0(PoolId)
        external
        pure
        returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality)
    {
        return (79228162514264337593543950336, 100, 0, 0);
    }
}

contract UniswapV4StrategyTestHelper is Test {
    using CurrencyLibrary for Currency;

    UniswapV4Strategy public strategy;
    KaminoVault public vault;
    MockERC20 public asset;
    MockERC20 public token0;
    MockERC20 public token1;
    MockPoolManager public poolManager;
    PoolKey public poolKey;

    address internal constant USER = address(0x1);
    address internal constant ADMIN = address(0x2);

    function setUp() public virtual {
        token0 = new MockERC20("Mock Token 0", "MT0");
        token1 = new MockERC20("Mock Token 1", "MT1");

        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        asset = token0;
        poolManager = new MockPoolManager();

        token0.mint(address(poolManager), 1_000_000e18);
        token1.mint(address(poolManager), 1_000_000e18);

        vault = new KaminoVault(asset, "Kamino Vault", "kVault", ADMIN);
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
    }
}

contract UniswapV4StrategyTest is UniswapV4StrategyTestHelper {
    function test_Rebalance_And_Create_Position() public {
        uint256 depositAmount = 100e18;
        token0.mint(USER, depositAmount);

        vm.startPrank(USER);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, USER);
        vm.stopPrank();

        token1.mint(address(strategy), depositAmount);

        vm.prank(ADMIN);
        vault.invest();

        assertTrue(strategy.liquidity() > 0, "Liquidity should be greater than zero");
        assertEq(strategy.tickLower(), 40, "Tick lower should be set correctly");
        assertEq(strategy.tickUpper(), 160, "Tick upper should be set correctly");
    }

    function test_Compound_WithAccruedFees() public {
        uint256 depositAmount = 100e18;
        token0.mint(USER, depositAmount);
        vm.startPrank(USER);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, USER);
        vm.stopPrank();
        token1.mint(address(strategy), depositAmount);
        vm.prank(ADMIN);
        vault.invest();

        uint128 initialLiquidity = strategy.liquidity();
        uint256 feeAmount = 10e18;
        token0.mint(address(strategy), feeAmount);
        token1.mint(address(strategy), feeAmount);

        vm.warp(block.timestamp + 1);

        vm.prank(ADMIN);
        strategy.compound();
        assertTrue(strategy.liquidity() > initialLiquidity, "Liquidity should increase after compounding");
    }
    
    function test_EmergencyWithdraw_Full() public {
        uint256 depositAmount = 100e18;
        token0.mint(USER, depositAmount);
        vm.startPrank(USER);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, USER);
        vm.stopPrank();
        token1.mint(address(strategy), depositAmount);
        vm.prank(ADMIN);
        vault.invest();

        vm.warp(block.timestamp + 24 hours + 1);

        uint256 initialVaultBalance = token0.balanceOf(address(vault));
        vm.prank(ADMIN);
        strategy.emergencyWithdraw();

        assertEq(strategy.liquidity(), 0, "Liquidity should be zero after emergency withdrawal");
        assertTrue(token0.balanceOf(address(vault)) > initialVaultBalance, "Vault should receive token0");
    }
    
    function test_Withdraw_Partial() public {
        uint256 depositAmount = 100e18;
        token0.mint(USER, depositAmount);

        vm.startPrank(USER);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, USER);
        vm.stopPrank();

        uint256 shares = vault.balanceOf(USER);
        assertEq(shares, depositAmount, "Initial shares should equal deposit amount");

        vm.prank(ADMIN);
        vault.invest();
        assertTrue(strategy.liquidity() > 0, "Liquidity should be greater than zero after invest");

        uint256 userBalanceBefore = asset.balanceOf(USER);
        uint256 withdrawAmount = depositAmount / 2;

        vm.prank(USER);
        vault.withdraw(withdrawAmount, USER, USER);

        uint256 userBalanceAfter = asset.balanceOf(USER);
        assertEq(userBalanceAfter - userBalanceBefore, withdrawAmount, "User should receive the withdrawn assets");

        uint256 remainingShares = vault.balanceOf(USER);
        assertTrue(remainingShares < shares, "User shares should decrease after withdrawal");

        uint256 expectedTotalAssets = depositAmount - withdrawAmount;
        assertApproxEqAbs(vault.totalAssets(), expectedTotalAssets, 1e12, "Vault total assets should decrease");
    }

    function test_TotalAssets_AfterInvest() public {
        uint256 depositAmount = 100e18;
        token0.mint(USER, depositAmount);
        vm.startPrank(USER);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, USER);
        vm.stopPrank();

        token1.mint(address(strategy), depositAmount);
        vm.prank(ADMIN);
        vault.invest();
        
        uint256 totalAssets = strategy.totalAssets();
        assertTrue(totalAssets > 0, "Total assets in strategy should be greater than 0");
    }

    // Access Control Tests
    function test_SetPool_NotAdmin() public {
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(AccessControl.AccessControlUnauthorizedAccount.selector, USER, strategy.DEFAULT_ADMIN_ROLE())
        );
        strategy.setPool(poolKey);
    }

    function test_SetRangeWidth_NotAdmin() public {
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(AccessControl.AccessControlUnauthorizedAccount.selector, USER, strategy.DEFAULT_ADMIN_ROLE())
        );
        strategy.setRangeWidth(20);
    }

    function test_Rebalance_NotRebalancer() public {
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(AccessControl.AccessControlUnauthorizedAccount.selector, USER, strategy.REBALANCER_ROLE())
        );
        strategy.rebalance();
    }

    function test_Compound_NotRebalancer() public {
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(AccessControl.AccessControlUnauthorizedAccount.selector, USER, strategy.REBALANCER_ROLE())
        );
        strategy.compound();
    }

    function test_EmergencyWithdraw_NotAdmin() public {
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(AccessControl.AccessControlUnauthorizedAccount.selector, USER, strategy.DEFAULT_ADMIN_ROLE())
        );
        strategy.emergencyWithdraw();
    }

    // Callback Security Test
    function test_UnlockCallback_NotPoolManager() public {
        vm.prank(USER);
        vm.expectRevert("NotPoolManager()");
        strategy.unlockCallback(abi.encode(keccak256("rebalance")));
    }

    // Failure Scenarios
    function test_Fail_Rebalance_NoPoolSet() public {
        vm.prank(ADMIN);
        UniswapV4Strategy newStrategy = new UniswapV4Strategy(address(poolManager), address(vault), 10, ADMIN);
        
        vm.prank(ADMIN);
        newStrategy.grantRole(newStrategy.REBALANCER_ROLE(), ADMIN);
        
        vm.prank(ADMIN);
        vm.expectRevert("PoolNotSet()");
        newStrategy.rebalance();
    }

    function test_Fail_UnlockCallback_InvalidAction() public {
        vm.prank(address(poolManager));
        vm.expectRevert("InvalidAction()");
        strategy.unlockCallback(abi.encode(keccak256("invalidAction")));
    }
    
    function test_Fail_Deposit_ZeroAmount() public {
        vm.prank(ADMIN);
        vm.expectRevert("ZeroAmount()");
        strategy.deposit();
    }
    
    function test_Fail_Withdraw_NoLiquidity() public {
        vm.prank(address(vault));
        uint256 withdrawnAmount = strategy.withdraw(100e18);
        assertEq(withdrawnAmount, 0, "Withdrawn amount should be zero");
    }

    function test_Fail_EmergencyWithdraw_NoLiquidity() public {
        uint256 initialVaultBalance = token0.balanceOf(address(vault));
        vm.prank(ADMIN);
        strategy.emergencyWithdraw();
        assertEq(strategy.liquidity(), 0, "Liquidity should be zero");
        assertEq(token0.balanceOf(address(vault)), initialVaultBalance, "Vault balance should not change");
    }

    function test_Compound_WithFees() public {
        uint256 depositAmount = 100e18;
        token0.mint(USER, depositAmount);
        vm.startPrank(USER);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, USER);
        vm.stopPrank();
        token1.mint(address(strategy), depositAmount);
        
        vm.prank(ADMIN);
        vault.invest();

        uint128 initialLiquidity = strategy.liquidity();

        uint256 feeAmount0 = 10e18;
        uint256 feeAmount1 = 5e18;
        token0.mint(address(poolManager), feeAmount0);
        token1.mint(address(poolManager), feeAmount1);
        poolManager.setFeeBalance(poolKey.currency0, feeAmount0);
        poolManager.setFeeBalance(poolKey.currency1, feeAmount1);

        vm.prank(ADMIN);
        strategy.compound();

        uint128 newLiquidity = strategy.liquidity();
        assertTrue(newLiquidity > initialLiquidity, "Liquidity should increase after compounding with fees");
    }
}
