// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "../interfaces/ICLAMM.sol";
import "../lib/TickMath.sol";

/// @title CLAMMQuoter - Quotes for Concentrated Liquidity AMM swaps
/// @notice Provides functionality to simulate swaps and return expected outputs without executing actual swaps
/// @dev Uses a try-catch pattern with a revert to return swap simulation results
contract CLAMMQuoter {
    /// @notice Parameters required for getting a quote
    /// @param pool The address of the CLAMM pool
    /// @param amountIn The amount of tokens to be swapped
    /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
    struct QuoteParams {
        address pool;
        uint256 amountIn;
        bool zeroForOne;
    }

    /// @notice Returns the expected output amount for a given swap without executing the swap
    /// @param params The parameters for the quote
    /// @return amountOut The expected output amount
    /// @return sqrtPriceX96After The expected sqrt price after the swap
    /// @return tickAfter The expected tick after the swap
    /// @dev This function simulates a swap by attempting it and catching the revert that contains the results
    function quote(QuoteParams memory params)
        public
        returns (uint256 amountOut, uint160 sqrtPriceX96After, int24 tickAfter)
    {
        try ICLAMM(params.pool).swap(
            address(this), // recipient
            params.zeroForOne,
            int256(params.amountIn),
            params.zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            ""  // Empty bytes for data parameter
        ) {} catch (bytes memory reason) {
            return abi.decode(reason, (uint256, uint160, int24));
        }
        revert("Unexpected");
    }

    /// @notice Callback function called by the CLAMM pool during swap simulation
    /// @param amount0Delta The change in token0 balance
    /// @param amount1Delta The change in token1 balance
    /// @param data Encoded pool address
    /// @dev This function is called during the swap simulation and reverts with the quote results
    /// @dev The revert is caught by the quote function to return the results
    function clammSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes memory data) external view {
        address pool = abi.decode(data, (address));
        require(msg.sender == address(pool), "Unauthorized callback");

        // Get the current state of the pool
        ICLAMM.Slot0 memory slot0 = ICLAMM(pool).slot0();
        uint160 sqrtPriceX96After = slot0.sqrtPriceX96;
        int24 tickAfter = slot0.tick;

        // Calculate the output amount based on the delta of the token that was received
        uint256 amountOut = amount0Delta > 0 ? uint256(-amount1Delta) : uint256(-amount0Delta);

        // Revert with the quote results encoded
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, amountOut)
            mstore(add(ptr, 0x20), sqrtPriceX96After)
            mstore(add(ptr, 0x40), tickAfter)
            revert(ptr, 96)
        }
    }
}
