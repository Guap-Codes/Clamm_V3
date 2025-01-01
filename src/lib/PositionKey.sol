// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

/// @title PositionKey
/// @notice Library for computing position keys for the CLAMMPositionManager
library PositionKey {
    /// @notice Computes the position key for a position in a CLAMM pool
    /// @param owner The owner of the position
    /// @param pool The address of the CLAMM pool
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @return key The unique key for the position
    function compute(address owner, address pool, int24 tickLower, int24 tickUpper)
        internal
        pure
        returns (bytes32 key)
    {
        key = keccak256(abi.encodePacked(owner, pool, tickLower, tickUpper));
    }
}
