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

    /// -----------------------------------------------------------------------
    /// Custom types
    /// -----------------------------------------------------------------------

    enum PositionType {
        LONG,
        SHORT
    }

    /// -----------------------------------------------------------------------
    /// Storage/state variables
    /// -----------------------------------------------------------------------

    uint256 internal s_lockedLiquidity;
    IERC20 internal immutable i_collateralToken;
    IERC20 internal immutable i_wbtc;
    AggregatorV3Interface internal immutable i_priceOracle;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event LiquidityAdded(address indexed provider, uint256 amount);
    event LiquidityRemoved(address indexed provider, uint256 amount);

    /// -----------------------------------------------------------------------
    /// Constructor logic
    /// -----------------------------------------------------------------------

    constructor(
        address collateralToken,
        address wbtc,
        address priceOracle
    ) ERC20("Liquidity token PerpEC", "LTPerpEC") {
        i_collateralToken = IERC20(collateralToken);
        i_wbtc = IERC20(wbtc);
        i_priceOracle = AggregatorV3Interface(priceOracle);
    }

    /// -----------------------------------------------------------------------
    /// Public/external state-change functions
    /// -----------------------------------------------------------------------

    function newPosition(
        PositionType type_,
        uint256 collateral,
        uint256 size
    ) external {}

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
