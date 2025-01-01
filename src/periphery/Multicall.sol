// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title Multicall
/// @notice Enables calling multiple methods in a single call to the contract
/// @dev Inherits ReentrancyGuard to prevent reentrancy attacks during multiple calls
contract Multicall is ReentrancyGuard {
    /// @notice Represents a single call to be executed
    /// @param target The address of the contract to call
    /// @param callData The encoded function data to be sent to the target
    struct Call {
        address target;
        bytes callData;
    }

    /// @notice Executes multiple calls in a single transaction
    /// @dev Uses nonReentrant modifier to prevent reentrancy attacks
    /// @param calls Array of Call structs containing target addresses and call data
    /// @return results Array of bytes containing the results of each call
    function multicall(Call[] memory calls) public nonReentrant returns (bytes[] memory results) {
        require(calls.length <= 20, "Multicall: too many calls");
        results = new bytes[](calls.length);

        uint256 gasLeftStart = gasleft();
        uint256 gasPerCall = 5_000_000;
        require(gasLeftStart >= calls.length * gasPerCall, "Multicall: insufficient gas");

        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory result) = executeCall(calls[i]);
            require(success, "Multicall: call failed");
            results[i] = result;
        }

        return results;
    }

    /// @notice Executes a single call to a target contract
    /// @dev Internal function with a gas limit of 5,000,000
    /// @param call The Call struct containing target address and call data
    /// @return success Boolean indicating if the call was successful
    /// @return result Bytes containing the return data from the call
    function executeCall(Call memory call) internal returns (bool success, bytes memory result) {
        (success, result) = call.target.call{gas: 5000000}(call.callData);
    }
}
