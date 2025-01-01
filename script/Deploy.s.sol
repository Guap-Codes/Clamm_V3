// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {CLAMM as Clamm} from "../src/Clamm.sol";
import {LiquidityMining} from "../src/periphery/LiquidityMining.sol";
import {PineToken} from "../src/PineToken.sol";
import {FeeCollector} from "../src/periphery/FeeCollector.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICLAMM} from "../src/interfaces/ICLAMM.sol";

contract DeployScript is Script {
    // Configuration variables
    address constant rewardTokenAddress = address(0xdef); // Replace with actual reward token
    uint256 constant rewardPerBlock = 1e18;              // 1 token per block
    address constant clammAddress = address(0);          // Will be updated after CLAMM deployment

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Create the required addresses array for owners
        address[3] memory owners = [
            msg.sender,
            address(0x123), // Replace with actual second owner address
            address(0x456)  // Replace with actual third owner address
        ];

        // Deploy LiquidityMining contract first (or use existing address)
        LiquidityMining liquidityMining = new LiquidityMining(
            IERC20(rewardTokenAddress),  // Address of reward token
            rewardPerBlock,              // Amount of rewards per block
            block.number,                // Current block number as start
            ICLAMM(clammAddress)        // CLAMM contract address/* constructor args */);
        );
                    
        // Deploy PineToken first (or use existing address)
        PineToken lpToken = new PineToken(/* constructor args */);

        // Deploy CLAMM with all required parameters
        Clamm clamm = new Clamm(
            address(0x789),  // token0 address
            address(0xabc),  // token1 address
            3000,           // fee (0.3%)
            60,            // tickSpacing
            owners,        // owners array
            address(liquidityMining), // liquidityMining address
            address(lpToken)  // lpToken address
        );

        // Set CLAMM address in LP token
        lpToken.setCLAMM(address(clamm));

        // Deploy FeeCollector
        address[] memory feeSigners = new address[](3);
        feeSigners[0] = msg.sender;
        feeSigners[1] = address(0x123); // Replace with actual signer
        feeSigners[2] = address(0x456); // Replace with actual signer
        
        FeeCollector feeCollector = new FeeCollector(
            msg.sender,      // fee recipient
            feeSigners,      // signers array
            2               // required signatures
        );

        // Initialize CLAMM
        clamm.setLiquidityMining(address(liquidityMining));
        clamm.emergencySetFeeCollector(address(feeCollector));
        clamm.initialize(79228162514264337593543950336); // Initial sqrt price

        // Add liquidity mining pool
        liquidityMining.add(100, IERC20(address(lpToken))); // 100 = allocation points

        console2.log("Deployment Addresses:");
        console2.log("CLAMM:", address(clamm));
        console2.log("Fee Collector:", address(feeCollector));
        console2.log("Liquidity Mining:", address(liquidityMining));
        console2.log("LP Token:", address(lpToken));

        vm.stopBroadcast();
    }
} 