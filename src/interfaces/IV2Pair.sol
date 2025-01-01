// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

/// @title Uniswap V2 Pair Interface
/// @notice Interface for interacting with Uniswap V2 liquidity pairs
interface IV2Pair {
    /// @notice Transfers tokens from one address to another using allowance mechanism
    /// @param from Address to transfer tokens from
    /// @param to Address to transfer tokens to
    /// @param value Amount of tokens to transfer
    /// @return success True if the transfer was successful
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    /// @notice Transfers tokens from the caller to another address
    /// @param to Address to transfer tokens to
    /// @param value Amount of tokens to transfer
    /// @return success True if the transfer was successful
    function transfer(address to, uint256 value) external returns (bool);

    /// @notice Burns liquidity tokens to receive underlying assets
    /// @param liquidity Amount of liquidity tokens to burn
    /// @return amount0 Amount of token0 received
    /// @return amount1 Amount of token1 received
    function burn(uint256 liquidity) external returns (uint256 amount0, uint256 amount1);
}
