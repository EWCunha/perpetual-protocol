// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

/// -----------------------------------------------------------------------
/// Imports
/// -----------------------------------------------------------------------

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/shared/interfaces/AggregatorV3Interface.sol";

/// -----------------------------------------------------------------------
/// Contract
/// -----------------------------------------------------------------------

contract PerpEC is ERC20 {
    /// -----------------------------------------------------------------------
    /// Custom errors
    /// -----------------------------------------------------------------------

    error PerpEC__NotEnoughAllowance();
    error PerpEC__ExceedsMaxLeverage();

    /// -----------------------------------------------------------------------
    /// Custom types
    /// -----------------------------------------------------------------------

    enum PositionType {
        LONG,
        SHORT
    }

    struct Position {
        PositionType positionType;
        uint256 collateral;
        uint256 size;
    }


    /// -----------------------------------------------------------------------
    /// Storage/state variables
    /// -----------------------------------------------------------------------

    uint256 internal s_lockedLiquidity;
    uint256 internal s_maxLeverage;
    IERC20 internal immutable i_collateralToken;
    IERC20 internal immutable i_wbtc;
    AggregatorV3Interface internal immutable i_priceOracle;

    mapping(address => Position) internal s_positions;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event LiquidityAdded(address indexed provider, uint256 amount);
    event LiquidityRemoved(address indexed provider, uint256 amount);
    event PositionOpened(address indexed trader, PositionType positionType, uint256 collateral, uint256 size);

    /// -----------------------------------------------------------------------
    /// Constructor logic
    /// -----------------------------------------------------------------------

    constructor(
        address collateralToken,
        address wbtc,
        address priceOracle,
        uint256 maxLeverage
    ) ERC20("Liquidity token PerpEC", "LTPerpEC") {
        i_collateralToken = IERC20(collateralToken);
        i_wbtc = IERC20(wbtc);
        i_priceOracle = AggregatorV3Interface(priceOracle);
        s_maxLeverage = maxLeverage;
    }

    /// -----------------------------------------------------------------------
    /// Public/external state-change functions
    /// -----------------------------------------------------------------------

    function newPosition(
        PositionType type_,
        uint256 collateral,
        uint256 size
    ) external {

        // TODO: Implement the logic for liquidity reserves valiation - Traders cannot utilize more than a configured percentage of the deposited liquidity.

        // Check if the position (size / collateral) exceeds the max leverage
        uint256 indexTokenPrice = getPrice();
        uint256 sizeInCollateralToken = (size * indexTokenPrice) / 1e18;
        if (sizeInCollateralToken > collateral * s_maxLeverage) {
            revert PerpEC__ExceedsMaxLeverage();
        }
        
        // Collateral transfer
        if (i_collateralToken.allowance(msg.sender, address(this)) < collateral) {
            revert PerpEC__NotEnoughAllowance();
        }

        i_collateralToken.transferFrom(msg.sender, address(this), collateral);

        // Store the position
        s_positions[msg.sender] = Position({
            positionType: type_,
            collateral: collateral,
            size: size
        });

        emit PositionOpened(msg.sender, type_, collateral, size);
    }

    function addLiquidity(uint256 amount) external {
        if (i_wbtc.allowance(msg.sender, address(this)) < amount) {
            revert PerpEC__NotEnoughAllowance();
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

    function removeLiquidity(uint256 amount) external {
        if (amount > getRemovableShares(msg.sender)) {
            revert();
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

    function getRemovableShares(address user) public view returns (uint256) {
        uint256 userShares = balanceOf(user);
        uint256 lockedShares = (userShares * s_lockedLiquidity) /
            i_wbtc.balanceOf(address(this));

        return userShares - lockedShares;
    }

    function getPrice() public view returns (int256) {
        (, int answer, , , ) = i_priceOracle.latestRoundData();

        return answer;
    }
}
