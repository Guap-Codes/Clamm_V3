// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

library Math {
    /// @notice Returns the minimum of two numbers
    /// @param x The first number
    /// @param y The second number
    /// @return z The smaller of the two numbers
    function min(int24 x, int24 y) internal pure returns (int24 z) {
        z = x < y ? x : y;
    }

    /// @notice Returns the maximum of two numbers
    /// @param x The first number
    /// @param y The second number
    /// @return z The larger of the two numbers
    function max(int24 x, int24 y) internal pure returns (int24 z) {
        z = x > y ? x : y;
    }

    /// @notice Returns the minimum of two numbers
    /// @param x The first number
    /// @param y The second number
    /// @return z The smaller of the two numbers
    function min(uint160 x, uint160 y) internal pure returns (uint160 z) {
        z = x < y ? x : y;
    }

    /// @notice Returns the maximum of two numbers
    /// @param x The first number
    /// @param y The second number
    /// @return z The larger of the two numbers
    function max(uint160 x, uint160 y) internal pure returns (uint160 z) {
        z = x > y ? x : y;
    }
} 