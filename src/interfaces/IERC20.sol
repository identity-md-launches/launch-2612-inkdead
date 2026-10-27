// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title ERC-20 with the optional metadata extension
/// @notice The standard interface (EIP-20) plus `name`, `symbol` and `decimals`.
interface IERC20 {
    /// @notice Emitted when `value` tokens move from `from` to `to`. A mint has `from == address(0)`.
    event Transfer(address indexed from, address indexed to, uint256 value);
    /// @notice Emitted when `owner` sets the allowance of `spender` to `value`.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice Human-readable token name.
    function name() external view returns (string memory);
    /// @notice Ticker symbol.
    function symbol() external view returns (string memory);
    /// @notice Number of decimals the token is displayed with.
    function decimals() external view returns (uint8);

    /// @notice Tokens in existence.
    function totalSupply() external view returns (uint256);
    /// @notice Tokens held by `account`.
    function balanceOf(address account) external view returns (uint256);
    /// @notice Tokens `spender` may still move out of `owner` through `transferFrom`.
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Moves `value` tokens from the caller to `to`.
    function transfer(address to, uint256 value) external returns (bool);
    /// @notice Sets the caller's allowance for `spender` to `value`.
    function approve(address spender, uint256 value) external returns (bool);
    /// @notice Moves `value` tokens from `from` to `to` using the caller's allowance.
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}
