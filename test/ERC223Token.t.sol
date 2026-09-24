// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC223Token} from "../src/ERC223Token.sol";
import {IERC223} from "../src/interfaces/IERC223.sol";
import {IERC223Recipient} from "../src/interfaces/IERC223Recipient.sol";
import {GoodReceiver} from "../src/examples/GoodReceiver.sol";
import {BadReceiver} from "../src/examples/BadReceiver.sol";

/// @dev Swallows any call through its fallback but never returns the magic value.
contract FallbackOnlyReceiver {
    fallback() external {}
}

contract ERC223TokenTest is Test {
    ERC223Token internal token;
    ERC223Token internal otherToken;
    GoodReceiver internal good;
    BadReceiver internal bad;
    FallbackOnlyReceiver internal fallbackOnly;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 internal constant AMOUNT = 100 ether;

    // ---------- Setup ----------

    function setUp() public {
        vm.startPrank(alice);
        token = new ERC223Token("Safer Token", "SAFE", 18, INITIAL_SUPPLY);
        otherToken = new ERC223Token("Other Token", "OTHER", 18, INITIAL_SUPPLY);
        vm.stopPrank();

        good = new GoodReceiver(address(token));
        bad = new BadReceiver();
        fallbackOnly = new FallbackOnlyReceiver();
    }

    // ---------- Helpers ----------

    function _transferAs(address from, address to, uint256 value) internal {
        vm.prank(from);
        token.transfer(to, value);
    }

    function _transferWithDataAs(address from, address to, uint256 value, bytes memory data) internal {
        vm.prank(from);
        token.transfer(to, value, data);
    }

    // ---------- Metadata ----------

    function test_Metadata() public view {
        assertEq(token.name(), "Safer Token");
        assertEq(token.symbol(), "SAFE");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY);
    }

    function test_MagicValueMatchesSpec() public view {
        assertTrue(IERC223Recipient.tokenReceived.selector == bytes4(0x8943ec02), "selector mismatch");
        assertTrue(token.TOKEN_RECEIVED_MAGIC() == bytes4(0x8943ec02), "constant mismatch");
    }

    // ---------- Transfers to EOAs ----------

    function test_TransferToEOA() public {
        _transferAs(alice, bob, AMOUNT);

        assertEq(token.balanceOf(bob), AMOUNT);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - AMOUNT);
    }

    function test_TransferToEOA_EmitsTransferEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC223.Transfer(alice, bob, AMOUNT, "");

        _transferAs(alice, bob, AMOUNT);
    }

    // ---------- Transfers to contracts ----------

    function test_TransferToGoodReceiver_CreditsDeposit() public {
        _transferAs(alice, address(good), AMOUNT);

        assertEq(token.balanceOf(address(good)), AMOUNT);
        assertEq(good.deposits(alice), AMOUNT);
    }

    function test_TransferWithData_ForwardsDataToReceiver() public {
        bytes memory data = bytes("invoice-42");

        _transferWithDataAs(alice, address(good), AMOUNT, data);

        assertEq(good.lastData(), data);
        assertEq(good.deposits(alice), AMOUNT);
    }

    function test_GoodReceiver_Withdraw() public {
        _transferAs(alice, address(good), AMOUNT);

        vm.prank(alice);
        good.withdraw(AMOUNT);

        assertEq(token.balanceOf(alice), INITIAL_SUPPLY);
        assertEq(token.balanceOf(address(good)), 0);
        assertEq(good.deposits(alice), 0);
    }

    // ---------- Failure cases ----------

    function test_RevertWhen_ReceiverHasNoHook() public {
        vm.expectRevert(abi.encodeWithSelector(ERC223Token.ERC223__ReceiverRejected.selector, address(bad)));
        _transferAs(alice, address(bad), AMOUNT);

        // Nothing moved: the sender keeps the tokens
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY);
        assertEq(token.balanceOf(address(bad)), 0);
    }

    function test_RevertWhen_ReceiverOnlyHasFallback() public {
        vm.expectRevert(
            abi.encodeWithSelector(ERC223Token.ERC223__ReceiverRejected.selector, address(fallbackOnly))
        );
        _transferAs(alice, address(fallbackOnly), AMOUNT);
    }

    function test_RevertWhen_ReceiverRejectsToken() public {
        // GoodReceiver only accepts `token`, so `otherToken` is rejected inside the hook
        vm.expectRevert(abi.encodeWithSelector(ERC223Token.ERC223__ReceiverRejected.selector, address(good)));
        vm.prank(alice);
        otherToken.transfer(address(good), AMOUNT);
    }

    function test_RevertWhen_InsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(ERC223Token.ERC223__InsufficientBalance.selector, bob, 0, AMOUNT));
        _transferAs(bob, alice, AMOUNT);
    }

    function test_RevertWhen_TransferToZeroAddress() public {
        vm.expectRevert(ERC223Token.ERC223__TransferToZeroAddress.selector);
        _transferAs(alice, address(0), AMOUNT);
    }

    function test_RevertWhen_EOACallsHookDirectly() public {
        // Spec notes tokenReceived can be called by an EOA; the receiver must filter by msg.sender
        vm.expectRevert(abi.encodeWithSelector(GoodReceiver.GoodReceiver__TokenNotAccepted.selector, bob));
        vm.prank(bob);
        good.tokenReceived(bob, AMOUNT, "");
    }

    // ---------- Fuzz ----------

    function testFuzz_TransferToEOA(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != alice && to.code.length == 0);
        assumeNotForgeAddress(to);
        amount = bound(amount, 0, INITIAL_SUPPLY);

        _transferAs(alice, to, amount);

        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - amount);
    }
}
