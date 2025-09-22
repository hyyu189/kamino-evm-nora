// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {KaminoVault} from "../src/KaminoVault.sol";
import {UniswapV4Strategy} from "../src/UniswapV4Strategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

contract Deploy is Script {
    using CurrencyLibrary for Currency;

    address internal constant POOL_MANAGER = 0xC2e4247322741c48bCA831F2f0D463A56a35528a; // Sepolia
    address internal constant WETH_SEPOLIA = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address internal constant USDC_SEPOLIA = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Using official Sepolia addresses instead of deploying mocks
        IERC20 token0 = IERC20(USDC_SEPOLIA);
        IERC20 token1 = IERC20(WETH_SEPOLIA);

        console.log("Using USDC (Token0) at:", address(token0));
        console.log("Using WETH (Token1) at:", address(token1));

        // The vault will manage USDC
        IERC20 assetToken = token0;

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