# SaferTransaction — ERC-223 Token

An implementation of [ERC-223: Token with transaction handling model](https://eips.ethereum.org/EIPS/eip-223),
built with Foundry for the Web3Bridge Eviction Test (Part 2, Option D).

## The problem

With ERC-20, `transfer` never notifies the recipient. If tokens are sent to a contract that isn't built
to handle them, the token contract just updates its balance table and the tokens are stuck forever.
The ERC-223 spec reports ~$201M lost this way across 50 examined tokens (as of May 2023).

## How ERC-223 fixes it

Transfers behave like sending ETH:

- **To a wallet (EOA):** works normally.
- **To a contract:** the token calls `tokenReceived(address,uint256,bytes)` on the receiver after updating
  balances. The receiver must return `0x8943ec02`. If the hook is missing, reverts, or returns anything
  else, the whole transfer reverts and the sender keeps the tokens.

## Project structure

```
src/
  ERC223Token.sol              Token implementation
  interfaces/
    IERC223.sol                Token interface (from the spec)
    IERC223Recipient.sol       Receiver hook interface (from the spec)
  examples/
    GoodReceiver.sol           Implements the hook correctly (accepts one token, supports withdraw)
    BadReceiver.sol            Deliberately has no hook, so transfers to it revert
test/
  ERC223Token.t.sol            Foundry test suite
docs/
  DESIGN.md                    Design note: scope, spec mapping, decisions, AI use
```

## Getting started

Requires [Foundry](https://book.getfoundry.sh/).

```bash
git clone https://github.com/Prudentdev-xyz/SaferTransaction.git
cd SaferTransaction
forge install
forge build
forge test -vv
```

## Tests

- **Happy path:** transfers to EOAs (including the `Transfer` event), deposits into `GoodReceiver`,
  `_data` forwarding, and withdrawal.
- **Failure cases:** receiver with no hook, fallback-only receiver, receiver rejecting an unknown token,
  insufficient balance, transfer to the zero address, and an EOA calling the hook directly.
- **Fuzz:** transfers to arbitrary EOAs with arbitrary amounts.

## Design

See [`docs/DESIGN.md`](docs/DESIGN.md) for the spec mapping, the ERC-20 failure mode this prevents, and the
key design decisions: strict magic-value check, low-level hook call, and calling the hook last.

## License

MIT
