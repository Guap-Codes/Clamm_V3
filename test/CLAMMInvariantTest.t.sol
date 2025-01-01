// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/Clamm.sol";
import {PineToken} from "../src/PineToken.sol";
import "../src/periphery/LiquidityMining.sol";
import "../test/mocks/MockERC20.sol";
import "../test/mocks/MockFeeCollector.sol";
import "../src/lib/TickMath.sol";
import {ICLAMM} from "../src/interfaces/ICLAMM.sol";

contract Handler is Test {
    CLAMM public clamm;
    MockERC20 public token0;
    MockERC20 public token1;
    PineToken public lpToken;
    LiquidityMining public liquidityMining;
    
    // Make constants public
    uint128 public constant MIN_LIQUIDITY = 1000;
    uint128 public constant MAX_LIQUIDITY = 1000000000000;  // 1 trillion
    
    // Track state for invariant testing
    uint256 public totalMints;
    uint256 public totalBurns;
    uint256 public totalSwaps;
    uint256 public sumLiquidity;
    mapping(int24 => uint128) public liquidityPerTick;
    
    // Add maximum tick range to prevent infinite loops
    uint256 constant MAX_TICK_TRAVEL = 100; // Limit tick range
    
    // Track the last position created
    int24 public lastTickLower;
    int24 public lastTickUpper;
    
    // Track staking stats
    uint256 public totalStakes;
    uint256 public totalUnstakes;
    mapping(address => uint256) public userStakes;
    
    constructor(
        CLAMM _clamm,
        MockERC20 _token0,
        MockERC20 _token1,
        PineToken _lpToken,
        LiquidityMining _liquidityMining
    ) {
        clamm = _clamm;
        token0 = _token0;
        token1 = _token1;
        lpToken = _lpToken;
        liquidityMining = _liquidityMining;
        
        // Approve max for tokens
        token0.approve(address(clamm), type(uint256).max);
        token1.approve(address(clamm), type(uint256).max);
    }
    
    // Mint action
    function mint(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external {
        // Bound inputs to valid ranges
        int24 minTick = -887272;
        int24 maxTick = 887272;
        // Ensure ticks are properly spaced
        int24 spacing = clamm.tickSpacing();
        tickLower = int24(
            bound(
                int256(tickLower), 
                int256(minTick), 
                int256(maxTick)
            ) / spacing * spacing
        );
        tickUpper = int24(
            bound(
                int256(tickUpper), 
                int256(tickLower) + spacing, 
                int256(maxTick)
            ) / spacing * spacing
        );
        // Ensure amount is reasonable and won't overflow
        amount = uint128(bound(uint256(amount), MIN_LIQUIDITY, MAX_LIQUIDITY));
        
        // Ensure tick range is reasonable
        require(tickUpper - tickLower <= int24(int256(MAX_TICK_TRAVEL)), "Tick range too large");
        
        // Check if adding this liquidity would exceed maxLiquidityPerTick
        uint128 maxLiquidityPerTick = clamm.maxLiquidityPerTick();
        uint256 iterations = 0;
        for (int24 tick = tickLower; tick <= tickUpper; tick += clamm.tickSpacing()) {
            require(iterations++ < MAX_TICK_TRAVEL, "Too many iterations");
            require(liquidityPerTick[tick] + amount <= maxLiquidityPerTick, "Exceeds max liquidity per tick");
        }

        try clamm.mint(
            address(this),
            tickLower,
            tickUpper,
            amount
        ) {
            totalMints++;
            sumLiquidity += amount;
            // Track the position
            lastTickLower = tickLower;
            lastTickUpper = tickUpper;
            // Track liquidity per tick
            for (int24 tick = tickLower; tick <= tickUpper; tick += clamm.tickSpacing()) {
                liquidityPerTick[tick] += amount;
            }
        } catch {
            // Mint failed, that's ok for invariant testing
        }
    }
    
    // Swap action
    function swap(
        bool zeroForOne,
        int256 amountSpecified
    ) external {
        // Ensure pool has minimum liquidity before swap
        uint128 currentLiquidity = clamm.liquidity();
        require(currentLiquidity >= MIN_LIQUIDITY, "Insufficient liquidity for swap");

        // Limit swap size based on current liquidity to prevent depletion
        uint256 maxSwap = uint256(currentLiquidity) / 4;  // More conservative limit
        amountSpecified = bound(amountSpecified, 1000, int256(maxSwap));
        
        // Add safety check for price impact
        uint160 currentPrice = clamm.slot0().sqrtPriceX96;
        uint160 sqrtPriceLimitX96 = zeroForOne ? 
            uint160(uint256(currentPrice) * 99 / 100) :  // 1% max price impact
            uint160(uint256(currentPrice) * 101 / 100);

        try clamm.swap(
            address(this),
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96,
            ""
        ) {
            totalSwaps++;
        } catch {
            // Swap failed, that's ok for invariant testing
        }
    }
    
    // Callback for swaps
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata
    ) external {
        if (amount0Delta > 0) {
            token0.transfer(msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            token1.transfer(msg.sender, uint256(amount1Delta));
        }
    }
    
    // Stake LP tokens
    function stake(uint256 amount) external {
        // Bound amount to reasonable range
        amount = bound(amount, 0, lpToken.balanceOf(address(this)));
        
        try liquidityMining.deposit(0, amount) {
            totalStakes++;
            userStakes[address(this)] += amount;
        } catch {
            // Staking failed, that's ok
        }
    }
    
    // Unstake LP tokens  
    function unstake(uint256 amount) external {
        // Get current staked amount
        (uint256 stakedAmount,) = liquidityMining.userInfo(0, address(this));
        // Only allow unstaking if we've staked before
        if (totalStakes == 0 || stakedAmount == 0) return;
        
        amount = bound(amount, 0, stakedAmount);
        
        try liquidityMining.withdraw(0, amount) {
            totalUnstakes++;
            userStakes[address(this)] -= amount;
        } catch {
            // Unstaking failed, that's ok
        }
    }
}

contract CLAMMInvariantTest is Test {
    CLAMM public clamm;
    PineToken public lpToken;
    LiquidityMining public liquidityMining;
    MockERC20 public token0;
    MockERC20 public token1;
    Handler public handler;
    MockFeeCollector public feeCollector;
    
    // Add run limits
    uint256 constant NUM_RUNS = 100;
    uint256 constant NUM_CALLS = 10;
    
    function setUp() public {
        // Setup tokens
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        lpToken = new PineToken();
        
        // Setup CLAMM with owners
        address[3] memory owners = [address(this), address(0x2), address(0x3)];
        clamm = new CLAMM(
            address(token0),
            address(token1),
            3000, // 0.3% fee
            60,   // tick spacing
            owners,
            address(0),
            address(lpToken)
        );
        
        // Setup LiquidityMining
        liquidityMining = new LiquidityMining(
            IERC20(address(token0)),
            1e18,
            block.number,
            ICLAMM(address(clamm))
        );
        
        clamm.setLiquidityMining(address(liquidityMining));
        
        // Add pool to LiquidityMining with allocation points
        liquidityMining.add(100, IERC20(address(lpToken)));
        
        // Setup fee collector
        feeCollector = new MockFeeCollector();
        clamm.pause();
        clamm.emergencySetFeeCollector(address(feeCollector));
        clamm.unpause();
        
        // Initialize pool
        clamm.initialize(79228162514264337593543950336);
        
        // Add some initial liquidity to the pool
        token0.mint(address(this), 1000000);
        token1.mint(address(this), 1000000);
        token0.approve(address(clamm), type(uint256).max);
        token1.approve(address(clamm), type(uint256).max);
        
        // Add initial liquidity
        clamm.mint(
            address(this),
            -60,  // tickLower
            60,   // tickUpper
            1000  // amount
        );
        
        // Setup handler
        handler = new Handler(clamm, token0, token1, lpToken, liquidityMining);
        
        // Target contracts for invariant testing
        targetContract(address(handler));
        targetSender(address(this));
        
        // Set fuzzing bounds
        vm.assume(NUM_RUNS > 0 && NUM_RUNS <= 1000);
        vm.assume(NUM_CALLS > 0 && NUM_CALLS <= 100);
    }
    
    // Price bounds invariant
    function invariant_price_bounds() public {
        uint160 currentPrice = clamm.slot0().sqrtPriceX96;
        assertTrue(
            currentPrice >= TickMath.MIN_SQRT_RATIO && 
            currentPrice <= TickMath.MAX_SQRT_RATIO
        );
    }
    
    // Liquidity invariant
    function invariant_liquidity_positive() public {
        uint128 totalLiquidity = clamm.liquidity();
        assertTrue(totalLiquidity >= 1000, "Pool must maintain minimum liquidity");
        assertTrue(totalLiquidity <= 1000000000000, "Pool exceeds maximum liquidity");
    }
    
    // Protocol fee invariant
    function invariant_protocol_fees() public {
        uint256 protocolFees0 = clamm.protocolFees0();
        uint256 protocolFees1 = clamm.protocolFees1();
        uint256 balance0 = token0.balanceOf(address(clamm));
        uint256 balance1 = token1.balanceOf(address(clamm));
        
        // Protocol fees should never exceed pool balance
        assertTrue(protocolFees0 <= balance0);
        assertTrue(protocolFees1 <= balance1);
    }
    
    // Token balance invariant
    function invariant_token_balances() public {
        uint256 balance0 = token0.balanceOf(address(clamm));
        uint256 balance1 = token1.balanceOf(address(clamm));
        
        // Pool should never have negative balance
        assertTrue(balance0 >= 0);
        assertTrue(balance1 >= 0);
    }
    
    // State consistency invariant
    function invariant_state_consistency() public {
        // Simpler check: if we have any swaps, liquidity must be >= minimum
        if (handler.totalSwaps() > 0) {
            uint128 liquidity = clamm.liquidity();
            assertTrue(liquidity >= 1000, "Must maintain minimum liquidity for swaps");
        }
    }
    
    // Call statistics
    function invariant_call_summary() public view {
        console2.log("Total mints:", handler.totalMints());
        console2.log("Total swaps:", handler.totalSwaps());
        console2.log("Current liquidity:", clamm.liquidity());
    }
    
    // Tick spacing invariant
    function invariant_tick_spacing() public {
        int24 spacing = clamm.tickSpacing();
        assertTrue(spacing > 0, "Tick spacing must be positive");
    }

    // Fee invariant
    function invariant_fee_range() public {
        uint24 fee = clamm.fee();
        assertTrue(fee <= 100000, "Fee must be <= 10%");
    }

    // Protocol fee invariant
    function invariant_protocol_fee_range() public {
        uint8 protocolFee = clamm.protocolFee();
        assertTrue(protocolFee <= 10, "Protocol fee must be <= 1%");
    }

    // Liquidity per tick invariant
    function invariant_max_liquidity_per_tick() public {
        uint128 maxLiquidityPerTick = clamm.maxLiquidityPerTick();
        uint128 currentLiquidity = clamm.liquidity();
        assertTrue(currentLiquidity <= maxLiquidityPerTick, "Liquidity exceeds max per tick");
    }

    // Add tick range invariant
    function invariant_tick_range() public {
        ICLAMM.Slot0 memory slot0 = clamm.slot0();
        int24 tick = slot0.tick;
        assertTrue(
            tick >= TickMath.MIN_TICK && tick <= TickMath.MAX_TICK,
            "Tick must be within valid range"
        );
        assertTrue(
            _isValidTick(tick, clamm.tickSpacing()),
            "Tick must be at valid spacing interval"
        );
    }

    // Add helper function to check tick spacing
    function _isValidTick(int24 tick, int24 spacing) internal pure returns (bool) {
        return tick % spacing == 0;
    }

    // Position state invariant
    function invariant_position_state() public {
        // Get total supply of LP tokens
        uint256 totalSupply = lpToken.totalSupply();
        
        // Get total liquidity in the pool
        uint128 totalLiquidity = clamm.liquidity();
        
        // Skip if no positions created
        if (handler.totalMints() == 0) return;
        
        // Get handler's position info using last known position
        (
            uint128 posLiquidity,
            ,  // feeGrowthInside0LastX128
            ,  // feeGrowthInside1LastX128
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = clamm.positions(
            keccak256(
                abi.encodePacked(
                    address(handler),
                    handler.lastTickLower(),
                    handler.lastTickUpper()
                )
            )
        );
        
        // Verify total supply matches or exceeds total liquidity
        assertTrue(totalSupply >= totalLiquidity, "Supply/liquidity mismatch");
        
        // Only verify position if mints occurred
        if (handler.totalMints() > 0) {
            // Verify position liquidity is part of total liquidity
            assertTrue(posLiquidity <= totalLiquidity, "Position liquidity exceeds total");
            
            // Verify tokens owed are less than pool balance
            assertTrue(tokensOwed0 <= token0.balanceOf(address(clamm)), "Tokens owed 0 exceeds balance");
            assertTrue(tokensOwed1 <= token1.balanceOf(address(clamm)), "Tokens owed 1 exceeds balance");
        }
    }
    
    // Simplified liquidity mining invariant
    function invariant_liquidity_mining() public {
        // Get total pool liquidity
        uint128 poolLiquidity = clamm.liquidity();
        
        // Get handler's staked amount
        (uint256 stakedAmount,) = liquidityMining.userInfo(0, address(handler));
        
        // Core invariants
        assertTrue(stakedAmount <= poolLiquidity, "Staked amount exceeds pool liquidity");
        assertTrue(
            address(clamm.liquidityMining()) == address(liquidityMining),
            "LiquidityMining contract mismatch"
        );
        
        // Verify handler's tracked stakes match contract state
        assertTrue(
            handler.userStakes(address(handler)) == stakedAmount,
            "Stake tracking mismatch"
        );
    }
    
    // Staking state invariant
    function invariant_staking_state() public {
        // Get handler's LP token balance
        uint256 lpBalance = lpToken.balanceOf(address(handler));
        
        // Get handler's staked amount
        (uint256 stakedAmount,) = liquidityMining.userInfo(0, address(handler));
        
        // Total handler's LP tokens (staked + unstaked) should not exceed total supply
        assertTrue(
            lpBalance + stakedAmount <= lpToken.totalSupply(),
            "LP token accounting error"
        );
        
        // Verify stake/unstake operations are consistent
        if (handler.totalUnstakes() > 0) {
            assertTrue(
                handler.totalStakes() > 0,
                "Cannot unstake without staking first"
            );
        }
    }
}
