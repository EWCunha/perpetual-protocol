// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// -----------------------------------------------------------------------
/// Imports
/// -----------------------------------------------------------------------

// ---- External imports ----

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/shared/interfaces/AggregatorV3Interface.sol";

// ---- Internal imports ----

import {IERC20Decimals} from "./interfaces/IERC20Decimals.sol";

/// -----------------------------------------------------------------------
/// Contract
/// -----------------------------------------------------------------------

/**
 * @title PerpEF: perpetual protocol developed by Ed and Frank.
 * @author @EWCunha and @Cheng-research
 * @notice Uses WBTC as indexed token.
 * @notice Assumes collateral token is a USD pegged stablecoin (i.e. USDC, USDT, DAI).
 */
contract PerpEF is ERC20 {
    /// -----------------------------------------------------------------------
    /// Custom errors
    /// -----------------------------------------------------------------------

    /// @dev error for when not enough allowance was given for this contract.
    error PerpEF__NotEnoughAllowance();

    /// @dev error for when maximum leverage is exceeded.
    error PerpEF__ExceedsMaxLeverage();

    /**
     * @dev error for when given amount exceeds amount of removable shares.
     * @param amount: amount of liquidity to be removed.
     * @param removableShares: amount of removables shares from liquidity.
     */
    error PerpEF__ExceedsRemovableShares(
        uint256 amount,
        uint256 removableShares
    );

    /// @dev error for when a position violates the liquidity reserves limit.
    error PerpEF__LiquidityReservesInvalidated();

    /// -----------------------------------------------------------------------
    /// Custom types
    /// -----------------------------------------------------------------------

    /// @dev specifies the position types
    enum PositionType {
        LONG,
        SHORT
    }

    /**
     * @dev struct for the position openings
     * @param positionType: type of the opened position (`LONG` or `SHORT`)
     * @param collateral: amount of the collateral to open position.
     * @param size: size amount of the position.
     */
    struct Position {
        PositionType positionType;
        uint256 collateral;
        uint256 size;
    }

    /// -----------------------------------------------------------------------
    /// Storage/state variables
    /// -----------------------------------------------------------------------

    uint256 internal s_maxLeverage;
    uint256 internal s_maxUtilizationPercentage;
    uint256 internal s_lockedLiquidity;
    uint256 internal s_depositedLiquidity;
    uint256 internal s_shortOpenInterest;
    uint256 internal s_longOpenInterestInTokens;
    IERC20 internal immutable i_collateralToken;
    IERC20 internal immutable i_wbtc;
    AggregatorV3Interface internal immutable i_priceOracle;

    mapping(address => Position) internal s_positions;

    uint256 internal immutable PRECISION;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    /**
     * @dev event for when liquidity is added.
     * @param provider: address of the liquidity provider.
     * @param amount: amount of liquidity provided.
     */
    event LiquidityAdded(address indexed provider, uint256 amount);

    /**
     * @dev event for when liquidity is removed.
     * @param provider: address of the liquidity provider.
     * @param amount: amount of liquidity removed.
     */
    event LiquidityRemoved(address indexed provider, uint256 amount);

    /**
     * @dev event for when a new position is opened.
     * @param trader: address of the trader that has opened the position.
     * @param positionType: type of the opened position.
     * @param collateral: amount of collateral given to open position.
     * @param size: size amount of the position.
     */
    event PositionOpened(
        address indexed trader,
        PositionType positionType,
        uint256 collateral,
        uint256 size
    );

    /// -----------------------------------------------------------------------
    /// Constructor logic
    /// -----------------------------------------------------------------------

    /**
     * @notice Constructor logic.
     * @dev Also initializes the ERC20 for liquidity shares.
     * @param collateralToken: address of the ERC20 token to be used as collateral.
     * @param wbtc: address of the ERC20 smart contract for WBTC.
     * @param priceOracle: address of the price oracle for WBTC.
     * @param maxLeverage: maximum allowed leverage.
     * @param maxUtilizationPercentage: maximum utilization percentage of liquidity in positions.
     */
    constructor(
        address collateralToken,
        address wbtc,
        address priceOracle,
        uint256 maxLeverage,
        uint256 maxUtilizationPercentage
    ) ERC20("Liquidity token PerpEF", "LTPerpEF") {
        i_collateralToken = IERC20(collateralToken);
        i_wbtc = IERC20(wbtc);
        i_priceOracle = AggregatorV3Interface(priceOracle);
        s_maxLeverage = maxLeverage;
        s_maxUtilizationPercentage = maxUtilizationPercentage;
        PRECISION = 10 ** IERC20Decimals(wbtc).decimals();
    }

    /// -----------------------------------------------------------------------
    /// Public/external state-change functions
    /// -----------------------------------------------------------------------

    /**
     * @notice Opens a position.
     * @param type_: position type. Either `LONG` or `SHORT`.
     * @param collateral: amount of collateral in collateral token.
     * @param size: size value for the position, in collateral token.
     */
    function newPosition(
        PositionType type_,
        uint256 collateral,
        uint256 size
    ) external {
        // Check if the position (size / collateral) exceeds the max leverage
        uint256 indexTokenPrice = getPrice();
        s_shortOpenInterest += size;
        s_longOpenInterestInTokens += _checkIfExceedsMaxLevarage(
            collateral,
            size,
            indexTokenPrice
        );

        // liquidity reserves valiation - Traders cannot utilize more than a configured percentage of the deposited liquidity.
        _validateLiquidityReserves(indexTokenPrice);

        // Collateral transfer
        if (
            i_collateralToken.allowance(msg.sender, address(this)) < collateral
        ) {
            revert PerpEF__NotEnoughAllowance();
        }

        // Store the position
        s_positions[msg.sender] = Position({
            positionType: type_,
            collateral: collateral,
            size: size
        });

        i_collateralToken.transferFrom(msg.sender, address(this), collateral);

        emit PositionOpened(msg.sender, type_, collateral, size);
    }

    /**
     * @notice Adds liquidity to pay gains.
     * @param amount: amount of tokens to add liquidity
     * @dev In this case, the liquidity token is WBTC
     */
    function addLiquidity(uint256 amount) external {
        if (i_wbtc.allowance(msg.sender, address(this)) < amount) {
            revert PerpEF__NotEnoughAllowance();
        }

        uint256 balance = i_wbtc.balanceOf(address(this));
        if (balance == 0) {
            _mint(msg.sender, amount);
        } else {
            _mint(msg.sender, (amount * totalSupply()) / balance);
        }

        i_wbtc.transferFrom(msg.sender, address(this), amount);

        emit LiquidityAdded(msg.sender, amount);
    }

    /**
     * @notice Removes liquidity.
     * @param amount: amount of tokens to remove liquidity
     * @dev In this case, the liquidity token is WBTC
     */
    function removeLiquidity(uint256 amount) external {
        uint256 removableShares = getRemovableShares(msg.sender);
        if (amount > removableShares) {
            revert PerpEF__ExceedsRemovableShares(amount, removableShares);
        }

        uint256 liquidityAmount = (amount * i_wbtc.balanceOf(address(this))) /
            totalSupply();

        _burn(msg.sender, amount);

        i_wbtc.transfer(msg.sender, liquidityAmount);

        emit LiquidityRemoved(msg.sender, liquidityAmount);
    }

    /// -----------------------------------------------------------------------
    /// Public/external view functions
    /// -----------------------------------------------------------------------

    /**
     * @notice Calculates the amount of shares that can be removed from liquidity.
     * @param user: address of the user.
     * @return - uint256 - amount of shares that can be removed from liquidiy.
     */
    function getRemovableShares(address user) public view returns (uint256) {
        uint256 userShares = balanceOf(user);
        uint256 lockedShares = (userShares * s_lockedLiquidity) /
            i_wbtc.balanceOf(address(this));

        return userShares - lockedShares;
    }

    /**
     * @notice Queries the liquidity token price.
     * @dev In this case, the liquidity token is WBTC
     * @return - uint256 - price of the liquidity token.
     */
    function getPrice() public view returns (uint256) {
        (, int256 answer, , , ) = i_priceOracle.latestRoundData();

        return uint256(answer);
    }

    /// -----------------------------------------------------------------------
    /// Private/internal view functions
    /// -----------------------------------------------------------------------

    /**
     * @dev Checks if given position exceeds maximum leverage.
     * @dev Reverts if it does.
     * @param collateral: amount of collateral in collateral token.
     * @param size: size value for the position, in collateral token.
     * @param indexTokenPrice: price of the index token. In this case, WBTC.
     */
    function _checkIfExceedsMaxLevarage(
        uint256 collateral,
        uint256 size,
        uint256 indexTokenPrice
    ) internal view returns (uint256) {
        uint256 sizeInCollateralToken = (size * indexTokenPrice) / PRECISION;
        if (sizeInCollateralToken > collateral * s_maxLeverage) {
            revert PerpEF__ExceedsMaxLeverage();
        }

        return sizeInCollateralToken;
    }

    /**
     * @dev Performs liquidity reserves valiation.
     * @dev Traders cannot utilize more than a configured percentage of the deposited liquidity.
     * @dev Reverts if that happens.
     * @param indexTokenPrice: price of the index token. In this case, WBTC.
     */
    function _validateLiquidityReserves(uint256 indexTokenPrice) internal view {
        if (
            !(s_shortOpenInterest +
                s_longOpenInterestInTokens *
                indexTokenPrice <
                s_depositedLiquidity * s_maxUtilizationPercentage)
        ) {
            revert PerpEF__LiquidityReservesInvalidated();
        }
    }
}
