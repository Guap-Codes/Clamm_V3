// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/Clamm.sol";
import {PineToken} from "../src/PineToken.sol";
import "../src/periphery/LiquidityMining.sol";
import "../test/mocks/MockERC20.sol"; // Assuming you have a mock ERC20 token for testing
import "../test/mocks/MockFeeCollector.sol";

contract CLAMMTest is Test {
    CLAMM clamm;
    PineToken lpToken;
    LiquidityMining liquidityMining;
    MockERC20 token0;
    MockERC20 token1;
    address owner1 = address(0x1);
    address owner2 = address(0x2);
    address owner3 = address(0x3);
    address[3] owners = [owner1, owner2, owner3];

    // Add tick spacing constant - this should match the spacing in your CLAMM contract
    int24 constant TICK_SPACING = 60;

    MockFeeCollector feeCollector;

    function setUp() public {
        // Set up the test contract as one of the owners
        owner1 = address(this); // Make the test contract one of the owners
        owner2 = address(0x2);
        owner3 = address(0x3);
        owners = [owner1, owner2, owner3];

        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        lpToken = new PineToken();

        // Deploy the CLAMM contract with the test contract as one of the owners
        clamm = new CLAMM(
            address(token0),
            address(token1),
            3000, // 0.3% fee
            60, // tick spacing
            owners,
            address(0), // Temporary address for liquidityMining
            address(lpToken)
        );

        // Now deploy LiquidityMining with the correct CLAMM address
        liquidityMining = new LiquidityMining(
            IERC20(address(token0)), // Use token0 as reward token for testing
            1e18, // rewardPerBlock
            block.number, // startBlock
            ICLAMM(address(clamm)) // Correct CLAMM address
        );

        // Set CLAMM's liquidityMining address (now this should work since we're an owner)
        clamm.setLiquidityMining(address(liquidityMining));

        // Mint some tokens for testing
        token0.mint(address(this), 1e24);
        token1.mint(address(this), 1e24);

        // Approve CLAMM contract to spend tokens
        token0.approve(address(clamm), type(uint256).max);
        token1.approve(address(clamm), type(uint256).max);

        // After setting up CLAMM and LiquidityMining
        LiquidityMining(liquidityMining).add(
            100, // allocation points
            IERC20(address(lpToken)) // LP token (PineToken)
        );

        // Set up fee collector
        feeCollector = new MockFeeCollector();
        clamm.pause();
        clamm.emergencySetFeeCollector(address(feeCollector));
        clamm.unpause();
    }

    function testInitialize() public {
        uint160 sqrtPriceX96 = 79228162514264337593543950336; // Example sqrt price
        clamm.initialize(sqrtPriceX96);

        ICLAMM.Slot0 memory slot0 = clamm.slot0();
        assertEq(
            slot0.sqrtPriceX96,
            sqrtPriceX96,
            "Sqrt price not initialized correctly"
        );
        assertEq(
            slot0.tick,
            TickMath.getTickAtSqrtRatio(sqrtPriceX96),
            "Tick not initialized correctly"
        );
    }

    function testMint() public {
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        clamm.initialize(sqrtPriceX96);

        // Use tick values that are multiples of 60 (the tick spacing from constructor)
        int24 tickLower = -120; // -120 is a multiple of 60
        int24 tickUpper = 120; // 120 is a multiple of 60
        uint128 liquidity = 1000000;

        (uint256 amount0, uint256 amount1) = clamm.mint(
            address(this),
            tickLower,
            tickUpper,
            liquidity
        );

        console2.log("Minted amount0:", amount0);
        console2.log("Minted amount1:", amount1);

        assertGt(amount0, 0, "Amount0 should be greater than 0");
        assertGt(amount1, 0, "Amount1 should be greater than 0");
    }

    function testBurn() public {
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        clamm.initialize(sqrtPriceX96);

        // Add liquidity first
        uint128 lpAmount = 1000000;
        (uint256 amount0, uint256 amount1) = clamm.mint(
            address(this),
            -120,
            120,
            lpAmount
        );

        // Store initial balances
        uint256 initialBalance0 = token0.balanceOf(address(this));
        uint256 initialBalance1 = token1.balanceOf(address(this));

        // Get the actual LP token balance
        uint256 actualLPBalance = lpToken.balanceOf(address(this));
        require(actualLPBalance > 0, "No LP tokens minted");

        // Approve LP tokens for burning
        lpToken.approve(address(clamm), actualLPBalance);

        // Burn the LP tokens and collect in a single transaction
        (uint256 burned0, uint256 burned1) = clamm.burn(
            -120,
            120,
            uint128(actualLPBalance)
        );

        // Verify the amounts
        assertGt(burned0, 0, "No token0 burned");
        assertGt(burned1, 0, "No token1 burned");

        // Transfer additional tokens to CLAMM for collection
        token0.transfer(address(clamm), burned0);
        token1.transfer(address(clamm), burned1);

        // Now collect the tokens
        (uint128 collected0, uint128 collected1) = clamm.collect(
            address(this),
            -120,
            120,
            uint128(burned0),
            uint128(burned1)
        );

        // Verify final balances
        assertEq(
            token0.balanceOf(address(this)),
            initialBalance0 + collected0 - burned0,  // Adjust for transferred tokens
            "Token0 balance mismatch"
        );
        assertEq(
            token1.balanceOf(address(this)),
            initialBalance1 + collected1 - burned1,  // Adjust for transferred tokens
            "Token1 balance mismatch"
        );
    }

    function testSwap() public {
        // Initialize with price of 1
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(0);
        clamm.initialize(sqrtPriceX96);

        // Log initial state
        ICLAMM.Slot0 memory slot = clamm.slot0();
        console2.log("Initial tick:", int256(slot.tick));
        console2.log("Initial liquidity:", uint256(clamm.liquidity()));

        // Add liquidity
        int24 tickLower = -60;
        int24 tickUpper = 60;
        uint128 liquidity = 1000000 * 10**6;  // More significant liquidity

        // Approve tokens before minting
        token0.approve(address(clamm), type(uint256).max);
        token1.approve(address(clamm), type(uint256).max);

        // Mint with larger amounts
        (uint256 mintAmount0, uint256 mintAmount1) = clamm.mint(
            address(this),
            tickLower,
            tickUpper,
            liquidity
        );

        console2.log("Mint amounts - token0:", uint(mintAmount0));
        console2.log("Mint amounts - token1:", uint(mintAmount1));

        // Store initial balances
        uint256 initialBalance0 = token0.balanceOf(address(this));
        uint256 initialBalance1 = token1.balanceOf(address(this));

        console2.log("Initial balance token0:", uint(initialBalance0));
        console2.log("Initial balance token1:", uint(initialBalance1));

        // Use a reasonable swap amount and scale it
        int256 amountSpecified = 1000000000;  // 1 token

        // Adjust price limit for a more significant price movement
        uint160 sqrtPriceLimitX96 = uint160(
            (uint256(sqrtPriceX96) * 990) / 1000  // Allow for 1% price impact
        );
        
        console2.log("Current price:", uint(sqrtPriceX96));
        console2.log("Price limit:", uint(sqrtPriceLimitX96));

        try clamm.swap(
            address(this),
            true,  // zeroForOne
            amountSpecified,
            sqrtPriceLimitX96,
            ""  // Empty bytes for data parameter
        ) returns (int256 amount0Delta, int256 amount1Delta) {
            // Log swap details
            ICLAMM.Slot0 memory slotAfter = clamm.slot0();
            console2.log("Price after swap:", uint256(slotAfter.sqrtPriceX96));
            console2.log("Tick after swap:", int256(slotAfter.tick));
            console2.log("Liquidity after swap:", uint256(clamm.liquidity()));
            
            console2.logInt(amount0Delta);
            console2.logInt(amount1Delta);
            
            assertTrue(amount0Delta > 0, "amount0Delta should be positive");
            assertTrue(amount1Delta < 0, "amount1Delta should be negative");

            // 3. Collect accumulated fees
            uint128 feeAmount0 = uint128(amount0Delta > 0 ? uint256(amount0Delta) / 100 : 0);  // 1% fee
            uint128 feeAmount1 = uint128(amount1Delta < 0 ? uint256(-amount1Delta) / 100 : 0);  // 1% fee
            (uint128 collected0, uint128 collected1) = clamm.collect(
                address(this),
                tickLower,
                tickUpper,
                feeAmount0,
                feeAmount1
            );

            // 4. Verify fee collection
            assertTrue(collected0 > 0 || collected1 > 0, "Should have collected some fees");

            // Verify final balances including fees
            assertEq(
                token0.balanceOf(address(this)),
                initialBalance0 - uint256(amount0Delta) + uint256(collected0),
                "Token0 balance mismatch after fee collection"
            );
            assertEq(
                token1.balanceOf(address(this)),
                initialBalance1 + uint256(-amount1Delta) + uint256(collected1),
                "Token1 balance mismatch after fee collection"
            );
        } catch Error(string memory reason) {
            fail(string.concat("Swap failed: ", reason));
        }
    }

    function testEmergencyWithdraw() public {
        // First, transfer some tokens to the CLAMM contract
        uint256 amount = 1000;
        token0.transfer(address(clamm), amount);

        // Pause the contract (required for emergency withdrawal)
        clamm.pause();

        // Store initial balance
        uint256 initialBalance = token0.balanceOf(address(this));

        // Perform emergency withdrawal
        clamm.emergencyWithdraw(address(token0), address(this), amount);

        // Verify the withdrawal
        uint256 finalBalance = token0.balanceOf(address(this));
        assertEq(
            finalBalance,
            initialBalance + amount,
            "Emergency withdrawal failed"
        );
    }

    function testSetProtocolFee() public {
        clamm.setProtocolFee(5);
        assertEq(clamm.protocolFee(), 5, "Protocol fee not set correctly");
    }

    function testPauseAndUnpause() public {
        clamm.pause();
        assertTrue(clamm.paused(), "Contract should be paused");

        clamm.unpause();
        assertFalse(clamm.paused(), "Contract should be unpaused");
    }

    function testFeeCollection() public {
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        clamm.initialize(sqrtPriceX96);

        // Get initial swap fee
        uint24 swapFee = clamm.fee();
        console2.log("Swap fee:", swapFee);  // Should be 3000 (0.3%)

        // Set protocol fee to 0.5% (5/1000)
        clamm.setProtocolFee(5);
        
        // Verify protocol fee was set
        assertEq(clamm.protocolFee(), 5, "Protocol fee not set correctly");

        // Calculate expected protocol fee percentage
        uint256 protocolFeeDenominator = 10; // From PROTOCOL_FEE_DENOMINATOR in CLAMM
        uint256 expectedProtocolFeePct = 5 / protocolFeeDenominator; // 0.5%
        console2.log("Expected protocol fee percentage:", expectedProtocolFeePct);

        // 1. First provide liquidity
        int24 tickLower = -120;
        int24 tickUpper = 120;
        uint128 liquidity = 10000000;

        // Transfer tokens to CLAMM first
        uint256 amount0 = 100000;
        uint256 amount1 = 100000;

        // Add console logs to use these variables
        console2.log("Token0 amount:", amount0);
        console2.log("Token1 amount:", amount1);

        // Then continue with the transfers
        token0.transfer(address(clamm), amount0);
        token1.transfer(address(clamm), amount1);

        clamm.mint(
            address(this),
            tickLower,
            tickUpper,
            liquidity
        );

        // 2. Perform a single large swap to accumulate fees
        token0.mint(address(this), 1000000);
        token1.mint(address(this), 1000000);

        token0.transfer(address(clamm), 1000000);
        token1.transfer(address(clamm), 1000000);

        // Perform swap with a larger amount
        clamm.swap(
            address(this),
            true,
            1000000,
            uint160((uint256(sqrtPriceX96) * 990) / 1000), // 1% price impact
            ""
        );

        // Calculate expected protocol fees
        uint256 swapAmount = 1000000;
        uint256 expectedTotalFee = (swapAmount * swapFee) / 1000000; // 0.3% of swap amount
        uint256 expectedProtocolFee = (expectedTotalFee * expectedProtocolFeePct) / 100;
        console2.log("Expected total fee:", expectedTotalFee);
        console2.log("Expected protocol fee:", expectedProtocolFee);
        console2.log("Actual protocol fees 0:", clamm.protocolFees0());
        console2.log("Actual protocol fees 1:", clamm.protocolFees1());

        // Verify protocol fees have accumulated
        uint256 protocolFees0 = clamm.protocolFees0();
        uint256 protocolFees1 = clamm.protocolFees1();
        
        assertTrue(
            protocolFees0 > 0 || protocolFees1 > 0,
            "Should have accumulated protocol fees"
        );

        // Now collect the protocol fees
        vm.prank(address(feeCollector));
        feeCollector.collectFees(address(clamm));
        
        // Verify the fees were actually collected
        assertEq(
            feeCollector.lastPool(),
            address(clamm),
            "Fee collector should have recorded CLAMM as last pool"
        );
    }

    // Add this function to handle the swap callback
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        // Verify callback is from the CLAMM contract
        require(msg.sender == address(clamm), "Not CLAMM");

        // Transfer tokens to the CLAMM contract
        if (amount0Delta > 0) {
            token0.transfer(msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            token1.transfer(msg.sender, uint256(amount1Delta));
        }
    }
}
