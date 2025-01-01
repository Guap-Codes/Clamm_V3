# CLAMM (Concentrated Liquidity Automated Market Maker)

A concentrated liquidity automated market maker implementation inspired by Uniswap v3, built with Foundry.

## Overview

CLAMM is a decentralized exchange protocol that implements concentrated liquidity, allowing liquidity providers to specify custom price ranges for their positions. The protocol is built with a focus on gas efficiency and robust testing.

## Core Components

### Contracts

Core:
- `Clamm.sol`: Core AMM implementation with concentrated liquidity functionality
- `PineToken.sol`: LP token implementation for liquidity providers

Periphery:
- `FeeCollector.sol`: Handles protocol fee collection and distribution
- `LiquidityMining.sol`: Manages liquidity mining rewards and staking
- `Multicall.sol`: Enables batching multiple calls in a single transaction
- `ClammPositionManager.sol`: Manages non-fungible positions
- `ClammRouter.sol`: Router for interacting with the AMM
- `ClammQuoter.sol`: Quoter for calculating prices and amounts
- `StakingRewards.sol`: Manages staking rewards
- `V3Migrator.sol`: Migrator for migrating from V2 to V3


Interfaces:
- `ICLAMM.sol`: Interface defining core AMM functionality
- `IERC20.sol`: Interface for ERC20 token standard
- `IFeeCollector.sol`: Interface for fee collector functionality
- `IFlashCallback.sol`: Interface for flash loan callback functionality
- `INonfungiblePositionManager.sol`: Interface for non-fungible position manager
- `IV2Pair.sol`: Interface for V2 pair functionality


Libraries:
- Math:
  - `BitMath.sol`: Bit manipulation utilities
  - `FixedPoint96.sol`: Fixed-point arithmetic with 96 bits of precision
  - `FullMath.sol`: Safe 512-bit math operations
  - `LowGasSafeMath.sol`: Gas-optimized safe math operations
  - `SqrtPriceMath.sol`: Square root price calculations
  - `SwapMath.sol`: Core swap computation logic
  - `TickMath.sol`: Tick-related calculations
  - `UnsafeMath.sol`: Unchecked math operations for gas optimization
- Utils:
  - `SafeCast.sol`: Safe type casting utilities
  - `TransferHelper.sol`: Safe token transfer utilities


### Testing

The project includes comprehensive test suites:
- `CLAMMTest.t.sol`: Unit tests covering core functionality
- `CLAMMInvariantTest.t.sol`: Invariant tests ensuring protocol safety properties

## Installation

1. Install [Foundry](https://book.getfoundry.sh/getting-started/installation)
2. Clone the repository:

```bash
git clone [repository-url]
cd clamm
```

3. Install dependencies:

```bash
forge install
```

## Testing

Run the test suite:

```bash
forge test
```
For detailed test output: 

```bash
forge test -vvvv
```

Run invariant tests:

```bash
forge test --match-contract CLAMMInvariantTest
```


## Key Features

- **Concentrated Liquidity**: Liquidity providers can specify custom price ranges
- **Efficient Fee Collection**: Dedicated fee collector contract for protocol fees
- **Comprehensive Testing**: Both unit and invariant tests ensuring protocol safety
- **Gas Optimized**: Implemented with gas efficiency in mind

## Development

Built using:
- Solidity 0.8.24
- Foundry for development and testing
- Extensive math libraries for precision calculations

## License

[MIT](LICENSE)
