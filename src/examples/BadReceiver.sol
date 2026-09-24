// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title BadReceiver
/// @notice Deliberately does NOT implement tokenReceived (and has no fallback).
///         Represents a contract that was never written to handle tokens.
contract BadReceiver {
    uint256 public counter;

    function ping() external {
        counter++;
    }
}