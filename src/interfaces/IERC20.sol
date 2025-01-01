// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

/// @title IERC20 Interface
/// @notice Standard interface for ERC20 tokens
/// @dev Implementation of the ERC20 interface as defined in the EIP-20
interface IERC20 {
    /// @notice Returns the total token supply
    /// @return The total supply of tokens
    function totalSupply() external view returns (uint256);

    /// @notice Returns the token balance of an account
    /// @param account The address to query the balance of
    /// @return The token balance of the specified account
    function balanceOf(address account) external view returns (uint256);

    /// @notice Transfers tokens to a specified address
    /// @param recipient The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @return success True if the transfer succeeded
    function transfer(address recipient, uint256 amount) external returns (bool);

    /// @notice Returns the remaining allowance of a spender
    /// @param owner The address that owns the tokens
    /// @param spender The address that can spend the tokens
    /// @return The remaining number of tokens allowed to be spent
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Approves an address to spend tokens
    /// @param spender The address authorized to spend tokens
    /// @param amount The amount of tokens authorized to be spent
    /// @return success True if the approval succeeded
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Transfers tokens from one address to another
    /// @param sender The address to transfer tokens from
    /// @param recipient The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @return success True if the transfer succeeded
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /// @notice Emitted when tokens are transferred
    /// @param from The address tokens are transferred from
    /// @param to The address tokens are transferred to
    /// @param value The amount of tokens transferred
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted when token spending is approved
    /// @param owner The address that owns the tokens
    /// @param spender The address authorized to spend the tokens
    /// @param value The amount of tokens approved to spend
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
