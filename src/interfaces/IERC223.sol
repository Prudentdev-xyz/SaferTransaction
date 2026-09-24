// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ERC-223 Token
/// @notice Spec: https://eips.ethereum.org/EIPS/eip-223#token-contract
interface IERC223 {
    // ---------- Events ----------

    event Transfer(address indexed _from, address indexed _to, uint256 _value, bytes _data);

    // ---------- Optional metadata ----------

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    // ---------- Core ----------

    function totalSupply() external view returns (uint256);
    function balanceOf(address _owner) external view returns (uint256);
    function transfer(address _to, uint256 _value) external returns (bool);
    function transfer(address _to, uint256 _value, bytes calldata _data) external returns (bool);
}
