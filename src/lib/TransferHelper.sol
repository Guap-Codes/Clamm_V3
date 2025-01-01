// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

library TransferHelper {
    /// @notice Transfers tokens from the targeted address to the given destination
    /// @notice Errors with 'TransferHelper: TRANSFER_FROM_FAILED'
    /// @param token The contract address of the token to be transferred
    /// @param from The originating address from which the tokens will be transferred
    /// @param to The destination address of the transfer
    /// @param value The amount to be transferred
    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call{gas: 50000}(abi.encodeWithSelector(0x23b872dd, from, to, value));
        if (!success) {
            revert("TransferHelper: TRANSFER_FAILED");
        }
        if (data.length > 0) {
            require(abi.decode(data, (bool)), "TransferHelper: TRANSFER_FAILED");
        }
    }

    /// @notice Transfers tokens from msg.sender to a recipient
    /// @notice Errors with 'TransferHelper: TRANSFER_FAILED'
    /// @param token The contract address of the token to be transferred
    /// @param to The recipient of the transfer
    /// @param value The value of the transfer
    function safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call{gas: 50000}(abi.encodeWithSelector(0xa9059cbb, to, value));
        if (!success) {
            revert("TransferHelper: TRANSFER_FAILED");
        }
        if (data.length > 0) {
            require(abi.decode(data, (bool)), "TransferHelper: TRANSFER_FAILED");
        }
    }

    /// @notice Approves the stipulated contract to spend the given allowance in the given token
    /// @notice Errors with 'TransferHelper: APPROVE_FAILED'
    /// @param token The contract address of the token to be approved
    /// @param to The target of the approval
    /// @param value The amount of the given token the target will be allowed to spend
    function safeApprove(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call{gas: 50000}(abi.encodeWithSelector(0x095ea7b3, to, value));
        if (!success) {
            revert("TransferHelper: APPROVE_FAILED");
        }
        if (data.length > 0) {
            require(abi.decode(data, (bool)), "TransferHelper: APPROVE_FAILED");
        }
    }
}
