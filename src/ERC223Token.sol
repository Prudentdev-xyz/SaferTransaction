// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC223} from "./interfaces/IERC223.sol";
import {IERC223Recipient} from "./interfaces/IERC223Recipient.sol";

/// @title ERC223Token
/// @notice Fungible token where transfers to contracts must be accepted by the receiver via tokenReceived.
/// @dev Spec: https://eips.ethereum.org/EIPS/eip-223
contract ERC223Token is IERC223 {
    // ---------- Errors ----------

    error ERC223__TransferToZeroAddress();
    error ERC223__InsufficientBalance(address from, uint256 balance, uint256 needed);
    error ERC223__ReceiverRejected(address to);

    // ---------- Constants ----------

    /// @notice Value tokenReceived must return: bytes4(keccak256("tokenReceived(address,uint256,bytes)"))
    bytes4 public constant TOKEN_RECEIVED_MAGIC = 0x8943ec02;

    // ---------- Storage ----------

    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    // ---------- Constructor ----------

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 initialSupply) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;

        _totalSupply = initialSupply;
        _balances[msg.sender] = initialSupply;
        emit Transfer(address(0), msg.sender, initialSupply, "");
    }

    // ---------- Metadata ----------

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    // ---------- Views ----------

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address _owner) external view returns (uint256) {
        return _balances[_owner];
    }

    // ---------- Transfers ----------

    /// @notice Spec: transfer(address, uint). Same as the 3-arg version with empty data.
    function transfer(address _to, uint256 _value) external returns (bool) {
        _transfer(msg.sender, _to, _value, "");
        return true;
    }

    /// @notice Spec: transfer(address, uint, bytes). _data is forwarded to the receiver's hook.
    function transfer(address _to, uint256 _value, bytes calldata _data) external returns (bool) {
        _transfer(msg.sender, _to, _value, _data);
        return true;
    }

    // ---------- Internal ----------

    function _transfer(address from, address to, uint256 value, bytes memory data) internal {
        if (to == address(0)) revert ERC223__TransferToZeroAddress();

        uint256 fromBalance = _balances[from];
        if (fromBalance < value) revert ERC223__InsufficientBalance(from, fromBalance, value);

        // Effects
        unchecked {
            _balances[from] = fromBalance - value;
        }
        _balances[to] += value;
        emit Transfer(from, to, value, data);

        // Interaction: MUST be last (spec, re-entrancy protection)
        if (to.code.length > 0) {
            _callTokenReceived(from, to, value, data);
        }
    }

    /// @dev Low-level call so that a missing hook, a revert inside the hook, and a wrong
    ///      return value all end in the same clear error.
    function _callTokenReceived(address from, address to, uint256 value, bytes memory data) private {
        (bool success, bytes memory ret) =
            to.call(abi.encodeWithSelector(IERC223Recipient.tokenReceived.selector, from, value, data));

        if (!success || ret.length < 32 || bytes4(ret) != TOKEN_RECEIVED_MAGIC) {
            revert ERC223__ReceiverRejected(to);
        }
    }
}