// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "./interfaces/IERC20.sol";

/// @title InkDead (IDEAD)
/// @notice A plain, fixed-supply ERC-20. The whole supply is minted once, in the constructor, to the
/// deployer (`msg.sender`). There is no owner, no minter, no pause, no blacklist, no fee and no burn
/// hook: after construction the contract has no privileged path of any kind, and the supply can
/// never change.
/// @dev Self-contained on purpose. The verifier builds offline and this repository vendors nothing,
/// so the ERC-20 is written out here rather than imported. Semantics follow OpenZeppelin v5:
/// custom errors, zero-address guards on both ends of a transfer and on the spender of an approval,
/// and an allowance of `type(uint256).max` that is never decremented.
contract IDEADToken is IERC20 {
    // ---------------------------------------------------------------------------------------------
    // Launch parameters
    // ---------------------------------------------------------------------------------------------

    /// @notice Token name returned by `name()`.
    string public constant NAME = "InkDead";
    /// @notice Token symbol returned by `symbol()`.
    string public constant SYMBOL = "IDEAD";
    /// @notice Decimals returned by `decimals()`.
    uint8 public constant DECIMALS = 18;
    /// @notice Whole supply in minor units: 1,000,000,000 tokens at 18 decimals.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(DECIMALS);

    // ---------------------------------------------------------------------------------------------
    // Errors (ERC-6093 names)
    // ---------------------------------------------------------------------------------------------

    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);

    // ---------------------------------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------------------------------

    mapping(address account => uint256) private _balances;
    mapping(address owner => mapping(address spender => uint256)) private _allowances;

    /// @notice Mints the whole supply to the deployer. Takes no arguments and calls no other contract,
    /// so it runs unchanged on an empty chain and through the launch factory, which becomes the
    /// holder of the supply and distributes it.
    constructor() {
        _balances[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata
    // ---------------------------------------------------------------------------------------------

    /// @inheritdoc IERC20
    function name() external pure override returns (string memory) {
        return NAME;
    }

    /// @inheritdoc IERC20
    function symbol() external pure override returns (string memory) {
        return SYMBOL;
    }

    /// @inheritdoc IERC20
    function decimals() external pure override returns (uint8) {
        return DECIMALS;
    }

    // ---------------------------------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------------------------------

    /// @inheritdoc IERC20
    /// @dev Nothing can mint or burn, so the supply is the constant minted at construction.
    function totalSupply() external pure override returns (uint256) {
        return TOTAL_SUPPLY;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    // ---------------------------------------------------------------------------------------------
    // Actions
    // ---------------------------------------------------------------------------------------------

    /// @inheritdoc IERC20
    function transfer(address to, uint256 value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 value) external override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /// @inheritdoc IERC20
    /// @dev Only an allowance granted by `from` to `msg.sender` lets tokens leave `from`. There is no
    /// other path: no operator role, no admin override.
    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        return true;
    }

    // ---------------------------------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------------------------------

    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0)) revert ERC20InvalidSender(address(0));
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        uint256 fromBalance = _balances[from];
        if (fromBalance < value) revert ERC20InsufficientBalance(from, fromBalance, value);
        unchecked {
            // Underflow is excluded by the check above; overflow is excluded because the sum of all
            // balances is the constant supply.
            _balances[from] = fromBalance - value;
            _balances[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value) private {
        if (owner == address(0)) revert ERC20InvalidApprover(address(0));
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) private {
        uint256 current = _allowances[owner][spender];
        if (current == type(uint256).max) return;
        if (current < value) revert ERC20InsufficientAllowance(spender, current, value);
        unchecked {
            _allowances[owner][spender] = current - value;
        }
    }
}
