// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "../interfaces/ICLAMM.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title LimitOrderManager
/// @notice Manages limit orders for the CLAMM (Concentrated Liquidity Automated Market Maker)
/// @dev Allows users to create, execute, and cancel limit orders for token swaps
contract LimitOrderManager {
    using SafeERC20 for IERC20;

    struct LimitOrder {
        address owner;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
        uint256 deadline;
        bool executed;
    }

    ICLAMM public immutable clamm;
    mapping(uint256 => LimitOrder) public limitOrders;
    uint256 public nextOrderId;

    event LimitOrderCreated(
        uint256 indexed orderId,
        address indexed owner,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum
    );
    event LimitOrderExecuted(uint256 indexed orderId, address indexed executor, uint256 amountIn, uint256 amountOut);
    event LimitOrderCancelled(uint256 indexed orderId);

    constructor(address _clamm) {
        require(_clamm != address(0), "Invalid CLAMM address");
        clamm = ICLAMM(_clamm);
    }

    /// @notice Creates a new limit order
    /// @param tokenIn Address of the token being sold
    /// @param tokenOut Address of the token being bought
    /// @param amountIn Amount of tokenIn to sell
    /// @param amountOutMinimum Minimum amount of tokenOut to receive
    /// @param sqrtPriceLimitX96 Price limit for the swap
    /// @param deadline Timestamp after which the order expires
    /// @return orderId Unique identifier for the created order
    function createLimitOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96,
        uint256 deadline
    ) external returns (uint256 orderId) {
        require(tokenIn != tokenOut, "Invalid token pair");
        require(amountIn > 0, "Invalid amount");
        require(deadline > block.timestamp, "Expired deadline");

        // Update state before external call
        orderId = nextOrderId++;
        limitOrders[orderId] = LimitOrder({
            owner: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: sqrtPriceLimitX96,
            deadline: deadline,
            executed: false
        });

        // External call
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        emit LimitOrderCreated(orderId, msg.sender, tokenIn, tokenOut, amountIn, amountOutMinimum);
    }

    /// @notice Executes a pending limit order
    /// @dev Anyone can execute a limit order if the conditions are met
    /// @param orderId The ID of the order to execute
    function executeLimitOrder(uint256 orderId) external {
        LimitOrder storage order = limitOrders[orderId];
        require(order.owner != address(0), "Order does not exist");
        require(!order.executed, "Order already executed");
        require(block.timestamp <= order.deadline, "Order expired");

        bool zeroForOne = order.tokenIn < order.tokenOut;
        IERC20 tokenIn = IERC20(order.tokenIn);

        // Approve CLAMM to spend tokens
        tokenIn.safeIncreaseAllowance(address(clamm), order.amountIn);

        try clamm.swap(
            address(this),
            zeroForOne,
            int256(order.amountIn),
            order.sqrtPriceLimitX96,
            abi.encode(msg.sender)
        ) returns (
            int256 amount0, int256 amount1
        ) {
            uint256 amountOut = uint256(-(zeroForOne ? amount1 : amount0));
            require(amountOut >= order.amountOutMinimum, "Insufficient output amount");

            // Reset allowance after swap
            tokenIn.safeDecreaseAllowance(address(clamm), order.amountIn);

            order.executed = true;
            emit LimitOrderExecuted(orderId, msg.sender, order.amountIn, amountOut);
        } catch {
            // Reset allowance if swap fails
            tokenIn.safeDecreaseAllowance(address(clamm), order.amountIn);
            revert("Swap failed");
        }
    }

    /// @notice Cancels a pending limit order
    /// @dev Only the order creator can cancel their order
    /// @param orderId The ID of the order to cancel
    function cancelLimitOrder(uint256 orderId) external {
        LimitOrder storage order = limitOrders[orderId];
        require(msg.sender == order.owner, "Not order owner");
        require(!order.executed, "Order already executed");

        IERC20(order.tokenIn).safeTransfer(order.owner, order.amountIn);
        delete limitOrders[orderId];

        emit LimitOrderCancelled(orderId);
    }
}
