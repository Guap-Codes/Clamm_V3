// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "../interfaces/IERC20.sol";
import "../interfaces/ICLAMM.sol";
import "../interfaces/IV2Pair.sol";
import "../interfaces/INonfungiblePositionManager.sol";

/// @title V3 Liquidity Migration Contract
/// @notice Enables migration of liquidity from V2 AMM pairs to V3 Concentrated Liquidity positions
/// @dev This contract handles the entire migration process including removal of V2 liquidity and minting of V3 positions
contract V3Migrator {
    /// @notice Struct to hold migration state variables
    struct MigrationState {
        uint256 liquidityToMigrate;
        uint256 amount0V2;
        uint256 amount1V2;
        uint256 amount0V3;
        uint256 amount1V3;
    }

    /// @notice The address of the V3 factory contract
    address public immutable factory;
    /// @notice The address of the V3 NonfungiblePositionManager contract
    address public immutable positionManager;

    /// @notice Creates a new V3Migrator contract
    /// @param _factory The address of the V3 factory contract
    /// @param _positionManager The address of the V3 NonfungiblePositionManager contract
    constructor(address _factory, address _positionManager) {
        factory = _factory;
        positionManager = _positionManager;
    }

    /// @notice Migrates liquidity from a V2 pair to a V3 pool
    /// @param pair The V2 pair to migrate from
    /// @param liquidityV2 The amount of V2 liquidity to migrate
    /// @param percentageToMigrate The percentage of liquidity to migrate (1-100)
    /// @param token0 The address of token0 of the pair
    /// @param token1 The address of token1 of the pair
    /// @param fee The fee tier of the V3 pool to migrate to
    /// @param tickLower The lower tick of the V3 position
    /// @param tickUpper The upper tick of the V3 position
    /// @param amount0Min The minimum amount of token0 to receive in the V3 position
    /// @param amount1Min The minimum amount of token1 to receive in the V3 position
    /// @param recipient The address that will receive the V3 position
    /// @param deadline The timestamp after which the transaction will revert
    function migrate(
        IV2Pair pair,
        uint256 liquidityV2,
        uint8 percentageToMigrate,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient,
        uint256 deadline
    ) external {
        // Initial validation
        _validateMigration(percentageToMigrate, deadline);

        // Transfer and calculate liquidity
        MigrationState memory state = _prepareV2Liquidity(pair, liquidityV2, percentageToMigrate);

        // Handle V3 minting
        _mintV3(state, token0, token1, fee, tickLower, tickUpper, amount0Min, amount1Min, recipient, deadline);

        // Handle remaining assets
        _handleRemainingAssets(
            pair,
            liquidityV2,
            state.liquidityToMigrate,
            token0,
            token1,
            state.amount0V2,
            state.amount1V2,
            state.amount0V3,
            state.amount1V3
        );
    }

    function _mintV3(
        MigrationState memory state,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient,
        uint256 deadline
    ) private {
        MintV3Params memory params = MintV3Params({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0V2: state.amount0V2,
            amount1V2: state.amount1V2,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: recipient,
            deadline: deadline
        });

        (state.amount0V3, state.amount1V3) = _mintV3Position(params);
    }

    function _validateMigration(uint8 percentageToMigrate, uint256 deadline) private view {
        require(percentageToMigrate > 0 && percentageToMigrate <= 100, "Invalid percentage");
        require(block.timestamp <= deadline, "Transaction too old");
    }

    function _prepareV2Liquidity(IV2Pair pair, uint256 liquidityV2, uint8 percentageToMigrate)
        private
        returns (MigrationState memory state)
    {
        // Transfer V2 liquidity from user to this contract
        require(pair.transferFrom(msg.sender, address(this), liquidityV2), "Transfer failed");

        // Calculate and burn V2 liquidity
        state.liquidityToMigrate = (liquidityV2 * percentageToMigrate) / 100;
        (state.amount0V2, state.amount1V2) = pair.burn(state.liquidityToMigrate);
        return state;
    }

    struct MintV3Params {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0V2;
        uint256 amount1V2;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function _mintV3Position(MintV3Params memory params) private returns (uint256 amount0V3, uint256 amount1V3) {
        // Approve tokens
        require(IERC20(params.token0).approve(positionManager, params.amount0V2), "Token0 approval failed");
        require(IERC20(params.token1).approve(positionManager, params.amount1V2), "Token1 approval failed");

        // Create params struct inline to reduce stack variables
        (,, amount0V3, amount1V3) = INonfungiblePositionManager(positionManager).mint{value: 0}(
            INonfungiblePositionManager.MintParams({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: params.amount0V2,
                amount1Desired: params.amount1V2,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                recipient: params.recipient,
                deadline: params.deadline
            })
        );
        return (amount0V3, amount1V3);
    }

    function _handleRemainingAssets(
        IV2Pair pair,
        uint256 liquidityV2,
        uint256 liquidityToMigrate,
        address token0,
        address token1,
        uint256 amount0V2,
        uint256 amount1V2,
        uint256 amount0V3,
        uint256 amount1V3
    ) private {
        // Handle remaining V2 liquidity
        if (liquidityToMigrate < liquidityV2) {
            require(pair.transfer(msg.sender, liquidityV2 - liquidityToMigrate), "Transfer failed");
        }

        // Handle remaining tokens
        if (amount0V2 > amount0V3) {
            require(IERC20(token0).transfer(msg.sender, amount0V2 - amount0V3), "Transfer failed");
        }
        if (amount1V2 > amount1V3) {
            require(IERC20(token1).transfer(msg.sender, amount1V2 - amount1V3), "Transfer failed");
        }
    }
}
