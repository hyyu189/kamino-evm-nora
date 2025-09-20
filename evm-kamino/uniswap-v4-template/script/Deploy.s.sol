// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {KaminoVault} from "../src/KaminoVault.sol";
import {UniswapV4Strategy} from "../src/UniswapV4Strategy.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

contract Deploy is Script {
    using CurrencyLibrary for Currency;

    address internal constant POOL_MANAGER = 0xC2e4247322741c48bCA831F2f0D463A56a35528a; // Sepolia

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock tokens
        MockERC20 token0 = new MockERC20("Token A", "TKA");
        MockERC20 token1 = new MockERC20("Token B", "TKB");

        console.log("Token0 deployed to:", address(token0));
        console.log("Token1 deployed to:", address(token1));

        // For this MVP, we'll use one of the tokens as the vault's asset
        // In a real scenario, this would likely be a stablecoin or major asset
        MockERC20 assetToken = token0;

        // Deploy KaminoVault
        KaminoVault vault = new KaminoVault(
            assetToken,
            "Kamino USDC/WETH Vault",
            "kUSDC-WETH",
            deployerAddress
        );
        console.log("KaminoVault deployed to:", address(vault));

        // Deploy UniswapV4Strategy
        uint24 rangeWidth = 50; // Example range width
        UniswapV4Strategy strategy = new UniswapV4Strategy(
            POOL_MANAGER,
            address(vault),
            rangeWidth,
            deployerAddress
        );
        console.log("UniswapV4Strategy deployed to:", address(strategy));

        // Configure the vault and strategy
        vault.setStrategy(address(strategy));
        console.log("Vault strategy set to:", address(strategy));

        // Define a pool key for the strategy
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: IHooks(address(0)) // No hooks for this example pool
        });
        strategy.setPool(poolKey);
        console.log("Strategy pool key set");

        vm.stopBroadcast();
    }
}