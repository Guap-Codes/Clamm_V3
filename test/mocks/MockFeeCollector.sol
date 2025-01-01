// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

import "../../src/interfaces/IFeeCollector.sol";

/// @title Mock Fee Collector for Testing
/// @notice A mock implementation of IFeeCollector for testing purposes
/// @dev Simulates fee collection functionality without actual token transfers
contract MockFeeCollector is IFeeCollector {
    /// @notice The last pool address that called collectFees
    /// @dev Used to verify correct pool interactions in tests
    address public lastPool;

    /// @notice The last recipient address for collected fees
    /// @dev Used to track fee collection destination in tests
    address public lastRecipient;

    /// @notice Mock amount for token0 fees
    /// @dev Default value set to 100 for testing
    uint256 public mockToken0Fees = 100;

    /// @notice Mock amount for token1 fees
    /// @dev Default value set to 200 for testing
    uint256 public mockToken1Fees = 200;

    /// @notice Emitted when fees are collected
    /// @param pool The address of the pool from which fees were collected
    /// @param recipient The address receiving the collected fees
    /// @param amount0 The amount of token0 fees collected
    /// @param amount1 The amount of token1 fees collected
    event FeesCollected(
        address pool,
        address recipient,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Simulates fee collection from a pool
    /// @param pool The address of the pool to collect fees from
    /// @dev Updates lastPool and lastRecipient, then emits FeesCollected event
    function collectFees(address pool) external {
        // Store last collection details
        lastPool = pool;
        lastRecipient = address(this);

        // Emit event for testing purposes
        emit FeesCollected(pool, address(this), mockToken0Fees, mockToken1Fees);
    }

    /// @notice Sets mock fee amounts for testing
    /// @param amount0 The amount to set for token0 fees
    /// @param amount1 The amount to set for token1 fees
    /// @dev Allows tests to configure expected fee amounts
    function setMockFees(uint256 amount0, uint256 amount1) external {
        mockToken0Fees = amount0;
        mockToken1Fees = amount1;
    }
}
