// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

/// @title Oracle Library for Time-Weighted Average Price (TWAP) calculations
/// @notice Provides functionality for maintaining and querying historical price observations
/// @dev Implements a ring buffer of observations with binary search for efficient queries
library Oracle {
    /// @notice Represents a single price observation at a specific timestamp
    /// @dev Packed into 32 bytes to optimize storage
    struct Observation {
        uint32 blockTimestamp;                         // Timestamp of the observation
        int56 tickCumulative;                         // Cumulative tick value at this timestamp
        uint160 secondsPerLiquidityCumulativeX128;    // Cumulative seconds per liquidity, Q128.128 fixed point
    }

    /// @notice Initializes the oracle with the first observation
    /// @param observations The array of observations to initialize
    /// @dev Sets the first observation at index 0 with current timestamp and zero values
    function initialize(Oracle.Observation[65535] storage observations) internal {
        observations[0] = Observation({
            blockTimestamp: uint32(block.timestamp),
            tickCumulative: 0,
            secondsPerLiquidityCumulativeX128: 0
        });
    }

    /// @notice Returns the cumulative values at each specified timestamp
    /// @param observations The array of observations to query
    /// @param secondsAgos Array of seconds ago for which to return observations
    /// @return tickCumulatives Array of cumulative tick values
    /// @return secondsPerLiquidityCumulativeX128s Array of cumulative seconds per liquidity values
    function observe(Oracle.Observation[65535] storage observations, uint32[] calldata secondsAgos)
        internal
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        require(secondsAgos.length > 0, "Oracle: NO_SECONDS_SPECIFIED");

        tickCumulatives = new int56[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);

        for (uint256 i = 0; i < secondsAgos.length; i++) {
            (tickCumulatives[i], secondsPerLiquidityCumulativeX128s[i]) = observeSingle(observations, secondsAgos[i]);
        }
    }

    /// @notice Returns the cumulative values at a single timestamp
    /// @param observations The array of observations to query
    /// @param secondsAgo Number of seconds in the past to query
    /// @return tickCumulative The cumulative tick value at the specified timestamp
    /// @return secondsPerLiquidityCumulativeX128 The cumulative seconds per liquidity value
    /// @dev Uses binary search to find the closest observation
    function observeSingle(Oracle.Observation[65535] storage observations, uint32 secondsAgo)
        internal
        view
        returns (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128)
    {
        require(secondsAgo <= type(uint32).max - block.timestamp, "Oracle: SECONDS_AGO_OVERFLOW");

        uint32 target = uint32(block.timestamp) - secondsAgo;
        uint256 index = binarySearch(observations, target);
        Observation memory observation = observations[index];

        return (observation.tickCumulative, observation.secondsPerLiquidityCumulativeX128);
    }

    /// @notice Finds the index of the observation closest to the target timestamp
    /// @param observations The array of observations to search
    /// @param target The target timestamp to search for
    /// @return The index of the closest observation
    /// @dev Implements binary search algorithm
    function binarySearch(Oracle.Observation[65535] storage observations, uint32 target)
        internal
        view
        returns (uint256)
    {
        uint256 left = 0;
        uint256 right = _getLastIndex(observations);

        while (left < right) {
            uint256 mid = (left + right + 1) / 2;
            if (observations[mid].blockTimestamp <= target) {
                left = mid;
            } else {
                right = mid - 1;
            }
        }

        return left;
    }

    /// @notice Updates the oracle with a new observation
    /// @param observations The array of observations to update
    /// @param index Index at which to insert the new observation
    /// @param blockTimestamp Current block timestamp
    /// @param tick Current tick value
    /// @param liquidity Current liquidity value
    /// @param cardinality Current number of populated observations
    /// @param cardinalityNext Target number of observations
    /// @dev Calculates and stores cumulative values based on time elapsed
    function update(
        Oracle.Observation[65535] storage observations,
        uint16 index,
        uint32 blockTimestamp,
        int24 tick,
        uint128 liquidity,
        uint16 cardinality,
        uint16 cardinalityNext
    ) internal {
        require(observations[0].blockTimestamp > 0, "Oracle: NOT_INITIALIZED");

        uint32 timeElapsed = blockTimestamp - observations[_getLastIndex(observations)].blockTimestamp;

        if (timeElapsed > 0) {
            int56 tickCumulative =
                observations[_getLastIndex(observations)].tickCumulative + int56(tick) * int56(uint56(timeElapsed));
            uint160 secondsPerLiquidityCumulativeX128 = observations[_getLastIndex(observations)]
                .secondsPerLiquidityCumulativeX128 + ((uint160(timeElapsed) << 128) / liquidity);

            observations[index] = Observation({
                blockTimestamp: blockTimestamp,
                tickCumulative: tickCumulative,
                secondsPerLiquidityCumulativeX128: secondsPerLiquidityCumulativeX128
            });

            if (cardinalityNext > cardinality && index == (cardinality - 1)) {
                observations[cardinalityNext - 1] = observations[0];
            }
        }
    }

    /// @notice Returns the index of the last valid observation
    /// @param observations The array of observations to search
    /// @return The index of the last valid observation
    function _getLastIndex(Oracle.Observation[65535] storage observations) private view returns (uint256) {
        for (uint256 i = 0; i < 65535; i++) {
            if (observations[i].blockTimestamp == 0) {
                return i > 0 ? i - 1 : 0;
            }
        }
        return 65534;
    }

    /// @notice Returns the next available index for a new observation
    /// @param observations The array of observations to search
    /// @return The next available index, or 0 if array is full
    function _getNextIndex(Oracle.Observation[65535] storage observations) private view returns (uint256) {
        for (uint256 i = 0; i < 65535; i++) {
            if (observations[i].blockTimestamp == 0) {
                return i;
            }
        }
        return 0;
    }
}
