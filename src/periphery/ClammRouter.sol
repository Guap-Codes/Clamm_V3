// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "../interfaces/ICLAMM.sol";
import "../interfaces/IERC20.sol";
import "../lib/TransferHelper.sol";
import "../lib/TickMath.sol";

/// @title CLAMM Router for multi-hop swaps
/// @notice Handles swaps through one or multiple Concentrated Liquidity AMM pools
/// @dev Enables swapping tokens through optimal paths using multiple pools
contract CLAMMRouter {
    /// @notice Represents a single swap hop through a CLAMM pool
    /// @param tokenA The input token address
    /// @param tokenB The output token address
    /// @param pool The address of the CLAMM pool for this hop
    struct Route {
        address tokenA;
        address tokenB;
        address pool;
    }

    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible
    /// @param amountIn The amount of input tokens to send
    /// @param amountOutMin The minimum amount of output tokens that must be received
    /// @param route An array of Route structs representing the swap path
    /// @param to The address that will receive the output tokens
    /// @param deadline The Unix timestamp after which the transaction will revert
    /// @return amountOut The amount of output tokens received
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata route,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        require(deadline >= block.timestamp, "Router: EXPIRED");

        // Transfer input tokens from sender to router
        TransferHelper.safeTransferFrom(route[0].tokenA, msg.sender, address(this), amountIn);

        // Track current amount for the swap
        uint256 currentAmount = amountIn;

        // Iterate through all routes in the path
        for (uint256 i = 0; i < route.length; i++) {
            // Approve the pool to spend input tokens
            TransferHelper.safeApprove(route[i].tokenA, route[i].pool, currentAmount);

            // Determine swap direction based on token addresses
            bool zeroForOne = route[i].tokenA < route[i].tokenB;

            // Execute the swap through the CLAMM pool
            (int256 amount0, int256 amount1) = ICLAMM(route[i].pool).swap(
                address(this),
                zeroForOne,
                int256(currentAmount),
                zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                abi.encode(msg.sender)
            );

            // Update currentAmount for next iteration
            currentAmount = uint256(-(zeroForOne ? amount1 : amount0));
        }

        // Verify the output amount meets minimum requirements
        require(currentAmount >= amountOutMin, "Router: INSUFFICIENT_OUTPUT_AMOUNT");

        // Transfer the final output tokens to the recipient
        TransferHelper.safeTransfer(route[route.length - 1].tokenB, to, currentAmount);

        return currentAmount;
    }

    // Add more swap functions (e.g., swapTokensForExactTokens) here
}
