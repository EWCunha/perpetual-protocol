// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// -----------------------------------------------------------------------
/// Interface
/// -----------------------------------------------------------------------

/**
 * @title interface to query decimals from ERC20.
 * @author @EWCunha
 * @notice Only used in the constructor from the perpetual protocol.
 */
interface IERC20Decimals {
    /**
     * @notice Query the amount of decimals from ERC20 token.
     */
    function decimals() external view returns (uint8);
}
