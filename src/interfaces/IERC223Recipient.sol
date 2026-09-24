// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ERC-223 Token Receiver
/// @notice Spec: https://eips.ethereum.org/EIPS/eip-223#erc-223-token-receiver
interface IERC223Recipient {
    /// @notice Called by an ERC-223 token contract after tokens have been credited to this contract.
    /// @dev msg.sender is the token contract, _from is the original sender.
    ///      MUST return 0x8943ec02 (the selector of this function) to accept the tokens.
    function tokenReceived(address _from, uint256 _value, bytes calldata _data) external returns (bytes4);
}
