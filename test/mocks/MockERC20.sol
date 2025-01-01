// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20
/// @notice A mock ERC20 token contract for testing purposes
/// @dev Extends OpenZeppelin's ERC20 implementation with mint and burn capabilities
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    /// @notice Constructs a new MockERC20 token
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals_ The number of decimals for the token
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    /// @notice Mints new tokens
    /// @param account The address that will receive the minted tokens
    /// @param amount The amount of tokens to mint
    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    /// @notice Burns tokens from an account
    /// @param account The address whose tokens will be burned
    /// @param amount The amount of tokens to burn
    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    /// @notice Returns the number of decimals used for token amounts
    /// @return The number of decimals
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
