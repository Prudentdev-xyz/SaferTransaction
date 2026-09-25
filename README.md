# ERC-223 Implementation — Design Note

## 1. What I implemented

**Standard:** ERC-223 — Token with transaction handling model
**Spec:** https://eips.ethereum.org/EIPS/eip-223
**Scope:** Option D. A fungible token whose transfers to contracts require the receiver to implement
`tokenReceived` and return `0x8943ec02`, otherwise the transfer reverts. Transfers to EOAs work normally.
Includes one receiver that implements the hook (`GoodReceiver`) and one that does not (`BadReceiver`).

## 2. Spec mapping

| Code | Spec section |
|---|---|
| `IERC223.name / symbol / decimals` | [Token Methods](https://eips.ethereum.org/EIPS/eip-223#token-contract) (optional) |
| `totalSupply`, `balanceOf` | [Token Methods](https://eips.ethereum.org/EIPS/eip-223#token-contract) |
| `transfer(address,uint256)` | Token Methods: transfer(address, uint) |
| `transfer(address,uint256,bytes)` | Token Methods: transfer(address, uint, bytes) |
| `event Transfer(address,address,uint256,bytes)` | [Events](https://eips.ethereum.org/EIPS/eip-223#token-contract) |
| `to.code.length > 0` check | transfer(address, uint, bytes) NOTE: "code size being zero" = EOA |
| Hook called last in `_transfer` | "tokenReceived ... MUST be called after all other operations" |
| `IERC223Recipient.tokenReceived` returning `0x8943ec02` | [ERC-223 Token Receiver](https://eips.ethereum.org/EIPS/eip-223#erc-223-token-receiver) |
| `GoodReceiver` `msg.sender` filter | Receiver NOTE + [Backwards Compatibility](https://eips.ethereum.org/EIPS/eip-223#backwards-compatibility) example |

## 3. The ERC-20 failure mode this prevents

ERC-20 `transfer` never notifies the recipient. If the recipient is a contract, the token contract simply
edits its own balance table, and the recipient has no chance to react or refuse.

**Concrete example:** A vault accepts USDT only through `deposit()`, which calls `transferFrom` and then
records `deposits[user] += amount`. A user instead calls `USDT.transfer(vault, 1000)` directly. USDT's
table now says the vault owns 1,000 more, but `deposits[user]` never increases. The vault has no function to
return tokens it didn't record, so the 1,000 USDT is stuck permanently. The same happens when users send
tokens to the token contract's own address. The spec reports ~$201M lost this way across 50 examined
tokens (as of 9 May 2023).

With ERC-223 the same `transfer` calls the vault's `tokenReceived`. A contract without the hook
(`BadReceiver`) makes the transfer revert, so the user keeps the tokens (`test_RevertWhen_ReceiverHasNoHook`).
A contract with the hook (`GoodReceiver`) records the deposit in the same transaction — one call instead of
ERC-20's approve + transferFrom.

## 4. Hardest design decisions

**a) Strictly requiring the magic value.**
The reference implementation ignores `tokenReceived`'s return value, and the spec says the call "can be
handled by the fallback function ... and in this case it may not return the magic value." I chose to
**require** `0x8943ec02`. A contract with a generic fallback (e.g. a proxy or a contract written for ETH)
would otherwise silently accept tokens it cannot handle — exactly the stuck-token problem ERC-223 exists to
fix. Trade-off: fallback-only receivers are rejected (`test_RevertWhen_ReceiverOnlyHasFallback`). This
follows the spec's MUST ("must return 0x8943ec02") over its permissive note.

**b) Low-level call instead of an interface call.**
Calling `IERC223Recipient(to).tokenReceived(...)` directly gives different failure modes: a missing function
reverts with empty data, and a fallback returning nothing causes an ABI-decoding revert. I use
`to.call(...)` and check success, return length and value, so every rejection ends in one clear error,
`ERC223__ReceiverRejected(to)`. Trade-off: the receiver's own revert reason is not bubbled up.

**c) Ordering: state and event before the hook.**
The spec says the hook "MUST be called after all other operations to avoid re-entrancy attacks". The
reference implementation emits `Transfer` after the hook; I emit before it so the hook is truly last
(checks-effects-interactions). If the hook re-enters `transfer`, balances are already consistent.

## 5. Other choices and limitations

- **No approve / transferFrom.** They are not part of the ERC-223 spec; the push model replaces them.
- **Zero-address check and custom errors.** Not required by the spec; added for safety and clear reverts.
- **Empty data** is `""` in the 2-argument transfer (the reference implementation uses `hex"00000000"`);
  the spec only says `_data` can be empty.
- **Minting:** the full supply is minted to the deployer in the constructor, emitting `Transfer(0x0, ...)`.
- **extcodesize limitation:** a contract still inside its constructor has no code yet, so it is treated as
  an EOA and no hook is called (also noted in the reference implementation).
- **Event incompatibility:** ERC-223's `Transfer` has a 4th `bytes` field, so its topic differs from ERC-20's
  `Transfer`; ERC-20-only indexers will not recognise it.
- **Non-payable transfers:** the spec's ether-forwarding note only applies to payable transfers; mine are not payable.

## 6. Tests

14 Foundry tests: metadata and magic value, EOA transfers (+ event), GoodReceiver deposit / data forwarding /
withdraw, and failure cases — no hook, fallback-only, rejected token, insufficient balance, zero address,
EOA calling the hook directly — plus a fuzz test for EOA transfers.

## 7. AI use

I used Claude to explain what ERCs are, explain the stuck-token problem, walk through the
ERC-223 spec, and draft tests and this note.

**What I verified myself:**
- Read the ERC-223 spec and checked every function, event and the receiver hook against it
  (names, parameters, return types, and the `0x8943ec02` magic value).
- Confirmed the magic value matches the spec with `test_MagicValueMatchesSpec`.
- Ran `forge build` and `forge test` and confirmed all tests pass.
- Checked that the token calls `tokenReceived` only after balances and the event are updated,
  as the spec requires.

**How I used it:**
- I started writing the contracts myself ([The interfaces and the basic balance/transfer
  logic]) but got stuck on [How to detect a missing hook / how to check the return value /
  the tests].
- At that point I used Claude to help complete the implementation and tests, then reviewed the result
  against the spec and my own partial version.
- I kept the AI's approach where it matched the spec, and made sure I understood the parts I didn't
  write myself, especially `_transfer` and `_callTokenReceived`.
- Where both the AI draft and my implementation deliberately differ from the spec's reference
  implementation (strict magic-value check, emitting the event before the hook), I documented why in
  section 4.
- Project setup issues I fixed myself: renamed a mis-named test file (`IERC223Token.t.sol` →
  `ERC223Token.t.sol`), removed the leftover `Counter.s.sol` script that broke the build, and fixed empty
  source files caused by editor tabs saving to a renamed folder path.
