# SwapEscrow

An escrow swap contract for [TON](https://ton.org): two parties deposit assets —
NFTs, GRAM (native TON), and Jettons — and the swap executes automatically once
both sides are fully funded. Either party can cancel before completion. A
supervisor role can also intervene at any time — see
[Trust model](#trust-model) below for exactly what that role can do.

Written in [Tolk](https://docs.ton.org/tolk/overview), built and tested with
[Acton](https://ton-blockchain.github.io/acton/) 1.1.0.

## Status

The contract is deployed and in use on TON mainnet. It has **not** undergone
an external security audit. Use at your own risk — see the warranty disclaimer
in [LICENSE](LICENSE).

What it has had is an internal security review — manual source reading plus
symbolic execution — written up in
[docs/SECURITY-REVIEW-2026-09-11.md](docs/SECURITY-REVIEW-2026-09-11.md). It
found no exploitable defect at the current code hash. What it does record is
the trust model you are accepting if you deploy or deposit: above all, that the
supervisor can take everything. Read that section before either.

A note on naming: the contract source is `contracts/escrow_beta_v1.tolk`, while
the contract metadata declares `version: "2.0.0-stage2"` and the Acton package
is named `swap-escrow-v2`. The metadata is intentionally left untouched —
changing it would change the compiled bytecode, and with it every deployed
deal's address.

## Trust model

Each deal names a `supervisor` address in its storage. That address has broad,
unilateral powers over the deal — anyone depositing into this contract is
trusting whoever holds that key. Concretely, the supervisor can, at any time
and without either party's consent:

- **Collect all deal assets to itself.** `handleEmergencyCollect` is
  supervisor-only, callable while the deal is in phase `ACTIVE` or `SETUP`,
  and sends every asset the contract has received for the deal (NFTs and
  Jettons from both sides) to the supervisor's own address, then marks the
  deal `CANCELLED`.
- **Sweep the entire contract balance.** `handleEmergencyWithdraw` is
  supervisor-only and has **no phase gate at all** — it works even after the
  deal is `DONE` or `CANCELLED`. It uses `SEND_MODE_CARRY_ALL_BALANCE` to send
  the contract's full TON balance to the supervisor, including both parties'
  GRAM deposits.
- **Return all deal assets to their depositors.** `handleEmergencyReturn` is
  supervisor-only, callable in phase `ACTIVE`/`SETUP`, and refunds GRAM and
  returns NFTs/Jettons to the original owners, then marks the deal
  `CANCELLED`.
- **Rescue individual stuck assets.** `handleRescueNft` and
  `handleRescueJetton` are supervisor-only, have no phase gate, and let the
  supervisor pull out a specific NFT or Jetton amount (e.g. one left behind
  after a failed transfer) and send it to itself.
- **Force delivery of a specific asset.** `handleForceDeliver` is
  supervisor-only and lets the supervisor push or fallback a single
  in-flight distribution asset outside the normal batch/retry flow.

None of these powers require a majority, a timelock, or agreement from either
party to the deal — the supervisor address alone is sufficient. Depositing
into a deal means trusting whoever controls that deal's supervisor key as
much as you trust a conventional custodian. Verify who the supervisor is
before depositing.

### A supervisor-free variant is planned

A second contract without the supervisor role is planned, to be offered
alongside this one rather than replacing it: the party creating a deal picks
which guarantee they want. This is a priority and will be implemented in the
near future.

It is planned as a **separate contract**, not a flag in storage. That
distinction is the whole point. A runtime flag would leave the emergency
handlers in the bytecode and make their absence a promise the code merely keeps;
a separate contract makes it a property of the code, verifiable once against a
code hash and inherited by every deal deployed from it. "Cannot" is worth more
than "will not".

The reason both will exist, rather than the supervisor simply being removed, is
that its rescue paths are the only recovery for three cases this contract can
genuinely reach. `returnForeignNft` and `returnJettons` both give up when the
incoming message underpays the gas for the return — the asset then sits with the
escrow, recoverable only through `rescue_nft` / `rescue_jetton`. A jetton
overpayment whose refund cannot be funded strands the same way. And
`force_deliver` is what unblocks a distribution whose recipient permanently
rejects the transfer.

## What the contract validates, and what it cannot

The contract does check that a deposit is genuine. A jetton deposit is
accepted only if the notification comes from the wallet that TEP-89 discovery
resolved for the minter recorded in the registry, and only if the depositor is
the side's own owner; the amount must match the registry entry exactly, with
underpayment returned in full and overpayment refunded down to the recorded
amount. NFT receipt likewise verifies that the item address matches the
registry entry before a hinted index is accepted. A forged notification from
an arbitrary contract matches nothing and is sent back.

Every one of those checks is relative to **the registry the contract was
deployed with**. The registry lives in `stateInit`, so it is fixed at deploy
and cannot be altered afterwards — but the contract has no way to know whether
it describes what the two parties actually agreed on. It stores a minter
address, never a token name or symbol, and it will faithfully execute a swap of
whatever minter is recorded. Put a different minter in the registry and the
contract accepts that token without complaint.

Whoever builds the deal therefore holds this trust, not the contract. Two
failure modes follow, and a bug produces them as readily as bad faith:

- the registry names a minter other than the one the user was shown;
- the user is handed the address of a different deployment than the one whose
  terms they were shown.

Both are caught by the same client-side check, and it is worth building:
reconstruct `Storage` from the deal as presented to the user, derive the
address from it, and refuse to sign if it disagrees with the address supplied
by whatever served the deal. Because the address is a hash of code and data, a
substituted minter necessarily produces a different address, so the mismatch
surfaces before anything is sent. `wrappers-ts/SwapEscrow.gen.ts` derives
addresses this way already, and `ts-tests/` pins the result. Showing the
minter address alongside the token symbol is worth doing too — a symbol is
attacker-chosen metadata and guarantees nothing.

The same reasoning covers deal *validity*, not just token identity: nothing
on chain checks that `assets` holds exactly the keys `0 .. assetsCount-1`,
that `jettonsCount` agrees with the registry's contents, or that
`pendingWallets` was derived from it. A malformed deal is simply a different
address, reachable only if something sends a user there.

## Deal size limits

A deal's whole registry lives inside the contract's `stateInit`, and several
handlers walk it in a single transaction. Every transaction is capped at
1,000,000 gas by the network, and no amount of attached TON raises that
ceiling — so a deal can be built large enough that it cannot function. The
contract does not validate this itself; whatever deploys it must.

These are the limits this repository ships and tests:

| | Limit | Measured ceiling |
|---|---|---|
| NFT positions per side | **150** | 500 per side, full cycle |
| Jetton positions per side | **15** | 25 per side, full cycle |

Both are **per side**, not per deal — the symmetric form is the harsher one
(`78×78` fails where `156×0` of the same total passes).

Both are also **flat**: they do not vary with what else the deal contains. A
jetton-only deal has considerably more headroom than one carrying 300 NFTs,
because the registry that every minter reply re-scans is short — but the cap
stays at 15 either way. One number that always holds is easier to enforce
correctly than a formula, and the measured ceilings in the right-hand column
are there as headroom, not as an invitation to compute a tighter bound. Both
the mixed and the jetton-only case are pinned by tests at the shipped limit.

Limits count *positions in the registry*, never amounts. A position carries a
single `coins` field, so one holding a million tokens costs exactly what one
holding a single token costs.

Two separate ceilings are behind those numbers, and they compete for the same
gas budget:

- **Distinct minters.** Each unique jetton minter is sent its own TEP-89
  `ProvideWalletAddress`, all from the deploy transaction. Exceed this and the
  deploy aborts — the contract is never created, so nothing is at risk. With
  no NFTs about 70 distinct minters get through; with a 300-NFT registry that
  drops to around 50.
- **Positions of one minter.** Each reply re-scans the whole registry and
  writes back every position belonging to that minter, so this ceiling is much
  lower and is the one the table above is set by. Its failure is the dangerous
  one: **the deploy succeeds** and the minter's reply is what rolls back,
  leaving the deal in `PHASE_SETUP` permanently. It stays cancellable, so
  deposits are never trapped, but it can never execute either. Reject
  oversized deals *before* deploying them.

The anchors for all of this are in `tests/gas_probe.test.tolk` — the shipped
limit is exercised end to end, and both the last passing size and the failure
mode are pinned.

## Layout

| Path | Contents |
|---|---|
| `contracts/escrow_beta_v1.tolk` | the escrow contract |
| `contracts/storage.tolk`, `messages.tolk` | storage layout and message schema |
| `contracts/nft_item_mock.tolk`, `jetton_wallet_mock.tolk`, `jetton_minter_mock.tolk`, `jetton_mock_lib.tolk` | NFT and Jetton mocks (and their shared helper code) used by tests only |
| `tests/` | 186 tests across 20 test files, plus a shared test-helper module |
| `wrappers/`, `wrappers-ts/` | generated wrappers for Tolk tests and TypeScript consumers |
| `ts-tests/` | validates the TypeScript wrapper against Tolk-side cell-hash fixtures |
| `scripts/` | deployment and testnet smoke scripts |
| `docs/` | the security review |
| `.github/` | CI workflow (build, format check, lint, tests) |

Build artifacts (`build/`, `.acton/`) are generated locally and are not part of
the repository.

## Build and test

Requires Acton 1.1.0.

```bash
acton build
acton test
```

The TypeScript layer:

```bash
npm install
npm run typecheck
npm test
```

## Verifying the build

The compiled code hash of `SwapEscrow` is:

```
41F7882FE4445147DAC4907FF6AEB60C32C4F7A5F43BFE5357433C18D41418D3
```

Run `acton build` and compare against `build/SwapEscrow.json`.

## Continuous integration

`.github/workflows/contracts.yml` runs `acton build`, `acton fmt --check`,
`acton check` and `acton test`, then `npm run typecheck` and `npm test` for
the TypeScript layer — the latter is what catches the generated wrapper
drifting away from the compiled contract. It runs on pushes and pull requests
targeting `main`/`master`, and can also be triggered manually
(`workflow_dispatch`).

## License

Copyright (C) 2026 MENA

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU Affero General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option) any
later version. See [LICENSE](LICENSE) for the full text.

Note section 13 in particular: if you run a modified version of this software as
a network service, you must offer its complete source code to the users of that
service.
