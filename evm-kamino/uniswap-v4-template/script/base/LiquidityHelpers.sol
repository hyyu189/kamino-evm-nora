// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BaseScript} from "./BaseScript.sol";

abstract contract LiquidityHelpers is BaseScript {
    address constant POOL_MANAGER = 0xBe2455423823E66813251f2942F5972873a5A43a;

    function swap(PoolKey memory poolKey, bool zeroForOne, uint256 amount) internal {
        SwapParams memory params =
            SwapParams({zeroForOne: zeroForOne, amountSpecified: -int256(amount), sqrtPriceLimitX96: 0});

        IPoolManager(POOL_MANAGER).swap(poolKey, params, "");
    }

    function addLiquidity(IPoolManager manager, PoolKey memory key, int24 tickLower, int24 tickUpper, uint128 amount)
        internal
    {
        manager.modifyLiquidity(
            key, ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: int256(uint256(amount)), salt: bytes32(0)}), ""
        );
    }
}
