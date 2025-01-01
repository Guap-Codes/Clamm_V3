// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Tick} from "./lib/Tick.sol";
import {Position} from "./lib/Position.sol";
import {SqrtPriceMath} from "./lib/SqrtPriceMath.sol";
import {SafeCast} from "./lib/SafeCast.sol";
import {TickBitmap} from "./lib/TickBitmap.sol";
import {TickMath} from "./lib/TickMath.sol";
import {SwapMath} from "./lib/SwapMath.sol";
import {Oracle} from "./lib/Oracle.sol";
import {ICLAMM} from "./interfaces/ICLAMM.sol";
import {LiquidityMining} from "./periphery/LiquidityMining.sol";
import {PineToken} from "./PineToken.sol";
import {IFeeCollector} from "./interfaces/IFeeCollector.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {FullMath} from "./lib/FullMath.sol";
import {FixedPoint96} from "./lib/FixedPoint96.sol";
import {IFlashCallback} from "../src/interfaces/IFlashCallback.sol";
import "./lib/Math.sol";

interface IUniswapV3SwapCallback {
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;
}

/// @title Concentrated Liquidity Automated Market Maker (CLAMM)
/// @notice Implements a concentrated liquidity AMM with support for liquidity mining
/// @dev Based on Uniswap V3's core functionality with additional features
contract CLAMM is ICLAMM {
    using SafeCast for uint256;
    using SafeCast for int256;
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using Oracle for Oracle.Observation[65535];
    using SqrtPriceMath for uint160;

    /// @notice Address of the first token in the pair
    address public immutable token0;
    /// @notice Address of the second token in the pair
    address public immutable token1;
    /// @notice The pool's fee in hundredths of a bip (i.e., 1e-6)
    uint24 public immutable fee;
    /// @notice The minimum number of ticks between initialized ticks
    int24 public immutable tickSpacing;
    /// @notice The maximum amount of liquidity per tick
    uint128 public immutable maxLiquidityPerTick;

    /// @notice Denominator for protocol fee calculation (fee = 1/PROTOCOL_FEE_DENOMINATOR)
    uint8 public constant PROTOCOL_FEE_DENOMINATOR = 10;
    /// @notice Current protocol fee rate
    uint8 public protocolFee;
    /// @notice Flag indicating if the contract is paused
    bool public paused;
    /// @notice Array of owner addresses (requires 2/3 for multi-sig)
    address[3] public owners;
    /// @notice Number of signatures required for multi-sig operations
    uint256 public constant REQUIRED_SIGNATURES = 2;
    /// @notice Mapping to track multi-sig approvals
    mapping(bytes32 => mapping(address => bool)) public approvals;

    Oracle.Observation[65535] public observations;


    /// @notice Parameters for modifying a position
    /// @param owner The owner of the position
    /// @param tickLower The lower tick boundary
    /// @param tickUpper The upper tick boundary
    /// @param liquidityDelta The amount of liquidity to add/remove (positive/negative)
    struct ModifyPositionParams {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        int128 liquidityDelta;
    }

    /// @notice Cache for swap computations
    /// @param liquidityStart The liquidity at the start of the swap
    struct SwapCache {
        uint128 liquidityStart;
        int24 tickNext;
        bool initialized;
        uint160 sqrtPriceNextX96;
        uint160 sqrtPriceTargetX96;
    }

    // the top level state of the swap, the results of which are recorded in storage at the end
    struct SwapState {
        // the amount remaining to be swapped in/out of the input/output asset
        int256 amountSpecifiedRemaining;
        // the amount already swapped out/in of the output/input asset
        int256 amountCalculated;
        // current sqrt(price)
        uint160 sqrtPriceX96;
        // the tick associated with the current price
        int24 tick;
        // the global fee growth of the input token
        uint256 feeGrowthGlobalX128;
        // the current liquidity in range
        uint128 liquidity;
    }

    Slot0 private slot0_;
    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;
    uint128 public liquidity;
    mapping(int24 => Tick.Info) public ticks;
    mapping(int16 => uint256) public tickBitmap;
    mapping(bytes32 => Position.Info) public positions;

    error EmergencyActionFailed();

    modifier lock() {
        require(slot0_.unlocked, "locked");
        slot0_.unlocked = false;
        _;
        slot0_.unlocked = true;
    }

    modifier onlyOwner() {
        require(isOwner(msg.sender), "Not an owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    /// @notice Reference to the liquidity mining contract
    LiquidityMining public liquidityMining;
    /// @notice LP token for this pool
    PineToken public lpToken;
    /// @notice Contract that collects protocol fees
    IFeeCollector public feeCollector;

    // Add these state variables
    uint256 public protocolFees0;
    uint256 public protocolFees1;

    // Add this event declaration
    event Flash(
        address indexed sender,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1,
        uint256 fee0,
        uint256 fee1
    );

    // Add this event declaration
    event EmergencyWithdraw(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    // Add this event declaration near other events
    event EmergencyFeeCollectorSet(
        address indexed oldFeeCollector,
        address indexed newFeeCollector
    );

    // Add this constant
    uint256 public constant MAX_SWAP_ITERATIONS = 100;

    constructor(
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing,
        address[3] memory _owners,
        address _liquidityMining,
        address _lpToken
    ) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;
        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(
            _tickSpacing
        );
        owners = _owners;
        protocolFee = 1; // 10% of fees go to protocol by default
        liquidityMining = LiquidityMining(_liquidityMining);
        lpToken = PineToken(_lpToken);

        // Set this contract as the authorized minter
        PineToken(_lpToken).setCLAMM(address(this));
    }

    /// @notice Validates tick range parameters
    /// @param tickLower The lower tick
    /// @param tickUpper The upper tick
    function checkTicks(int24 tickLower, int24 tickUpper) public view {
        require(tickLower < tickUpper, "TLU");
        require(tickLower >= TickMath.MIN_TICK, "TLM");
        require(tickUpper <= TickMath.MAX_TICK, "TUM");

        // Add tick spacing validation
        require(
            tickLower % tickSpacing == 0,
            "Tick lower not multiple of spacing"
        );
        require(
            tickUpper % tickSpacing == 0,
            "Tick upper not multiple of spacing"
        );
    }

    /// @notice Initializes the pool with first sqrt price
    /// @param sqrtPriceX96 Initial sqrt price as a Q64.96
    function initialize(uint160 sqrtPriceX96) external {
        require(slot0_.sqrtPriceX96 == 0, "Already initialized");
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        slot0_ = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            unlocked: true,
            observationIndex: 0,
            observationCardinality: 1,
            observationCardinalityNext: 1
        });

        // Initialize the first observation
        Oracle.Observation memory observation = Oracle.Observation({
            blockTimestamp: _blockTimestamp(),
            tickCumulative: 0,
            secondsPerLiquidityCumulativeX128: 0
        });
        observations[0] = observation;
    }

    function _modifyPosition(
        ModifyPositionParams memory params
    )
        private
        returns (Position.Info storage position, int256 amount0, int256 amount1)
    {
        checkTicks(params.tickLower, params.tickUpper);

        Slot0 memory slot0Start = slot0_;

        position = _updatePosition(
            params.owner,
            params.tickLower,
            params.tickUpper,
            params.liquidityDelta,
            slot0Start.tick
        );

        if (params.liquidityDelta != 0) {
            if (slot0Start.tick < params.tickLower) {
                amount0 = SqrtPriceMath.getAmount0DeltaSigned(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            } else if (slot0Start.tick < params.tickUpper) {
                amount0 = SqrtPriceMath.getAmount0DeltaSigned(
                    slot0Start.sqrtPriceX96,
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
                amount1 = SqrtPriceMath.getAmount1DeltaSigned(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    slot0Start.sqrtPriceX96,
                    params.liquidityDelta
                );

                liquidity = params.liquidityDelta < 0
                    ? liquidity - uint128(-params.liquidityDelta)
                    : liquidity + uint128(params.liquidityDelta);
            } else {
                amount1 = SqrtPriceMath.getAmount1DeltaSigned(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            }
        }
    }

    function _updatePosition(
        address positionOwner,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        int24 tick
    ) private returns (Position.Info storage position) {
        position = positions.get(positionOwner, tickLower, tickUpper);

        // TODO fees
        uint256 _feeGrowthGlobal0X128 = 0;
        uint256 _feeGrowthGlobal1X128 = 0;

        bool flippedLower;
        bool flippedUpper;
        if (liquidityDelta != 0) {
            flippedLower = ticks.update(
                tickLower,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                false,
                maxLiquidityPerTick
            );
            flippedUpper = ticks.update(
                tickUpper,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                true,
                maxLiquidityPerTick
            );

            if (flippedLower) {
                tickBitmap.flipTick(tickLower, tickSpacing);
            }
            if (flippedUpper) {
                tickBitmap.flipTick(tickUpper, tickSpacing);
            }
        }

        // TODO fees
        position.update(liquidityDelta, 0, 0);

        if (liquidityDelta < 0) {
            if (flippedLower) {
                ticks.clear(tickLower);
            }
            if (flippedUpper) {
                ticks.clear(tickUpper);
            }
        }
    }

    // Add this function to mint LP tokens
    function mintLPToken(address recipient, uint256 amount) private {
        lpToken.mint(recipient, amount);
    }

    // Add this function to burn LP tokens
    function burnLPToken(address tokenOwner, uint256 amount) private {
        lpToken.burn(tokenOwner, amount);
    }

    // Modify the mint function to handle maximum liquidity
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external lock returns (uint256 amount0, uint256 amount1) {
        require(amount > 0, "amount = 0");

        // Convert amount to int128 safely before passing to _modifyPosition
        int128 liquidityDelta;
        if (amount <= uint128(type(int128).max)) {
            liquidityDelta = int128(amount);
        } else {
            revert("Amount exceeds max int128");
        }

        // Update liquidity before minting LP tokens
        liquidity += uint128(amount);

        (
            Position.Info storage position,
            int256 amount0Int,
            int256 amount1Int
        ) = _modifyPosition(
                ModifyPositionParams({
                    owner: recipient,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: liquidityDelta
                })
            );

        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        // Update position's tokens owed based on amounts
        if (amount0Int > 0 || amount1Int > 0) {
            position.tokensOwed0 += uint256(amount0Int).toUint128();
            position.tokensOwed1 += uint256(amount1Int).toUint128();
        }

        // Calculate LP token amount based on the provided liquidity
        uint256 lpAmount = _calculateLPTokenAmount(
            amount0,
            amount1,
            slot0_.sqrtPriceX96
        );
        if (lpAmount == 0) lpAmount = amount; // Fallback to using the input amount if calculation is zero

        // Mint LP tokens and update state before external calls
        mintLPToken(recipient, lpAmount);
        liquidityMining.notifyLiquidityAdded(recipient, lpAmount);

        // Perform external calls after state updates
        if (amount0 > 0) {
            require(
                IERC20(token0).transferFrom(msg.sender, address(this), amount0),
                "Transfer of token0 failed"
            );
        }
        if (amount1 > 0) {
            require(
                IERC20(token1).transferFrom(msg.sender, address(this), amount1),
                "Transfer of token1 failed"
            );
        }

        emit Mint(
            msg.sender,
            recipient,
            tickLower,
            tickUpper,
            amount,
            amount0,
            amount1
        );
    }

    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external lock returns (uint128 amount0, uint128 amount1) {
        Position.Info storage position = positions.get(
            msg.sender,
            tickLower,
            tickUpper
        );

        amount0 = amount0Requested > position.tokensOwed0
            ? position.tokensOwed0
            : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1
            ? position.tokensOwed1
            : amount1Requested;

        // Update state before external calls
        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
        }
        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
        }

        // Perform external calls after state updates
        if (amount0 > 0) {
            require(
                IERC20(token0).transfer(recipient, amount0),
                "Transfer of token0 failed"
            );
        }
        if (amount1 > 0) {
            require(
                IERC20(token1).transfer(recipient, amount1),
                "Transfer of token1 failed"
            );
        }
    }

    // Modify the burn function to also burn LP tokens
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external lock returns (uint256 amount0, uint256 amount1) {
        // Add validation for amount
        require(amount > 0, "Amount must be greater than 0");
        require(
            amount <= uint128(type(int128).max),
            "Amount exceeds max int128"
        );

        // Update liquidity before modifying position
        if (amount > liquidity) {
            revert("Insufficient liquidity");
        }
        liquidity -= amount;

        (
            Position.Info storage position,
            int256 amount0Int,
            int256 amount1Int
        ) = _modifyPosition(
                ModifyPositionParams({
                    owner: msg.sender,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: -int128(amount)
                })
            );

        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        if (amount0 > 0 || amount1 > 0) {
            (position.tokensOwed0, position.tokensOwed1) = (
                position.tokensOwed0 + uint128(amount0),
                position.tokensOwed1 + uint128(amount1)
            );
        }

        // Burn LP tokens before emitting event
        burnLPToken(msg.sender, amount);

        // Notify LiquidityMining contract
        liquidityMining.notifyLiquidityRemoved(msg.sender, amount);

        emit Burn(msg.sender, tickLower, tickUpper, amount, amount0, amount1);
    }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external override returns (int256 amount0, int256 amount1) {
        require(amountSpecified != 0, "AS");


        SwapMath.StepComputations memory stepState;

        require(
            zeroForOne
                ? sqrtPriceLimitX96 < slot0_.sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 > slot0_.sqrtPriceX96 && sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
            "SPL"
        );

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0_.sqrtPriceX96,
            tick: slot0_.tick,
            feeGrowthGlobalX128: zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
            liquidity: liquidity
        });

        while (
            state.amountSpecifiedRemaining != 0 && 
            state.sqrtPriceX96 != sqrtPriceLimitX96
        ) {
            // Find the next initialized tick
            (stepState.tickNext, stepState.initialized) = zeroForOne 
                ? tickBitmap.nextInitializedTickWithinOneWord(
                    state.tick,
                    tickSpacing,
                    false
                )
                : (tickBitmap.nextInitializedTickWithinOneWord(
                    state.tick,
                    tickSpacing,
                    true
                ));

            // Calculate the next sqrt price
            stepState.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(stepState.tickNext);

            // Make sure we don't exceed the price limit
            if (zeroForOne) {
                stepState.sqrtPriceNextX96 = Math.min(
                    stepState.sqrtPriceNextX96,
                    sqrtPriceLimitX96
                );
            } else {
                stepState.sqrtPriceNextX96 = Math.max(
                    stepState.sqrtPriceNextX96,
                    sqrtPriceLimitX96
                );
            }

            (stepState.sqrtPriceNextX96, stepState.amountIn, stepState.amountOut, stepState.feeAmount) = SwapMath
                .computeSwapStep(
                    state.sqrtPriceX96,
                    stepState.sqrtPriceNextX96,
                    state.liquidity,
                    state.amountSpecifiedRemaining,
                    fee
                );

            // Calculate protocol fee portion
            uint256 protocolFeePortion = (stepState.feeAmount * protocolFee) / PROTOCOL_FEE_DENOMINATOR;
            
            // Accumulate protocol fees
            if (zeroForOne) {
                protocolFees0 += protocolFeePortion;
            } else {
                protocolFees1 += protocolFeePortion;
            }

            state.sqrtPriceX96 = stepState.sqrtPriceNextX96;
            state.amountSpecifiedRemaining -= (stepState.amountIn + stepState.feeAmount).toInt256();
            state.amountCalculated -= stepState.amountOut.toInt256();

            if (state.sqrtPriceX96 == stepState.sqrtPriceNextX96) {
                int128 liquidityNet = ticks.cross(
                    stepState.tickNext,
                    (zeroForOne ? state.feeGrowthGlobalX128 : state.feeGrowthGlobalX128),
                    (zeroForOne ? state.feeGrowthGlobalX128 : state.feeGrowthGlobalX128)
                );
                state.liquidity = liquidityNet < 0
                    ? state.liquidity - uint128(-liquidityNet)
                    : state.liquidity + uint128(liquidityNet);
                state.tick = zeroForOne ? stepState.tickNext - 1 : stepState.tickNext;
            } else {
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        if (state.tick != slot0_.tick) {
            (slot0_.sqrtPriceX96, slot0_.tick) = (state.sqrtPriceX96, state.tick);
        }

        if (liquidity != state.liquidity) liquidity = state.liquidity;

        (amount0, amount1) = zeroForOne
            ? (
                amountSpecified - state.amountSpecifiedRemaining,
                state.amountCalculated
            )
            : (
                state.amountCalculated,
                amountSpecified - state.amountSpecifiedRemaining
            );

        if (zeroForOne) {
            IERC20(token1).transfer(recipient, uint256(-amount1));
            uint256 balance0Before = IERC20(token0).balanceOf(address(this));
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
                amount0,
                amount1,
                data
            );
            require(balance0Before + uint256(amount0) <= IERC20(token0).balanceOf(address(this)), "IIA");
        } else {
            IERC20(token0).transfer(recipient, uint256(-amount0));
            uint256 balance1Before = IERC20(token1).balanceOf(address(this));
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
                amount0,
                amount1,
                data
            );
            require(balance1Before + uint256(amount1) <= IERC20(token1).balanceOf(address(this)), "IIA");
        }

        emit Swap(
            msg.sender,
            recipient,
            amount0,
            amount1,
            slot0_.sqrtPriceX96,
            state.liquidity,
            slot0_.tick
        );
    }

    // Implement the collectProtocolFees function
    function collectProtocolFees(
        address recipient
    ) external returns (uint256 amount0, uint256 amount1) {
        require(
            msg.sender == address(feeCollector),
            "Only fee collector can collect fees"
        );

        amount0 = protocolFees0;
        amount1 = protocolFees1;

        if (amount0 > 0) {
            protocolFees0 = 0;
            require(
                IERC20(token0).transfer(recipient, amount0),
                "Transfer of token0 failed"
            );
        }
        if (amount1 > 0) {
            protocolFees1 = 0;
            require(
                IERC20(token1).transfer(recipient, amount1),
                "Transfer of token1 failed"
            );
        }
    }

    function getTokens() external view returns (address, address) {
        return (token0, token1);
    }

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1)
    {
        Slot0 memory slot0Start = slot0_;
        uint128 _liquidity = liquidity;

        if (_liquidity == 0) {
            return (0, 0);
        }

        uint160 sqrtPriceX96 = slot0Start.sqrtPriceX96;
        int24 tick = slot0Start.tick;

        // Calculate the range of the current tick
        int24 tickLower = tick - (tick % tickSpacing);
        int24 tickUpper = tickLower + tickSpacing;

        // Calculate sqrtRatioA and sqrtRatioB
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        // Calculate the reserves using the SqrtPriceMath library
        uint256 amount0 = sqrtRatioAX96.getAmount0Delta(
            sqrtRatioBX96,
            _liquidity,
            true // roundUp
        );
        uint256 amount1 = sqrtRatioAX96.getAmount1Delta(
            sqrtRatioBX96,
            _liquidity,
            true // roundUp
        );

        // Adjust the amounts based on the current price within the range
        amount0 += sqrtPriceX96.getAmount0Delta(
            sqrtRatioBX96,
            _liquidity,
            true // roundUp
        );
        amount1 += sqrtRatioAX96.getAmount1Delta(
            sqrtPriceX96,
            _liquidity,
            true // roundUp
        );

        // Add checks before casting
        require(amount0 <= type(uint112).max, "amount0 exceeds uint112");
        require(amount1 <= type(uint112).max, "amount1 exceeds uint112");

        // Cast to uint112 using direct casting since we've already checked the bounds
        reserve0 = uint112(amount0);
        reserve1 = uint112(amount1);
    }

    // Add this function
    function isOwner(address account) public view returns (bool) {
        // Add a check for zero address
        if (account == address(0)) return false;

        // Check if the account is one of the owners
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == account) {
                return true;
            }
        }
        return false;
    }

    // Add this function
    function _blockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp);
    }

    function slot0() external view returns (Slot0 memory) {
        return slot0_;
    }

    function owner() external view returns (address) {
        return owners[0];
    }

    function setProtocolFee(uint8 _protocolFee) external {
        require(isOwner(msg.sender), "Not authorized");
        require(_protocolFee <= PROTOCOL_FEE_DENOMINATOR, "Invalid fee");
        protocolFee = _protocolFee;
        emit ProtocolFeeChanged(_protocolFee);
    }

    function pause() external {
        require(isOwner(msg.sender), "Not an owner");
        require(!paused, "Already paused");

        // Add a more stringent owner check
        bool foundOwner = false;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == msg.sender) {
                foundOwner = true;
                break;
            }
        }
        require(foundOwner, "Not an owner");

        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external {
        require(isOwner(msg.sender), "Not authorized");
        require(paused, "Not paused");
        paused = false;
        emit Unpaused(msg.sender);
    }

    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external lock whenNotPaused {
        require(amount0 > 0 || amount1 > 0, "amount0 = amount1 = 0");

        uint256 fee0 = FullMath.mulDivRoundingUp(amount0, uint256(fee), 1e6);
        uint256 fee1 = FullMath.mulDivRoundingUp(amount1, uint256(fee), 1e6);

        uint256 balance0Before = IERC20(token0).balanceOf(address(this));
        uint256 balance1Before = IERC20(token1).balanceOf(address(this));

        if (amount0 > 0) {
            require(
                IERC20(token0).transfer(recipient, amount0),
                "Transfer of token0 failed"
            );
        }
        if (amount1 > 0) {
            require(
                IERC20(token1).transfer(recipient, amount1),
                "Transfer of token1 failed"
            );
        }

        IFlashCallback(msg.sender).flashCallback(fee0, fee1, data);

        uint256 balance0After = IERC20(token0).balanceOf(address(this));
        uint256 balance1After = IERC20(token1).balanceOf(address(this));

        require(
            balance0Before + fee0 <= balance0After,
            "Flash: amount0 not returned"
        );
        require(
            balance1Before + fee1 <= balance1After,
            "Flash: amount1 not returned"
        );

        // Update protocol fees
        uint256 protocolFee0 = (fee0 * protocolFee) / PROTOCOL_FEE_DENOMINATOR;
        uint256 protocolFee1 = (fee1 * protocolFee) / PROTOCOL_FEE_DENOMINATOR;
        protocolFees0 += protocolFee0;
        protocolFees1 += protocolFee1;

        emit Flash(msg.sender, recipient, amount0, amount1, fee0, fee1);
    }

    function observeSingle(
        uint32 secondsAgo
    )
        external
        view
        returns (
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128
        )
    {
        return Oracle.observeSingle(observations, secondsAgo);
    }

    function addLiquidity(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1) {
        // This can be implemented similarly to mint() but with additional data parameter
        require(amount > 0, "amount = 0");

        (
            Position.Info storage position,
            int256 amount0Int,
            int256 amount1Int
        ) = _modifyPosition(
                ModifyPositionParams({
                    owner: recipient,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: int128(uint128(amount))
                })
            );

        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        // Update position's tokens owed based on amounts
        if (amount0Int > 0 || amount1Int > 0) {
            position.tokensOwed0 += uint256(amount0Int).toUint128();
            position.tokensOwed1 += uint256(amount1Int).toUint128();
        }

        // Mint LP tokens and update state before external calls
        uint256 lpAmount = amount; // You might want to use a different calculation here
        mintLPToken(recipient, lpAmount);
        liquidityMining.notifyLiquidityAdded(recipient, lpAmount);

        // Perform external calls after state updates
        if (amount0 > 0) {
            require(
                IERC20(token0).transferFrom(msg.sender, address(this), amount0),
                "Transfer of token0 failed"
            );
        }
        if (amount1 > 0) {
            require(
                IERC20(token1).transferFrom(msg.sender, address(this), amount1),
                "Transfer of token1 failed"
            );
        }

        emit LiquidityAdded(
            msg.sender,
            recipient,
            tickLower,
            tickUpper,
            amount,
            amount0,
            amount1,
            data
        );
    }

    function removeLiquidity(
        address inputToken0,
        address inputToken1,
        uint24 poolFee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidityAmount
    ) external override returns (uint256 amount0, uint256 amount1) {
        require(inputToken0 == address(this.token0()), "Wrong token0");
        require(inputToken1 == address(this.token1()), "Wrong token1");
        require(poolFee == this.fee(), "Wrong fee");

        // Burn the liquidity and receive tokens
        return this.burn(tickLower, tickUpper, liquidityAmount);
    }

    /// @notice Adds liquidity to a position in the pool
    /// @param inputToken0 The address of the first token
    /// @param inputToken1 The address of the second token
    /// @param poolFee The fee tier of the pool
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount0Desired The desired amount of token0 to add
    /// @param amount1Desired The desired amount of token1 to add
    /// @param amount0Min The minimum amount of token0 to add
    /// @param amount1Min The minimum amount of token1 to add
    /// @return liquidityAdded The amount of liquidity added to the position
    /// @return amount0 The actual amount of token0 added to the position
    /// @return amount1 The actual amount of token1 added to the position
    function addLiquidity(
        address inputToken0,
        address inputToken1,
        uint24 poolFee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        override
        returns (uint128 liquidityAdded, uint256 amount0, uint256 amount1)
    {
        require(
            inputToken0 == address(this.token0()),
            "CLAMM: Token0 address mismatch"
        );
        require(
            inputToken1 == address(this.token1()),
            "CLAMM: Token1 address mismatch"
        );
        require(poolFee == this.fee(), "CLAMM: Fee tier mismatch");

        // Calculate optimal liquidity amount based on desired amounts
        uint128 optimalLiquidity = _calculateOptimalLiquidity(
            tickLower,
            tickUpper,
            uint128(amount0Desired),
            uint128(amount1Desired)
        );

        // Add liquidity using the calculated optimal amount
        (amount0, amount1) = this.mint(
            msg.sender,
            tickLower,
            tickUpper,
            optimalLiquidity
        );

        // Verify minimum amounts are satisfied
        require(amount0 >= amount0Min, "CLAMM: Insufficient token0 output");
        require(amount1 >= amount1Min, "CLAMM: Insufficient token1 output");

        liquidityAdded = optimalLiquidity;
        return (liquidityAdded, amount0, amount1);
    }

    /// @notice Calculates the optimal liquidity amount based on desired token amounts
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount0Desired The desired amount of token0
    /// @param amount1Desired The desired amount of token1
    /// @return The optimal liquidity amount
    function _calculateOptimalLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) private pure returns (uint128) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        // Calculate liquidity amounts for both tokens
        uint128 liquidity0 = uint128(
            SqrtPriceMath.getAmount0Delta(
                sqrtRatioAX96,
                sqrtRatioBX96,
                uint128(amount0Desired),
                true
            )
        );
        uint128 liquidity1 = uint128(
            SqrtPriceMath.getAmount1Delta(
                sqrtRatioAX96,
                sqrtRatioBX96,
                uint128(amount1Desired),
                true
            )
        );

        // Return the minimum of the two liquidity amounts
        return liquidity0 < liquidity1 ? liquidity0 : liquidity1;
    }

    function setLiquidityMining(address _liquidityMining) external onlyOwner {
        require(_liquidityMining != address(0), "Invalid address");
        address oldLiquidityMining = address(liquidityMining);
        liquidityMining = LiquidityMining(_liquidityMining);
        emit LiquidityMiningSet(oldLiquidityMining, _liquidityMining);
    }

    // Add event declaration at contract level
    event LiquidityMiningSet(
        address indexed oldLiquidityMining,
        address indexed newLiquidityMining
    );

    function _calculateLPTokenAmount(
        uint256 amount0,
        uint256 amount1,
        uint160 sqrtPriceX96
    ) private pure returns (uint256) {
        // Calculate the geometric mean of the amounts
        uint256 value0 = FullMath.mulDiv(
            amount0,
            sqrtPriceX96,
            FixedPoint96.Q96
        );
        uint256 value1 = amount1;

        // Calculate square root using binary search
        uint256 z = (value0 * value1 + 1) >> 1;
        uint256 y = value0 * value1;
        while (z < y) {
            y = z;
            z = ((value0 * value1) / z + z) >> 1;
        }
        return y;
    }

    function emergencyWithdraw(
        address token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        require(paused, "Contract must be paused");
        if (!IERC20(token).transfer(recipient, amount)) {
            revert EmergencyActionFailed();
        }
        emit EmergencyWithdraw(token, recipient, amount);
    }

    function emergencySetFeeCollector(
        address newFeeCollector
    ) external onlyOwner {
        require(paused, "Contract must be paused");
        require(newFeeCollector != address(0), "Invalid address");
        feeCollector = IFeeCollector(newFeeCollector);
        emit EmergencyFeeCollectorSet(address(feeCollector), newFeeCollector);
    }
}
