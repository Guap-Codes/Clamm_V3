// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../interfaces/ICLAMM.sol";
import "../lib/PositionKey.sol";
import {INonfungiblePositionManager} from "../interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console2.sol";

/**
 * @title CLAMMPositionManager
 * @notice Manages ERC721 tokens that represent liquidity positions in the CLAMM (Concentrated Liquidity Automated Market Maker)
 * @dev This contract wraps CLAMM liquidity positions into ERC721 tokens, allowing for easier management and transfer of LP positions
 */
contract CLAMMPositionManager is ERC721, INonfungiblePositionManager {
    uint256 private _nextTokenId;

    ICLAMM public immutable clamm;

    /**
     * @notice Represents a liquidity position in the CLAMM
     * @param token0 The address of the first token in the pair
     * @param token1 The address of the second token in the pair
     * @param fee The fee tier of the pool
     * @param tickLower The lower tick boundary of the position
     * @param tickUpper The upper tick boundary of the position
     * @param liquidity The amount of liquidity in the position
     * @param feeGrowthInside0LastX128 The last recorded fee growth of token0 inside the position's tick range
     * @param feeGrowthInside1LastX128 The last recorded fee growth of token1 inside the position's tick range
     * @param tokensOwed0 Uncollected token0 fees
     * @param tokensOwed1 Uncollected token1 fees
     */
    struct Position {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    mapping(uint256 => Position) public positions;

    event PositionMinted(
        address indexed owner,
        uint256 indexed tokenId,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        bytes32 positionKey
    );

    event PositionBurned(address indexed owner, uint256 indexed tokenId, bytes32 positionKey);

    event FeesCollected(
        address indexed owner, uint256 indexed tokenId, bytes32 positionKey, uint128 amount0, uint128 amount1
    );

    /**
     * @notice Creates a new CLAMMPositionManager contract
     * @param _clamm The address of the CLAMM contract
     */
    constructor(address _clamm) ERC721("CLAMM LP", "CLP") {
        clamm = ICLAMM(_clamm);
        _nextTokenId = 1;
    }

    /**
     * @notice Returns the details of a position for a given token ID
     * @param tokenId The ID of the token representing the position
     * @return nonce The nonce for permits (not implemented)
     * @return operator The approved operator (not implemented)
     * @return token0 The first token of the pair
     * @return token1 The second token of the pair
     * @return fee The fee tier
     * @return tickLower The position's lower tick
     * @return tickUpper The position's upper tick
     * @return liquidity The amount of liquidity in the position
     * @return feeGrowthInside0LastX128 The last recorded fee growth of token0
     * @return feeGrowthInside1LastX128 The last recorded fee growth of token1
     * @return tokensOwed0 Uncollected fees for token0
     * @return tokensOwed1 Uncollected fees for token1
     */
    function getPosition(uint256 tokenId)
        external
        view
        override
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position memory position = positions[tokenId];
        return (
            0, // nonce (not implemented in this example)
            address(0), // operator (not implemented in this example)
            position.token0,
            position.token1,
            position.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    /**
     * @notice Creates a new liquidity position
     * @param params The parameters for minting a position
     * @return tokenId The ID of the newly minted token
     * @return liquidity The amount of liquidity added
     * @return amount0 The amount of token0 added as liquidity
     * @return amount1 The amount of token1 added as liquidity
     */
    function mint(MintParams calldata params)
        external
        payable
        override
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        bytes32 positionKey = PositionKey.compute(msg.sender, address(clamm), params.tickLower, params.tickUpper);

        (liquidity, amount0, amount1) = clamm.addLiquidity(
            params.token0,
            params.token1,
            params.fee,
            params.tickLower,
            params.tickUpper,
            params.amount0Desired,
            params.amount1Desired,
            params.amount0Min,
            params.amount1Min
        );

        tokenId = _nextTokenId++;
        _mint(params.recipient, tokenId);

        positions[tokenId] = Position({
            token0: params.token0,
            token1: params.token1,
            fee: params.fee,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: 0,
            feeGrowthInside1LastX128: 0,
            tokensOwed0: 0,
            tokensOwed1: 0
        });

        emit PositionMinted(
            params.recipient,
            tokenId,
            params.token0,
            params.token1,
            params.fee,
            params.tickLower,
            params.tickUpper,
            liquidity,
            positionKey
        );
    }

    /**
     * @notice Increases the liquidity in an existing position
     * @param params The parameters for increasing liquidity
     * @return liquidity The amount of liquidity added
     * @return amount0 The amount of token0 added as liquidity
     * @return amount1 The amount of token1 added as liquidity
     */
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        override
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        Position storage position = positions[params.tokenId];

        // solhint-disable-next-line var-name-mixedcase
        bytes32 positionKey = PositionKey.compute(address(this), address(clamm), position.tickLower, position.tickUpper);

        // Log the position key for debugging
        console2.logBytes32(positionKey);

        (liquidity, amount0, amount1) = clamm.addLiquidity(
            position.token0,
            position.token1,
            position.fee,
            position.tickLower,
            position.tickUpper,
            params.amount0Desired,
            params.amount1Desired,
            params.amount0Min,
            params.amount1Min
        );

        position.liquidity += liquidity;

        emit IncreaseLiquidity(params.tokenId, liquidity, amount0, amount1);
    }

    /**
     * @notice Decreases the liquidity in a position and accounts for fees
     * @param params The parameters for decreasing liquidity
     * @return amount0 The amount of token0 removed
     * @return amount1 The amount of token1 removed
     */
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        override
        returns (uint256 amount0, uint256 amount1)
    {
        Position storage position = positions[params.tokenId];
        require(position.liquidity >= params.liquidity, "Insufficient liquidity");

        bytes32 positionKey = PositionKey.compute(address(this), address(clamm), position.tickLower, position.tickUpper);
        
        // Log the position key for debugging
        console2.logBytes32(positionKey);

        (amount0, amount1) = clamm.removeLiquidity(
            position.token0, position.token1, position.fee, position.tickLower, position.tickUpper, params.liquidity
        );

        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, "Price slippage check");

        position.liquidity -= params.liquidity;
        position.tokensOwed0 += uint128(amount0);
        position.tokensOwed1 += uint128(amount1);

        emit DecreaseLiquidity(params.tokenId, params.liquidity, amount0, amount1);
    }

    /**
     * @notice Collects tokens owed to a position
     * @dev Fees are collected and transferred to the recipient
     * @param params The parameters for collecting fees
     * @return amount0 The amount of token0 collected
     * @return amount1 The amount of token1 collected
     */
    function collect(CollectParams calldata params)
        external
        payable
        override
        returns (uint256 amount0, uint256 amount1)
    {
        Position storage position = positions[params.tokenId];

        amount0 = uint256(position.tokensOwed0);
        amount1 = uint256(position.tokensOwed1);

        if (amount0 > params.amount0Max) {
            amount0 = params.amount0Max;
        }
        if (amount1 > params.amount1Max) {
            amount1 = params.amount1Max;
        }

        // Add safety checks before downcasting
        require(amount0 <= type(uint128).max, "amount0 overflow");
        require(amount1 <= type(uint128).max, "amount1 overflow");

        // Store the safe casted values
        uint128 collected0 = SafeCast.toUint128(amount0);
        uint128 collected1 = SafeCast.toUint128(amount1);

        // Update state before external calls
        if (amount0 > 0) {
            position.tokensOwed0 -= collected0;
        }
        if (amount1 > 0) {
            position.tokensOwed1 -= collected1;
        }

        // External calls after state updates
        if (amount0 > 0) {
            IERC20(position.token0).transfer(params.recipient, amount0);
        }
        if (amount1 > 0) {
            IERC20(position.token1).transfer(params.recipient, amount1);
        }

        emit FeesCollected(
            msg.sender,
            params.tokenId,
            PositionKey.compute(address(this), address(clamm), position.tickLower, position.tickUpper),
            collected0,
            collected1
        );
    }

    /**
     * @notice Burns a position token
     * @dev The position must have 0 liquidity and all tokens must be collected
     * @param tokenId The ID of the token to burn
     */
    function burn(uint256 tokenId) external payable override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "Not approved");
        Position memory position = positions[tokenId];
        require(position.liquidity == 0, "Cannot burn position with liquidity");
        require(position.tokensOwed0 == 0 && position.tokensOwed1 == 0, "Tokens not collected");

        bytes32 positionKey = PositionKey.compute(address(this), address(clamm), position.tickLower, position.tickUpper);

        delete positions[tokenId];
        _burn(tokenId);

        emit PositionBurned(msg.sender, tokenId, positionKey);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender);
    }
}
