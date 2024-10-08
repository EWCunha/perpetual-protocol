// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// -----------------------------------------------------------------------
/// Imports
/// -----------------------------------------------------------------------

// ---- External imports ----

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
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
contract PerpEF is ERC20, Ownable {
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

    /// @dev error for when a position could not be found for calling trader.
    error PerpEF__PositionNotFound();

    /// @dev error for when a position could not be liquidated.
    error PerpEF__PositionNotLiquidatable();

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
        uint256 size; // this tracks the cost of the position, changes only when the position is realized (decreased), increased, or closed
        uint256 sizeInIndexTokens; // this changes only when the position is realized (decreased), increased, or closed.
        uint256 lastUpdateTimestamp;
        uint256 borrowingFee; // update every time there is a liquidation check
    }

    /// -----------------------------------------------------------------------
    /// Storage/state variables
    /// -----------------------------------------------------------------------

    uint256 internal s_maxLeverage;
    uint256 internal s_maxUtilizationPercentage;
    uint256 internal s_lockedLiquidity; // @follow-up how to increment this?
    uint256 internal s_depositedLiquidity;
    uint256 internal s_shortOpenInterest;
    uint256 internal s_longOpenInterestInTokens;
    uint256 internal s_liquidatorFee = 500; // over 10_000 (5%) @follow-up decide this
    uint256 internal s_borrowingPerSharePerSecond; // @follow-up decide this
    uint256 internal s_positionFee = 10; // over 10_000 (0.1%) // @follow-up decide this
    IERC20 internal immutable i_collateralToken;
    IERC20 internal immutable i_wbtc;
    AggregatorV3Interface internal immutable i_priceOracle;

    mapping(address => Position) internal s_positions;

    uint256 internal immutable TOKEN_PRECISION;
    uint256 internal immutable PRICE_PRECISION;
    uint256 internal constant FEE_PRECISION = 10_000;

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
     * @param size: size amount of the position, in index tokens.
     */
    event PositionOpened(
        address indexed trader,
        PositionType positionType,
        uint256 collateral,
        uint256 size
    );

    /**
     * @dev event for when a collateral is increased.
     * @param trader: address of the trader.
     * @param increaseInCollateral: amount of increased collateral.
     */
    event CollateralIncreased(
        address indexed trader,
        uint256 increaseInCollateral
    );

    event CollateralDecreased(
        address indexed trader,
        uint256 decreaseInCollateral
    );

    /**
     * @dev event for when size is increased.
     * @param trader: address of the trader.
     * @param increaseInSizeInCollateralToken: amount of increased size, in collateral token.
     * @param increaseInSizeInIndexToken: amount of increased size, in index token.
     */
    event SizeIncreased(
        address indexed trader,
        uint256 increaseInSizeInCollateralToken,
        uint256 increaseInSizeInIndexToken
    );

    event SizeDecreased(
        address indexed trader,
        uint256 sizeDecreasedInCollateralToken,
        uint256 sizeDecreasedInIndexToken
    );

    /**
     * @dev event for when a position is liquidated.
     * @param liquidator: address of the liquidator.
     * @param trader: address of the trader.
     */
    event PositionLiquidated(
        address indexed liquidator;
        address indexed trader,
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
    ) ERC20("Liquidity token PerpEF", "LTPerpEF") Ownable(msg.sender) {
        i_collateralToken = IERC20(collateralToken);
        i_wbtc = IERC20(wbtc);
        i_priceOracle = AggregatorV3Interface(priceOracle);
        s_maxLeverage = maxLeverage;
        s_maxUtilizationPercentage = maxUtilizationPercentage;
        TOKEN_PRECISION = 10 ** IERC20Decimals(wbtc).decimals();
        PRICE_PRECISION = 10 ** i_priceOracle.decimals();
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
        if (
            i_collateralToken.allowance(msg.sender, address(this)) < collateral
        ) {
            revert PerpEF__NotEnoughAllowance();
        }

        // Check if the position (size / collateral) exceeds the max leverage
        _checkIfExceedsMaxLevarageAndRevert(collateral, size);

        // liquidity reserves valiation - Traders cannot utilize more than a configured percentage of the deposited liquidity.
        uint256 indexTokenPrice = getPrice();
        uint256 sizeInIndexTokens = _convertToIndexTokens(
            size,
            indexTokenPrice
        );
        if (type_ == PositionType.SHORT) {
            _validateLiquidityReserves(indexTokenPrice, size, 0);
            s_shortOpenInterest += size;
        } else {
            _validateLiquidityReserves(indexTokenPrice, 0, sizeInIndexTokens);
            s_longOpenInterestInTokens += sizeInIndexTokens;
        }

        // Store the position
        s_positions[msg.sender] = Position({
            positionType: type_,
            collateral: collateral,
            size: size,
            sizeInIndexTokens: sizeInIndexTokens,
            lastUpdateTimestamp: block.timestamp,
            borrowingFee: 0
        });

        // Collateral transfer
        i_collateralToken.transferFrom(msg.sender, address(this), collateral);

        emit PositionOpened(msg.sender, type_, collateral, size);
    }

    /**
     * @notice Increases collateral of a position.
     * @param collateralAmountToIncrease: amount of collateral do be increased, in collateral token.
     */
    function increaseCollateral(uint256 collateralAmountToIncrease) external {
        if (
            i_collateralToken.allowance(msg.sender, address(this)) <
            collateralAmountToIncrease
        ) {
            revert PerpEF__NotEnoughAllowance();
        }

        Position storage position = s_positions[msg.sender];
        if (position.collateral == 0) {
            revert PerpEF__PositionNotFound();
        }
        _checkIfExceedsMaxLevarageAndRevert(
            position.collateral + collateralAmountToIncrease,
            _convertToCollateralToken(position.sizeInIndexTokens, getPrice()) // real-time worth of the position in collateral token
        );
        uint256 indexTokenPrice = getPrice();

        /* @follow-up: this is not used, should we remove it?
        uint256 sizeInIndexTokens = _convertToIndexTokens(
            position.size,
            indexTokenPrice
        );
        */

        // @follow-up: here wre are not increasing the size, so we can keep both values as 0
        _validateLiquidityReserves(indexTokenPrice, 0, 0);

        position.collateral += collateralAmountToIncrease;

        // Collateral transfer
        i_collateralToken.transferFrom(
            msg.sender,
            address(this),
            collateralAmountToIncrease
        );

        emit CollateralIncreased(msg.sender, collateralAmountToIncrease);
    }

    function decreaseCollateral(uint256 collateralAmountToDecrease) external {
        // check if there is a opened position
        Position storage position = s_positions[msg.sender];
        if (position.collateral == 0) {
            revert PerpEF__PositionNotFound();
        }

        // check if the new position collateral exceeds max leverage, if exceeds, revert
        _checkIfExceedsMaxLevarageAndRevert(
            position.collateral - collateralAmountToDecrease,
            _convertToCollateralToken(position.sizeInIndexTokens, getPrice())
        );

        // update storage (Position)
        position.lastUpdateTimestamp = block.timestamp;
        position.collateral -= collateralAmountToDecrease;

        // transfer collateral to trader
        i_collateralToken.transfer(msg.sender, collateralAmountToDecrease);

        emit CollateralDecreased(msg.sender, collateralAmountToDecrease);
    }

    /**
     * @notice Increases size of a position.
     * @param sizeAmountToIncreaseInCollateralToken: amount to be increased in size, in collateral token.
     */
    function increaseSize(
        uint256 sizeAmountToIncreaseInCollateralToken
    ) external {
        Position storage position = s_positions[msg.sender];
        if (position.collateral == 0) {
            revert PerpEF__PositionNotFound();
        }

        // compare collateral with (real-time worth of the position in collateral token + sizeAmountToIncreaseInCollateralToken)
        _checkIfExceedsMaxLevarageAndRevert(
            position.collateral,
            _convertToCollateralToken(position.sizeInIndexTokens, getPrice()) +
                sizeAmountToIncreaseInCollateralToken
        );

        uint256 indexTokenPrice = getPrice();

        // @follow-up
        // think here the sizeInIndexTokens that already in the position should remain unchanged
        // and we should only calculate the sizeAmountToIncreaseInIndexTokens based on current price
        uint256 sizeAmountToIncreaseInIndexTokens = _convertToIndexTokens(
            sizeAmountToIncreaseInCollateralToken,
            indexTokenPrice
        );

        if (position.positionType == PositionType.SHORT) {
            _validateLiquidityReserves(
                indexTokenPrice,
                sizeAmountToIncreaseInCollateralToken,
                0
            );
            s_shortOpenInterest += sizeAmountToIncreaseInCollateralToken;
        } else {
            _validateLiquidityReserves(
                indexTokenPrice,
                0,
                sizeAmountToIncreaseInIndexTokens
            );
            s_longOpenInterestInTokens += sizeAmountToIncreaseInIndexTokens;
        }

        position.size += sizeAmountToIncreaseInCollateralToken; // Updating the cost of the position
        position.sizeInIndexTokens += sizeAmountToIncreaseInIndexTokens;

        emit SizeIncreased(
            msg.sender,
            sizeAmountToIncreaseInCollateralToken,
            sizeAmountToIncreaseInIndexTokens
        );
    }

    function decreaseSize(
        uint256 sizeAmountToDecreaseInCollateralToken
    ) external {
        // check if there is a opened position
        // check if the new position size exceeds max leverage, if not exceeds, it should not trigg liquidation
        // check if LONG or SHORT position
        // calculate position PnL
        // calulate realizable amount
        // update storage variables (Position) -> consider positionFee and borrowingFee
        // transfer realizable amount

        Position storage position = s_positions[msg.sender];
        if (position.collateral == 0) {
            revert PerpEF__PositionNotFound();
        }

        uint256 positionFee = (sizeAmountToDecreaseInCollateralToken *
            s_positionFee) / FEE_PRECISION;

        // compare collateral with (real-time worth of the position in collateral token - sizeAmountToIncreaseInCollateralToken)
        _checkIfExceedsMaxLevarageAndRevert(
            position.collateral - positionFee,
            _convertToCollateralToken(position.sizeInIndexTokens, getPrice()) -
                sizeAmountToDecreaseInCollateralToken
        );

        uint256 indexTokenPrice = getPrice();
        int256 PnL = _calculatePnL(position, indexTokenPrice);

        // Think the positionSize in the fomula means real-time worth of the position in collateral token
        int256 realizedPnL = PnL *
            int256(
                sizeAmountToDecreaseInCollateralToken /
                    _convertToCollateralToken(
                        position.sizeInIndexTokens,
                        getPrice()
                    )
            );

        uint256 sizeAmountToDecreaseInIndexTokens = _convertToIndexTokens(
            sizeAmountToDecreaseInCollateralToken,
            indexTokenPrice
        );

        // @follow-up consider fees
        // Think the positionSize in the fomula means real-time worth of the position in collateral token
        position.borrowingFee +=
            _convertToCollateralToken(position.sizeInIndexTokens, getPrice()) *
            (block.timestamp - position.lastUpdateTimestamp) *
            s_borrowingPerSharePerSecond;
        position.lastUpdateTimestamp = block.timestamp;
        position.size -= sizeAmountToDecreaseInCollateralToken; // updating the cost of the position
        position.sizeInIndexTokens -= sizeAmountToDecreaseInIndexTokens;
        position.collateral -= positionFee;

        if (realizedPnL < 0) {
            _checkIfExceedsMaxLevarageAndRevert(
                position.collateral - uint256(realizedPnL),
                _convertToCollateralToken(
                    position.sizeInIndexTokens,
                    getPrice()
                ) // real-time worth of the position in collateral token
            );
            position.collateral -= uint256(realizedPnL);
        } else if (realizedPnL > 0) {
            i_collateralToken.transfer(msg.sender, uint256(realizedPnL));
        }

        emit SizeDecreased(
            msg.sender,
            sizeAmountToDecreaseInCollateralToken,
            sizeAmountToDecreaseInIndexTokens
        );
    }

    function liquidate(address trader) external {
        // check if there is a opened position
        Position storage position = s_positions[trader];
        if (position.collateral == 0) {
            revert PerpEF__PositionNotFound();
        }

        // check if position is liquidatable
        if (!_checkIfExceedsMaxLevarage(
            position.collateral,
            _convertToCollateralToken(position.sizeInIndexTokens, getPrice())
            )) {
            revert PerpEF__PositionNotLiquidatable();
        }

        // liquidate position - size decreased by 100%
        uint256 sizeAmountToDecreaseInCollateralToken = _convertToCollateralToken(position.sizeInIndexTokens, getPrice());

        uint256 positionFee = (sizeAmountToDecreaseInCollateralToken *
            s_positionFee) / FEE_PRECISION;

        uint256 indexTokenPrice = getPrice();
        int256 PnL = _calculatePnL(position, indexTokenPrice);

        int256 realizedPnL = PnL;

        /*
        uint256 sizeAmountToDecreaseInIndexTokens = _convertToIndexTokens(
            sizeAmountToDecreaseInCollateralToken,
            indexTokenPrice
        );
        */

        position.borrowingFee +=
            _convertToCollateralToken(position.sizeInIndexTokens, getPrice()) *
            (block.timestamp - position.lastUpdateTimestamp) *
            s_borrowingPerSharePerSecond;
        position.lastUpdateTimestamp = block.timestamp;
        position.size -= sizeAmountToDecreaseInCollateralToken; // updating the cost of the position
        position.sizeInIndexTokens = 0;

        position.collateral -= positionFee;
        position.collateral -= borrowingFee; // Borrowing fee is deducted from the collateral since the position is being closed

        if (realizedPnL < 0) {
            position.collateral -= uint256(realizedPnL);
        } else if (realizedPnL > 0) {
            i_collateralToken.transfer(trader, uint256(realizedPnL));
        }

        // calculate liquidator fee -> deduce from the collateral
        uint256 liquidatorFee = (position.collateral *
            s_liquidatorFee) / FEE_PRECISION;

        // transfer liquidator fee to liquidator
        position.collateral -= liquidatorFee;
        i_collateralToken.transfer(msg.sender, liquidatorFee);

        // transfer remaining collateral to trader
        i_collateralToken.transfer(trader, position.collateral);

        // close the position
        delete s_positions[trader];

        emit PositionLiquidated(msg.sender, trader);
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

        s_depositedLiquidity += amount;
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

    /**
     * @notice Sets new maximum leverage permitted.
     * @param newMaxLeverage: new max leverage permitted.
     */
    function setMaxLeverage(uint256 newMaxLeverage) external onlyOwner {
        s_maxLeverage = newMaxLeverage;
    }

    /**
     * @notice Sets a new value for maximum liquidity utilization percentage.
     * @param newMaxUtilizationPercentage: new maxium liquidity utilization percentage.
     */
    function setMaxUtilizationPercentage(
        uint256 newMaxUtilizationPercentage
    ) external onlyOwner {
        s_maxUtilizationPercentage = newMaxUtilizationPercentage;
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

    /**
     * @notice Reads s_maxLeverage storage variable.
     * @return - uint256 - value of the maximum leverage allowed.
     */
    function getMaxLeverage() external view returns (uint256) {
        return s_maxLeverage;
    }

    /**
     * @notice Reads s_maxUtilizationPercentage storage variable.
     * @return - uint256 - value of the maximum liquidity utilization percentage.
     */
    function getMaxUtilizationPercentage() external view returns (uint256) {
        return s_maxUtilizationPercentage;
    }

    /**
     * @notice Reads s_lockedLiquidity storage variable.
     * @return - uint256 - amount of locked liquidity.
     */
    function getLockedLiquidity() external view returns (uint256) {
        return s_lockedLiquidity;
    }

    /**
     * @notice Reads s_depositedLiquidity storage variable.
     * @return - uint256 - amount of deposited liquidity.
     */
    function getDepositedLiquidity() external view returns (uint256) {
        return s_depositedLiquidity;
    }

    /**
     * @notice Reads s_shortOpenInterest storage variable.
     * @return - uint256 - sum of short open interests.
     */
    function getShortOpenInterest() external view returns (uint256) {
        return s_shortOpenInterest;
    }

    /**
     * @notice Reads s_longOpenInterestInTokens storage variable.
     * @return - uint256 - sum of long open interests, in index tokens.
     */
    function getLongOpenInterestInIndexTokens()
        external
        view
        returns (uint256)
    {
        return s_longOpenInterestInTokens;
    }

    /**
     * @notice Reads i_collateralToken immutable variable.
     * @return - IERC20 - interface of the ERC20 collateral token smart contract.
     */
    function getCollateralToken() external view returns (IERC20) {
        return i_collateralToken;
    }

    /**
     * @notice Reads i_wbtc immutable variable.
     * @return - IERC20 - interface of the ERC20 WBTC token smart contract.
     */
    function getWBTC() external view returns (IERC20) {
        return i_wbtc;
    }

    /**
     * @notice Reads i_priceOracle immutable variable.
     * @return - AggregatorV3Interface - interface of the price oracle smart contract.
     */
    function getPriceOracle() external view returns (AggregatorV3Interface) {
        return i_priceOracle;
    }

    /**
     * @notice Reads s_positions storage variable of given address.
     * @param trader: address of the trader.
     * @return - Position - data of the trader's position.
     */
    function getPosition(
        address trader
    ) external view returns (Position memory) {
        return s_positions[trader];
    }

    /**
     * @notice Reads TOKEN_PRECISION immutable variable.
     * @return - uint256 - precision of the index token (i.e. 10 ** token.decimals()).
     */
    function getTokenPrecision() external view returns (uint256) {
        return TOKEN_PRECISION;
    }

    /**
     * @notice Reads PRICE_PRECISION immutable variable.
     * @return - uint256 - precision of the price oracle (i.e. 10 ** oracle.decimals()).
     */
    function getPricePrecision() external view returns (uint256) {
        return PRICE_PRECISION;
    }

    /// -----------------------------------------------------------------------
    /// Private/internal view functions
    /// -----------------------------------------------------------------------

    /**
     * @dev Checks if given position exceeds maximum leverage.
     * @dev Reverts if it does.
     * @param collateral: amount of collateral in collateral token.
     * @param size: size value for the position, in collateral token.
     */
    function _checkIfExceedsMaxLevarageAndRevert(
        uint256 collateral,
        uint256 size
    ) internal view {
        if (_checkIfExceedsMaxLevarage(collateral, size)) {
            revert PerpEF__ExceedsMaxLeverage();
        }
    }

    function _checkIfExceedsMaxLevarage(
        uint256 collateral,
        uint256 size
    ) internal view returns (bool) {
        return size > collateral * s_maxLeverage;
    }

    function _calculatePnL(
        Position memory position,
        uint256 indexTokenPrice
    ) internal view returns (int256 PnL) {
        if (position.positionType == PositionType.LONG) {
            PnL =
                int256(
                    _convertToCollateralToken(
                        position.sizeInIndexTokens,
                        indexTokenPrice
                    )
                ) -
                int256(position.size); // @follow-up is this the right way to cast to int256? should be ok
        } else {
            PnL =
                int256(position.size) -
                int256(
                    _convertToCollateralToken(
                        position.sizeInIndexTokens,
                        indexTokenPrice
                    )
                ); // @follow-up is this the right way to cast to int256? shuold be ok
        }
    }

    /**
     * @dev Performs liquidity reserves valiation.
     * @dev Traders cannot utilize more than a configured percentage of the deposited liquidity.
     * @dev Reverts if that happens.
     * @param indexTokenPrice: price of the index token. In this case, WBTC.
     * @param size: size value for the position, in collateral token.
     * @param sizeInIndexTokens: size value for the position, in index token.
     */
    function _validateLiquidityReserves(
        uint256 indexTokenPrice,
        uint256 size,
        uint256 sizeInIndexTokens
    ) internal view {
        if (
            !((s_shortOpenInterest + size) +
                (s_longOpenInterestInTokens + sizeInIndexTokens) *
                indexTokenPrice <
                s_depositedLiquidity * s_maxUtilizationPercentage)
        ) {
            revert PerpEF__LiquidityReservesInvalidated();
        }
    }

    /**
     * @dev Converts given value to index token amount.
     * @param amountInCollateralToken: value to be converted.
     * @param tokenPrice: price of index token.
     * @return - uint256 - converted amount of index token.
     */
    function _convertToIndexTokens(
        uint256 amountInCollateralToken,
        uint256 tokenPrice
    ) internal view returns (uint256) {
        // ((USD * token_precision ) * (WBTC/USD * price_precision)) / (token_precision * price_precision) = WBTC
        return
            (amountInCollateralToken * tokenPrice) /
            (TOKEN_PRECISION * PRICE_PRECISION);
    }

    /**
     * @dev Converts given value to collateral token amount.
     * @param amountInIndexTokens: value to be converted.
     * @param tokenPrice: price of index token.
     * @return - uint256 - converted amount of collateral token.
     */
    function _convertToCollateralToken(
        uint256 amountInIndexTokens,
        uint256 tokenPrice
    ) internal view returns (uint256) {
        // @ follow-up: is this correct?
        return
            (amountInIndexTokens * TOKEN_PRECISION * PRICE_PRECISION) /
            tokenPrice;
    }
}
