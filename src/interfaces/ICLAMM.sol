// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "../lib/Oracle.sol";

/// @title Concentrated Liquidity Automated Market Maker (CLAMM) Interface
/// @notice Interface for interacting with a CLAMM pool
/// @dev This interface defines the core functionality for a concentrated liquidity AMM
interface ICLAMM {
    /// @notice Contains the current price and tick information for the pool
    /// @param sqrtPriceX96 The current square root price as a Q64.96
    /// @param tick The current tick
    /// @param unlocked The reentrancy lock state
    struct Slot0 {
        // The current price
        uint160 sqrtPriceX96;
        // The current tick
        int24 tick;
        // Whether the pool is locked
        bool unlocked;
        // The index of the last written observation
        uint16 observationIndex;
        // The current maximum number of observations that are being stored
        uint16 observationCardinality;
        // The next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
    }

    // Events
    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );
    event Mint(
        address indexed sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );
    event Burn(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );
    event Collect(
        address indexed owner,
        address recipient,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount0,
        uint128 amount1
    );
    event ProtocolFeeChanged(uint8 newProtocolFee);
    event Paused(address account);
    event Unpaused(address account);
    event LiquidityAdded(
        address indexed sender,
        address indexed recipient,
        int24 indexed tickLower,
        int24 tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1,
        bytes data
    );
    event LiquidityRemoved(
        address indexed sender,
        address indexed recipient,
        int24 indexed tickLower,
        int24 tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1,
        bytes data
    );

    /// @notice Returns the address of token0
    /// @return The contract address of token0
    function token0() external view returns (address);

    /// @notice Returns the address of token1
    /// @return The contract address of token1
    function token1() external view returns (address);

    /// @notice The pool's fee in hundredths of a bip (i.e., 1e-6)
    /// @return The fee
    function fee() external view returns (uint24);

    /// @notice The pool tick spacing
    /// @dev Ticks can only be used at multiples of this value
    /// @return The tick spacing
    function tickSpacing() external view returns (int24);

    /// @notice The maximum amount of liquidity that can be minted per tick
    /// @return The maximum liquidity per tick
    function maxLiquidityPerTick() external view returns (uint128);

    /// @notice The current protocol fee as a percentage
    /// @return The protocol fee
    function protocolFee() external view returns (uint8);

    /// @notice Returns true if the contract is paused, false otherwise
    function paused() external view returns (bool);

    /// @notice Returns the address of the contract owner
    function owner() external view returns (address);

    /// @notice Returns the pool's current price and tick data
    /// @return The current slot0 data
    function slot0() external view returns (Slot0 memory);

    /// @notice The all-time global fee growth of token0
    /// @return The fee growth of token0, per unit of liquidity, in Q128.128 format
    function feeGrowthGlobal0X128() external view returns (uint256);

    /// @notice The all-time global fee growth of token1
    /// @return The fee growth of token1, per unit of liquidity, in Q128.128 format
    function feeGrowthGlobal1X128() external view returns (uint256);

    /// @notice Returns the current liquidity in the pool
    function liquidity() external view returns (uint128);

    /// @notice Initializes the pool with an initial sqrt price
    /// @param sqrtPriceX96 The initial sqrt price of the pool as a Q64.96
    function initialize(uint160 sqrtPriceX96) external;

    /// @notice Adds liquidity for the given recipient/tickLower/tickUpper position
    /// @param recipient The address for which the liquidity will be created
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount The amount of liquidity to mint
    /// @return amount0 The amount of token0 that was paid to mint the liquidity
    /// @return amount1 The amount of token1 that was paid to mint the liquidity
    function mint(address recipient, int24 tickLower, int24 tickUpper, uint128 amount)
        external
        returns (uint256 amount0, uint256 amount1);

    /// @notice Collects tokens owed to a position
    /// @param recipient The address which should receive the tokens
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount0Requested How much token0 should be withdrawn from the fees
    /// @param amount1Requested How much token1 should be withdrawn from the fees
    /// @return amount0 The amount of token0 fees collected
    /// @return amount1 The amount of token1 fees collected
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);

    /// @notice Removes liquidity from the pool
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount The amount of liquidity to burn
    /// @return amount0 The amount of token0 withdrawn
    /// @return amount1 The amount of token1 withdrawn
    function burn(int24 tickLower, int24 tickUpper, uint128 amount)
        external
        returns (uint256 amount0, uint256 amount1);

    /// @notice Swap token0 for token1, or token1 for token0
    /// @param recipient The address to receive the output tokens
    /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
    /// @param amountSpecified The amount of the swap, which implicitly configures the swap as exact input (positive), or exact output (negative)
    /// @param sqrtPriceLimitX96 The Q64.96 sqrt price limit. If zero for one, the price cannot be less than this value after the swap. If one for zero, the price cannot be greater than this value after the swap
    /// @param data Any data to be passed through to the callback
    /// @return amount0 The delta of the balance of token0 of the pool, exact when negative, minimum when positive
    /// @return amount1 The delta of the balance of token1 of the pool, exact when negative, minimum when positive
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);

    /// @notice Receive token0 and token1 and pay it back, plus a fee, in the callback
    /// @param recipient The address which will receive the token0 and token1 amounts
    /// @param amount0 The amount of token0 to receive
    /// @param amount1 The amount of token1 to receive
    /// @param data Any data to be passed through to the callback
    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external;

    /// @notice Set the protocol's fee share of the swap fees
    /// @param _protocolFee New protocol fee
    function setProtocolFee(uint8 _protocolFee) external;

    /// @notice Pause the contract
    function pause() external;

    /// @notice Unpause the contract
    function unpause() external;

    /// @notice Returns the cumulative tick and liquidity-in-range data as of a given seconds ago
    /// @param secondsAgo The number of seconds ago to look up
    /// @return tickCumulative The cumulative tick value as of `secondsAgo`
    /// @return secondsPerLiquidityCumulativeX128 The cumulative seconds per liquidity-in-range value as of `secondsAgo`
    function observeSingle(uint32 secondsAgo)
        external
        view
        returns (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128);

    /// @notice Adds liquidity to a position in the pool
    /// @param token0 The address of the first token
    /// @param token1 The address of the second token
    /// @param fee The fee tier of the pool
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount0Desired The desired amount of token0 to add
    /// @param amount1Desired The desired amount of token1 to add
    /// @param amount0Min The minimum amount of token0 to add
    /// @param amount1Min The minimum amount of token1 to add
    /// @return liquidity The amount of liquidity added to the position
    /// @return amount0 The actual amount of token0 added to the position
    /// @return amount1 The actual amount of token1 added to the position
    function addLiquidity(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Removes liquidity from a position in the pool
    /// @param token0 The address of the first token
    /// @param token1 The address of the second token
    /// @param fee The fee tier of the pool
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param liquidity The amount of liquidity to remove
    /// @return amount0 The amount of token0 withdrawn
    /// @return amount1 The amount of token1 withdrawn
    function removeLiquidity(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Collects accumulated protocol fees
    /// @param recipient The address to receive the collected fees
    /// @return amount0 The amount of token0 protocol fees collected
    /// @return amount1 The amount of token1 protocol fees collected
    function collectProtocolFees(address recipient) external returns (uint256 amount0, uint256 amount1);
}
