// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

/// @title Position Library for Concentrated Liquidity AMM
/// @notice Manages liquidity positions and fee accounting for liquidity providers
/// @dev Handles position-specific data storage and updates for the CLAMM protocol
library Position {
    /// @notice Information stored for each liquidity position
    /// @dev Packed for gas optimization while maintaining position tracking
    struct Info {
        /// @notice Amount of liquidity owned by this position
        /// @dev Represents the amount of liquidity tokens in the position
        uint128 liquidity;

        /// @notice Per-unit fee growth of token0 as of last position update
        /// @dev Tracks fee accumulation for token0, stored as Q128.128 fixed point
        uint256 feeGrowthInside0LastX128;

        /// @notice Per-unit fee growth of token1 as of last position update
        /// @dev Tracks fee accumulation for token1, stored as Q128.128 fixed point
        uint256 feeGrowthInside1LastX128;

        /// @notice Uncollected token0 fees owed to position owner
        /// @dev Accumulated fees not yet collected for token0
        uint128 tokensOwed0;

        /// @notice Uncollected token1 fees owed to position owner
        /// @dev Accumulated fees not yet collected for token1
        uint128 tokensOwed1;
    }

    /// @notice Retrieves position information for a given owner and tick range
    /// @param self The mapping containing all position information
    /// @param owner The address of the position owner
    /// @param tickLower The lower tick boundary of the position
    /// @param tickUpper The upper tick boundary of the position
    /// @return position A storage pointer to the position information
    /// @dev Uses keccak256 hash of owner and tick bounds as unique position identifier
    function get(mapping(bytes32 => Info) storage self, address owner, int24 tickLower, int24 tickUpper)
        internal
        view
        returns (Position.Info storage position)
    {
        position = self[keccak256(abi.encodePacked(owner, tickLower, tickUpper))];
    }

    /// @notice Updates a position's liquidity and fee tracking
    /// @param self The position to update
    /// @param liquidityDelta The change in liquidity to apply (positive or negative)
    /// @param feeGrowthInside0X128 The current total fee growth of token0 inside tick range
    /// @param feeGrowthInsideX128 The current total fee growth of token1 inside tick range
    /// @dev Updates liquidity and fee growth tracking for a position
    /// @dev Reverts if attempting to update a position with zero liquidity
    function update(Info storage self, int128 liquidityDelta, uint256 feeGrowthInside0X128, uint256 feeGrowthInsideX128)
        internal
    {
        Info memory _self = self;

        // Ensure position has liquidity if no change is being made
        if (liquidityDelta == 0) {
            require(_self.liquidity > 0, "0 liquidity");
        }

        // Update fee growth tracking for both tokens
        self.feeGrowthInside0LastX128 = feeGrowthInside0X128;
        self.feeGrowthInside1LastX128 = feeGrowthInsideX128;

        // Update liquidity if there's a change
        if (liquidityDelta != 0) {
            self.liquidity = liquidityDelta < 0
                ? _self.liquidity - uint128(-liquidityDelta)  // Remove liquidity
                : _self.liquidity + uint128(liquidityDelta);  // Add liquidity
        }
    }
}
