// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/// @title IFeeCollector Interface
/// @notice Interface for collecting fees from pools
interface IFeeCollector {
    /// @notice Collects accumulated fees from a specified pool
    /// @param pool The address of the pool to collect fees from
    /// @dev This function should handle the collection and distribution of fees
    function collectFees(address pool) external;
}
