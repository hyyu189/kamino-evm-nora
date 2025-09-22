// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IStrategy
 * @notice Interface for the strategy contract that manages the vault's assets.
 */
interface IStrategy {
    /**
     * @notice Returns the total value of assets managed by the strategy.
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Withdraws a specified amount of assets from the strategy to the vault.
     * @param amount The amount of assets to withdraw.
     * @return The amount of assets successfully withdrawn.
     */
    function withdraw(uint256 amount) external returns (uint256);

    /**
     * @notice Deposits assets from the vault into the strategy.
     */
    function deposit() external;
}

/**
 * @title KaminoVault
 * @author Nora AI
 * @notice An ERC-4626 vault to hold the underlying asset and manage user deposits/withdrawals.
 * This vault will be controlled by a strategy contract that deploys the assets into a Uniswap V4 pool.
 */
contract KaminoVault is ERC4626, Ownable {
    /**
     * @notice The address of the strategy contract that manages this vault's assets.
     */
    address public strategy;

    /**
     * @notice The performance fee in basis points (e.g., 1000 for 10%).
     */
    uint256 public performanceFeeBps;

    /**
     * @notice The total assets at the last fee collection point. This is used to
     * calculate performance fees only on the profit generated since the last cycle.
     */
    uint256 public lastTotalAssets;

    event StrategySet(address indexed newStrategy);
    event PerformanceFeeSet(uint256 newFeeBps);
    event FeesCollected(uint256 feeInAssets, uint256 newSharesMinted);

    /**
     * @param _asset The address of the underlying ERC20 token for the vault.
     * @param _name The name of the vault token.
     * @param _symbol The symbol of the vault token.
     */
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address initialOwner
    ) ERC4626(_asset) ERC20(_name, _symbol) Ownable(initialOwner) {
        lastTotalAssets = totalAssets();
    }

    /**
     * @notice Sets the strategy address. Only callable by the current owner.
     * @dev This also approves the strategy to spend the vault's assets.
     * @param _strategy The address of the strategy contract.
     */
    function setStrategy(address _strategy) external onlyOwner {
        require(_strategy != address(0), "KaminoVault: strategy cannot be zero address");
        strategy = _strategy;
        // Approve the strategy to spend all of our assets
        IERC20(asset()).approve(_strategy, type(uint256).max);
        emit StrategySet(_strategy);
    }

    /**
     * @notice Approves an address to spend the vault's assets.
     * @dev This function is not part of the ERC4626 standard and is added for test flexibility.
     * @param spender The address to approve.
     * @param amount The amount of assets to approve.
     */
    function approve(address spender, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        return super.approve(spender, amount);
    }

    /**
     * @notice Sets the performance fee. Only callable by the current owner.
     * @param _performanceFeeBps The new performance fee in basis points.
     */
    function setPerformanceFee(uint256 _performanceFeeBps) external onlyOwner {
        require(_performanceFeeBps <= 10000, "KaminoVault: fee cannot exceed 100%");
        performanceFeeBps = _performanceFeeBps;
        emit PerformanceFeeSet(_performanceFeeBps);
    }

    /**
     * @notice Overrides the totalAssets function to include assets managed by the strategy.
     * @return The total value of underlying assets managed by the vault and strategy.
     */
    function totalAssets() public view override returns (uint256) {
        uint256 assetsInVault = IERC20(asset()).balanceOf(address(this));
        uint256 assetsInStrategy = 0;
        if (strategy != address(0)) {
            assetsInStrategy = IStrategy(strategy).totalAssets();
        }
        return assetsInVault + assetsInStrategy;
    }

    /**
     * @notice Invests all available assets from the vault into the strategy.
     * @dev This function can only be called by the owner. It is intended to be
     * called periodically to invest new deposits.
     */
    function invest() external onlyOwner {
        if (strategy != address(0)) {
            IStrategy(strategy).deposit();
        }
    }

    /**
     * @notice Collects performance fees if there is a profit.
     * @dev This function can be called by anyone. It mints new shares to the owner
     * based on the profit generated since the last fee collection.
     */
    function collectFees() external {
        uint256 currentTotalAssets = totalAssets();
        if (currentTotalAssets > lastTotalAssets) {
            uint256 profit = currentTotalAssets - lastTotalAssets;
            uint256 feeInAssets = (profit * performanceFeeBps) / 10000;

            if (feeInAssets > 0) {
                // Mint shares equivalent to the fee amount to the owner
                uint256 sharesToMint = previewDeposit(feeInAssets);
                _mint(owner(), sharesToMint);
                emit FeesCollected(feeInAssets, sharesToMint);
            }
        }
        // Update the baseline for the next fee period, even if there's no profit
        lastTotalAssets = currentTotalAssets;
    }

    /**
     * @notice Internal function to handle withdrawals. It ensures that the vault
     * has enough assets to cover the withdrawal, pulling from the strategy if necessary.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        uint256 availableAssets = IERC20(asset()).balanceOf(address(this));
        if (availableAssets < assets) {
            uint256 needed = assets - availableAssets;
            // Ensure we don't try to withdraw more than exists in the strategy
            uint256 strategyAssets = IStrategy(strategy).totalAssets();
            if (needed > strategyAssets) {
                needed = strategyAssets;
            }
            IStrategy(strategy).withdraw(needed);
        }

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @dev Helper function for testing purposes only.
     */
    function setLastTotalAssetsForTest(uint256 _amount) external onlyOwner {
        lastTotalAssets = _amount;
    }
}