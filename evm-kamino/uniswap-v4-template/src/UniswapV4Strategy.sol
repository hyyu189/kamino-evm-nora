// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {KaminoVault, IStrategy} from "./KaminoVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
        /**ol.
 */
contract UniswapV4Strategy is IStrategy, Ownable, ReentrancyGuard, IUnlockCallback {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    error NotPoolManager();
    error InvalidAction();
    error ZeroAmount();
    error PoolNotSet();

    IPoolManager public immutable poolManager;
    KaminoVault public immutable vault;
    PoolKey public poolKey;
    PoolId public poolId;

    int24 public tickLower;
    int24 public tickUpper;
    uint128 public liquidity;
    uint24 public rangeWidth;

    // Actions for lockAcquired
    bytes32 private constant ACTION_DEPOSIT = keccak256("deposit");
    bytes32 private constant ACTION_REBALANCE = keccak256("rebalance");
    bytes32 private constant ACTION_COMPOUND = keccak256("compound");

    event Rebalanced(int24 newTickLower, int24 newTickUpper, uint128 newLiquidity);
    event Compounded(uint128 newLiquidity);
    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event PoolSet(PoolKey newPoolKey, PoolId newPoolId);
    event RangeWidthSet(uint24 newRangeWidth);

    constructor(address _poolManager, address _vault, uint24 _rangeWidth, address initialOwner) Ownable(initialOwner) {
        poolManager = IPoolManager(_poolManager);
        vault = KaminoVault(_vault);
        rangeWidth = _rangeWidth;
    }

    /**
     * @notice Sets the Uniswap V4 pool to be used by this strategy.
     * @param _poolKey The key identifying the Uniswap V4 pool.
     */
    function setPool(PoolKey memory _poolKey) external onlyOwner {
        poolKey = _poolKey;
        poolId = _poolKey.toId();
        emit PoolSet(_poolKey, poolId);
    }

    /**
     * @notice Updates the width of the liquidity range for rebalancing.
     * @param _newRangeWidth The new range width in ticks.
     */
    function setRangeWidth(uint24 _newRangeWidth) external onlyOwner {
        rangeWidth = _newRangeWidth;
        emit RangeWidthSet(_newRangeWidth);
    }

    /**
     * @notice Deposits assets from the vault into the Uniswap V4 pool.
     */
    function deposit() external override nonReentrant {
        uint256 amountToDeposit = IERC20(address(vault.asset())).balanceOf(address(vault));
        if (amountToDeposit == 0) {
            revert ZeroAmount();
        }
        if (Currency.unwrap(poolKey.currency0) == address(0)) {
            revert PoolNotSet();
        }
        poolManager.unlock(abi.encode(ACTION_DEPOSIT));
    }

    function emergencyWithdraw() external onlyOwner nonReentrant {
        if (liquidity > 0) {
            poolManager.modifyLiquidity(
                poolKey,
                ModifyLiquidityParams({
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: -int256(uint256(liquidity)),
                    salt: bytes32(0)
                }),
                bytes("")
            );
            liquidity = 0;
        }

        IERC20 token0 = IERC20(Currency.unwrap(poolKey.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(poolKey.currency1));
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        if (balance0 > 0) {
            token0.transfer(address(vault), balance0);
        }
        if (balance1 > 0) {
            token1.transfer(address(vault), balance1);
        }

        emit Withdrawn(balance0 + balance1);
    }

    function withdraw(uint256 amount) external override nonReentrant returns (uint256) {
        uint256 total = totalAssets();
        if (amount > total) {
            amount = total;
        }

        if (total == 0) {
            return 0;
        }

        uint128 liquidityToWithdraw = uint128((uint256(liquidity) * amount) / total);

        if (liquidityToWithdraw > 0) {
            poolManager.modifyLiquidity(
                poolKey,
                ModifyLiquidityParams({
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: -int256(int128(liquidityToWithdraw)),
                    salt: bytes32(0)
                }),
                bytes("")
            );
            liquidity -= liquidityToWithdraw;
        }

        uint256 assetBalance = IERC20(address(vault.asset())).balanceOf(address(this));
        if (assetBalance > 0) {
            IERC20(address(vault.asset())).transfer(address(vault), assetBalance);
        }

        emit Withdrawn(assetBalance);
        return assetBalance;
    }

    function rebalance() external onlyOwner nonReentrant {
        if (Currency.unwrap(poolKey.currency0) == address(0)) revert PoolNotSet();
        poolManager.unlock(abi.encode(ACTION_REBALANCE));
    }

    function compound() external onlyOwner nonReentrant {
        if (Currency.unwrap(poolKey.currency0) == address(0)) revert PoolNotSet();
        poolManager.unlock(abi.encode(ACTION_COMPOUND));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        bytes32 action = abi.decode(data, (bytes32));

        if (action == ACTION_DEPOSIT) {
            _deposit();
        } else if (action == ACTION_REBALANCE) {
            _rebalance();
        } else if (action == ACTION_COMPOUND) {
            _compound();
        } else {
            revert InvalidAction();
        }
        return "";
    }

    function _deposit() internal {
        uint256 amountToDeposit = IERC20(address(vault.asset())).balanceOf(address(vault));
        if (amountToDeposit > 0) {
            IERC20(address(vault.asset())).transferFrom(address(vault), address(this), amountToDeposit);
            emit Deposited(amountToDeposit);
        }

        IERC20 token0 = IERC20(Currency.unwrap(poolKey.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(poolKey.currency1));
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        (uint160 sqrtPriceX96, int24 currentTick,,) = poolManager.getSlot0(poolId);

        int24 newTickLower = _getNewTick(currentTick, poolKey.tickSpacing, rangeWidth, false);
        int24 newTickUpper = _getNewTick(currentTick, poolKey.tickSpacing, rangeWidth, true);

        uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(newTickLower),
            TickMath.getSqrtPriceAtTick(newTickUpper),
            balance0,
            balance1
        );

        if (newLiquidity > 0) {
            if (balance0 > 0) token0.approve(address(poolManager), balance0);
            if (balance1 > 0) token1.approve(address(poolManager), balance1);
            poolManager.modifyLiquidity(
                poolKey,
                ModifyLiquidityParams({
                    tickLower: newTickLower,
                    tickUpper: newTickUpper,
                    liquidityDelta: int256(uint256(newLiquidity)),
                    salt: bytes32(0)
                }),
                bytes("")
            );
        }

        tickLower = newTickLower;
        tickUpper = newTickUpper;
        liquidity = newLiquidity;

        emit Rebalanced(newTickLower, newTickUpper, newLiquidity);
    }

    function _rebalance() internal {
        if (liquidity > 0) {
            poolManager.modifyLiquidity(
                poolKey,
                ModifyLiquidityParams({
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: -int256(uint256(liquidity)),
                    salt: bytes32(0)
                }),
                bytes("")
            );
        }

        IERC20 token0 = IERC20(Currency.unwrap(poolKey.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(poolKey.currency1));
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        
        // Get the current tick from the pool
        (uint160 sqrtPriceX96, int24 currentTick,,) = poolManager.getSlot0(poolId);

        int24 newTickLower = _getNewTick(currentTick, poolKey.tickSpacing, rangeWidth, false);
        int24 newTickUpper = _getNewTick(currentTick, poolKey.tickSpacing, rangeWidth, true);

        uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(newTickLower),
            TickMath.getSqrtPriceAtTick(newTickUpper),
            balance0,
            balance1
        );

        if (newLiquidity > 0) {
            if (balance0 > 0) token0.approve(address(poolManager), balance0);
            if (balance1 > 0) token1.approve(address(poolManager), balance1);
            poolManager.modifyLiquidity(
                poolKey,
                ModifyLiquidityParams({
                    tickLower: newTickLower,
                    tickUpper: newTickUpper,
                    liquidityDelta: int256(uint256(newLiquidity)),
                    salt: bytes32(0)
                }),
                bytes("")
            );
        }

        uint256 remainingBalance0 = token0.balanceOf(address(this));
        if (remainingBalance0 > 0) {
            token0.transfer(address(vault), remainingBalance0);
        }
        uint256 remainingBalance1 = token1.balanceOf(address(this));
        if (remainingBalance1 > 0) {
            token1.transfer(address(vault), remainingBalance1);
        }

        tickLower = newTickLower;
        tickUpper = newTickUpper;
        liquidity = newLiquidity;

        emit Rebalanced(newTickLower, newTickUpper, newLiquidity);
    }

    function _compound() internal {
        // Step 1: Collect any accrued fees. This is done by calling modifyLiquidity with a delta of 0.
        // This triggers a settlement of fees, which are then transferred to this contract.
        if (liquidity > 0) {
            poolManager.modifyLiquidity(
                poolKey,
                ModifyLiquidityParams({
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: 0,
                    salt: bytes32(0)
                }),
                bytes("")
            );
        }

        // Step 2: Now that fees are collected as token balances, proceed with compounding.
        // First, withdraw the existing liquidity to consolidate all assets.
        if (liquidity > 0) {
            poolManager.modifyLiquidity(
                poolKey,
                ModifyLiquidityParams({
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: -int256(uint256(liquidity)),
                    salt: bytes32(0)
                }),
                bytes("")
            );
        }

        IERC20 token0 = IERC20(Currency.unwrap(poolKey.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(poolKey.currency1));
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        
        // Get the current price from the pool
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        // Recalculate liquidity with the new, larger balances (including compounded fees)
        uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            balance0,
            balance1
        );

        // Re-deposit the entire balance into the pool
        if (newLiquidity > 0) {
            if (balance0 > 0) token0.approve(address(poolManager), balance0);
            if (balance1 > 0) token1.approve(address(poolManager), balance1);
            poolManager.modifyLiquidity(
                poolKey,
                ModifyLiquidityParams({
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: int256(uint256(newLiquidity)),
                    salt: bytes32(0)
                }),
                bytes("")
            );
        }

        liquidity = newLiquidity;
        emit Compounded(newLiquidity);
    }

            function getPoolKey() external view returns (PoolKey memory) {
                return poolKey;
            }

            function totalAssets() public view override returns (uint256) {
                if (liquidity == 0) {
                    return IERC20(address(vault.asset())).balanceOf(address(this));
                }

                (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

                (uint256 amount0FromLiquidity, uint256 amount1FromLiquidity) = LiquidityAmounts.getAmountsForLiquidity(
                    sqrtPriceX96,
                    TickMath.getSqrtPriceAtTick(tickLower),
                    TickMath.getSqrtPriceAtTick(tickUpper),
                    liquidity
                );

                uint256 totalAmount0 = amount0FromLiquidity + IERC20(Currency.unwrap(poolKey.currency0)).balanceOf(address(this));
                uint256 totalAmount1 = amount1FromLiquidity + IERC20(Currency.unwrap(poolKey.currency1)).balanceOf(address(this));

                if (Currency.unwrap(poolKey.currency0) == address(vault.asset())) {
                    return totalAmount0;
                } else {
                    return totalAmount1;
                }
            }
            
            function _getNewTick(int24 currentTick, int24 tickSpacing, uint24 rangeWidth, bool isUpper) internal pure returns (int24) {
                int24 centeredTick = currentTick / tickSpacing;
                if (currentTick < 0 && currentTick % tickSpacing != 0) {
                    centeredTick--;
                }

                if (isUpper) {
                    return (centeredTick + int24(rangeWidth / 2)) * tickSpacing;
                } else {
                    return (centeredTick - int24(rangeWidth / 2)) * tickSpacing;
                }
            }
        }