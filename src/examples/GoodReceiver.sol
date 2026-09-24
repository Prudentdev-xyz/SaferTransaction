// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC223} from "../interfaces/IERC223.sol";
import {IERC223Recipient} from "../interfaces/IERC223Recipient.sol";

/// @title GoodReceiver
/// @notice Example vault that correctly implements the ERC-223 receiver hook.
contract GoodReceiver is IERC223Recipient {
    // ---------- Errors ----------

    error GoodReceiver__TokenNotAccepted(address token);
    error GoodReceiver__InsufficientDeposit(uint256 deposited, uint256 requested);

    // ---------- Storage ----------

    address public immutable acceptedToken;
    mapping(address => uint256) public deposits;
    bytes public lastData;

    // ---------- Constructor ----------

    constructor(address acceptedToken_) {
        acceptedToken = acceptedToken_;
    }

    // ---------- ERC-223 hook ----------

    function tokenReceived(address _from, uint256 _value, bytes calldata _data) external returns (bytes4) {
        // msg.sender is the token contract. Reject unknown tokens and direct EOA calls.
        if (msg.sender != acceptedToken) revert GoodReceiver__TokenNotAccepted(msg.sender);

        deposits[_from] += _value;
        lastData = _data;

        return IERC223Recipient.tokenReceived.selector; // 0x8943ec02
    }

    // ---------- Withdraw ----------

    function withdraw(uint256 amount) external {
        uint256 deposited = deposits[msg.sender];
        if (deposited < amount) revert GoodReceiver__InsufficientDeposit(deposited, amount);

        deposits[msg.sender] = deposited - amount;
        IERC223(acceptedToken).transfer(msg.sender, amount);
    }
}