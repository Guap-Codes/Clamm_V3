// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

import "./BitMath.sol";

/// @title Tick Bitmap Library for Concentrated Liquidity AMM
/// @notice Stores a packed array of booleans to track initialized ticks
/// @dev Uses a mapping of int16 to uint256 to store 256 ticks in each word
library TickBitmap {
    /// @notice Calculates the position in the mapping and bitmap for a given tick
    /// @param tick The tick for which to calculate the position
    /// @return wordPos The key in the mapping containing the tick
    /// @return bitPos The position in the word where the tick's bit is stored
    /// @dev For negative ticks, the bit position is flipped to maintain order
    function position(
        int24 tick
    ) private pure returns (int16 wordPos, uint8 bitPos) {
        wordPos = int16(tick >> 8);  // Divide by 256 to get the word position

        if (tick < 0) {
            // For negative ticks, flip the bit position within the word
            int24 modTick = (-tick) & 0xFF;  // Get the position within the word
            bitPos = uint8(255 - uint24(modTick));  // Flip the position
        } else {
            bitPos = uint8(uint24(tick) & 0xFF);  // Get the position within the word
        }
    }

    /// @notice Flips the initialized state of a tick in the bitmap
    /// @param self The mapping containing all tick information
    /// @param tick The tick to flip
    /// @param tickSpacing The spacing between usable ticks
    /// @dev Ensures tick is a multiple of tickSpacing
    function flipTick(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing
    ) internal {
        require(tick % tickSpacing == 0);  // Ensure tick is properly spaced
        (int16 wordPos, uint8 bitPos) = position(tick);
        uint256 mask = 1 << bitPos;  // Create mask for the bit to flip
        self[wordPos] ^= mask;  // Flip the bit using XOR
    }

    /// @notice Finds the next initialized tick in the same word
    /// @param self The mapping containing all tick information
    /// @param tick The starting tick
    /// @param tickSpacing The spacing between usable ticks
    /// @param lte Whether to search for the next initialized tick to the left (less than or equal to)
    /// @return next The next initialized or uninitialized tick up to 256 ticks away
    /// @return initialized Whether the next tick is initialized
    /// @dev Searches within the same word (256 ticks) in either direction
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        int24 compressed = tick / tickSpacing;

        if (lte) {  // Search towards lesser ticks
            (int16 wordPos, uint8 bitPos) = position(compressed);
            // Create mask for all bits less than or equal to bitPos
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = self[wordPos] & mask;

            initialized = masked != 0;  // Check if any bits are set
            
            // Calculate the next tick based on most significant bit
            next = initialized
                ? ((compressed * tickSpacing) -
                    int24(uint24(bitPos - BitMath.mostSignificantBit(masked))))
                : (compressed *
                    tickSpacing -
                    int24(uint24(bitPos)) *
                    tickSpacing);
        } else {  // Search towards greater ticks
            (int16 wordPos, uint8 bitPos) = position(compressed);
            // Create mask for all bits greater than bitPos
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = self[wordPos] & mask;

            initialized = masked != 0;  // Check if any bits are set
            
            // Calculate the next tick based on least significant bit
            next = initialized
                ? ((compressed + 1) *
                    tickSpacing +
                    int24(uint24(BitMath.leastSignificantBit(masked) - bitPos)))
                : (compressed + 1) *
                    tickSpacing +
                    int24(uint24(type(uint8).max));
        }
    }
}
