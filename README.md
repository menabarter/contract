# SwapEscrow

An escrow swap contract for [TON](https://ton.org): two parties deposit assets —
NFTs, GRAM (native TON), and Jettons — and the swap executes automatically once
both sides are fully funded. Either party can cancel before completion. A
supervisor role can also intervene at any time — see
[Trust model](#trust-model) below for exactly what that role can do.

Written in [Tolk](https://docs.ton.org/tolk/overview), built and tested with
[Acton](https://ton-blockchain.github.io/acton/) 1.2.0.

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

`SwapEscrowNosup`, the supervisor-free variant described below, has its own
manual review in
[docs/SECURITY-REVIEW-NOSUP.md](docs/SECURITY-REVIEW-NOSUP.md); symbolic
analysis for it has not been run yet.

A note on naming: the contract source is `contracts/escrow_beta_v1.tolk`, while
the contract metadata declares `version: "2.0.0-stage2"` and the Acton package
is named `swap-escrow-v2`. The metadata is intentionally left untouched —
changing it would change the compiled bytecode, and with it every deployed
deal's address. The same reasoning applies to
`contracts/escrow_nosup_beta_v1.tolk`, whose own contract metadata declares
`version: "1.0.0-beta"` — it is a separate, independently versioned contract,
not a variant of the one above.

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

### The supervisor-free variant

A second contract, `contracts/escrow_nosup_beta_v1.tolk` (`SwapEscrowNosup`),
is offered alongside this one rather than replacing it: the party creating a
deal picks which guarantee they want. It has **no supervisor role at all** —
no `supervisor` field in storage, and none of the emergency handlers described
above exist in its bytecode. That is a **separate contract**, not a flag in
storage, and the distinction is the whole point: a runtime flag would leave
the emergency handlers in the bytecode and make their absence a promise the
code merely keeps, while a separate contract makes it a property of the
compiled code, checkable once against its own code hash (see
[Verifying the build](#verifying-the-build) below) and inherited by every deal
deployed from it. "Cannot" is worth more than "will not".

Removing the supervisor also removes its only genuine job: rescuing an asset
that push delivery could not complete. `SwapEscrowNosup` replaces that with a
**pull fallback** instead. Distribution is still automatic and still
push-first — nothing changes about the common path, where every asset simply
arrives. What changes is what happens when a delivery bounces: instead of
getting stuck the way it would without a supervisor's rescue handlers, the
asset is marked **claimable**, and the rest of the distribution keeps
going — a bounced delivery never stalls the deal. The asset's rightful
recipient can then pull it out themselves with `claim_asset`
(opcode `0x6d5f0006`), paying for that transfer's gas out of the value they
attach to the call. Nobody else can trigger this: the contract only ever sends
a claimed asset to the caller's own address, and only if the caller is the
recipient this deal names for that asset — the party that deposited an asset
can never claim it back once the swap has executed, and a stranger can never
redirect it to themselves.

NFTs and Jettons become claimable under different conditions, and the
difference is deliberate. An NFT is claimable as soon as it has been received
and the distribution has already attempted to send it — without waiting for a
bounce at all — because an NFT item only ever honors a transfer from its
current owner: if the NFT already left the escrow, a second attempt to send it
is simply rejected by the NFT contract itself, so nothing is lost by trying
anyway. A Jetton is different: the escrow's Jetton wallet for a given minter
can hold tokens belonging to more than one asset of the deal, or a leftover
from an overpayment, so resending it without proof that the earlier transfer
failed risks moving tokens that belong to something else. A Jetton is
therefore claimable only once a bounce has confirmed that the earlier transfer
never left the escrow's wallet.

A claim is funded entirely by the value attached to it, so it works on an
emptied balance — but the contract's check is `value >= NFT_TRANSFER_VALUE`
(0.03 TON) or `value >= JETTON_TRANSFER_VALUE` (0.05 TON) against the value as
it arrives, while what actually reaches the NFT item or the Jetton wallet is
that value minus this transaction's own cost. Attaching exactly the minimum
therefore under-funds the transfer it pays for. Attach headroom — 0.1 TON for
an NFT, 0.2 TON for a Jetton is comfortable. An under-funded NFT claim is
harmless (it bounces and the asset stays claimable), but an under-funded
Jetton claim clears the mark before sending, so if the failure is severe
enough that no bounce comes back, the asset cannot be marked again.

Two getters expose this state for a client to build a claim UI against:
`claimableAssets()` returns the indices currently marked claimable, and
`assetStatus(idx)` returns one asset's `(received, claimable, bounces)`. One
caveat worth knowing before wiring up a "claim" button: an NFT's `claimable`
flag can be **stale** — claiming an NFT that was in fact already delivered is
harmless (the NFT contract rejects the transfer since the escrow is no longer
the owner), but the bounce from that rejected attempt sets `claimable = true`
again regardless. So check who currently owns the NFT before offering the
button, rather than trusting the flag alone; Jetton claimability does not have
this problem, since a Jetton bounce is proof the tokens are still on the
escrow's wallet.

#### Risks this variant does not remove

Removing the supervisor does not remove every way an asset can end up stuck —
it removes the ones a rescue handler was needed for, and leaves standing the
ones no contract-side mechanism can fix without becoming exactly the kind of
privileged role this variant is built to avoid:

1. **A Jetton overpayment that arrives without enough gas to refund it**
   (under roughly 0.03 TON) leaves the excess sitting in the escrow's Jetton
   wallet; it is not a deal asset, so `claim_asset` does not apply to it.
2. **A foreign NFT or Jetton sent to the contract without enough gas for a
   return** has nothing to fund a refund with, and — if it arrives with a
   zero forward amount — the contract never even learns it arrived. It is not
   part of any deal's registry, so `claim_asset` cannot reach it either.
3. **A Jetton transfer that fails inside the Jetton contract's own second
   hop** never bounces back to the escrow, so the tokens stay on the escrow's
   Jetton wallet without ever being marked claimable. This does not happen
   with standard Jetton implementations.
4. **A recipient whose own wallet rejects the incoming transfer** — an NFT
   item that refuses the new owner, or a Jetton wallet that refuses the
   credit — leaves the asset stuck: `claim_asset` can only ever send an asset
   to the recipient's own address, so there is no other address to try.
5. **`execute_swap` (manual execution) is `owner1`-only**, exactly as in the
   contract with a supervisor.
6. **An NFT belonging to the deal that arrives late and without enough gas**
   for a bounce — say, sent again by mistake by whoever now holds it — can
   still be pulled out by the deal's rightful recipient via `claim_asset`;
   without that, it would be stuck the same way risk 2 describes.
7. **A Jetton bounce that never reaches the escrow** (this needs a
   non-standard Jetton wallet on the escrow's side — in practice essentially
   never, since 0.05 TON comfortably covers a standard wallet's bounce) leaves
   the tokens neither delivered nor claimable.
8. **The value carried by a bounced delivery stays on the escrow's balance.**
   Finalizing a deal sweeps the whole balance to `feeWallet` as its last act,
   so a bounce that arrives afterwards — carrying back the transfer's own
   value, on the order of 0.03 TON — lands on an account that has already been
   swept, and no later handler moves it: `claim_asset` is funded by the value
   the claimer attaches and forwards that value onward, and this variant has
   no privileged withdrawal. The remainder is consumed by storage fees over
   time. It affects only deals where a delivery bounced, never the assets
   themselves, and it is the direct cost of having no privileged role: a deal
   whose deliveries all succeed ends with a zero balance. A bounce that
   arrives *before* the sweep is not returned to its depositor either — it
   simply joins the balance the sweep hands to `feeWallet`.
9. **A large rise in the network's gas price outlives a deployed deal.** The
   contract prices its own compute dynamically, so its internal reserves
   follow the network, but the values it hands to other contracts —
   `NFT_TRANSFER_VALUE` (0.03 TON), `JETTON_TRANSFER_VALUE` (0.05),
   `PROVIDE_WALLET_VALUE` (0.02) — are fixed at deploy and cannot be raised
   for a deal that already exists. If gas becomes materially more expensive,
   deliveries in already-deployed deals start failing for want of gas. This is
   survivable rather than fatal precisely because of `claim_asset`: a failed
   delivery leaves the asset with its rightful recipient to pull, at whatever
   value the network then demands. A deal still in SETUP is the harder case,
   since TEP-89 discovery has no pull equivalent — `cancel_swap` is the exit.
10. **A batch deal one message short of finalization needs a `kick`.** When
    the final batch of a large deal is the one that sent assets, the contract
    defers finalization — the GRAM legs, the service fee, the pro-rata refund
    and the sweep — to one more self-message. That message is ordinary: it can
    fail, and its bounce is deliberately ignored. Either owner resumes the
    chain with `kick`, and the assets themselves are already delivered by that
    point; but if both owners walk away believing the deal is finished, the
    TON legs stay on the contract, and unlike registry assets they have no
    pull equivalent. A client should watch `distributionProgress()` and offer
    `kick` while it reports anything other than idle.

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

`required1Count` and `required2Count` deserve naming here, because they are
the fields that decide *who has to deposit what* before the swap may run, and
a registry can be perfectly well-formed while they are not. Set
`required1Count` to zero on a deal whose side 1 holds three NFTs, and side 2's
deposit alone satisfies every gate: the swap executes, side 2's asset goes to
side 1, and side 1 was never required to deposit anything. The contract
enforces the counts it was deployed with; it has no notion of what the two
parties agreed. This is the same client-side check as above, and it only works
when the reconstruction starts from the terms the user was shown — deriving
the address from a `Storage` blob handed over by whatever served the deal
proves nothing, since it necessarily matches itself. Rebuild the registry from
the displayed positions, confirm each side's required count equals the number
of positions displayed for that side, then compare addresses.

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
| `contracts/escrow_beta_v1.tolk` | the escrow contract with a supervisor role (`SwapEscrow`) |
| `contracts/storage.tolk`, `messages.tolk` | storage layout and message schema for `SwapEscrow` |
| `contracts/escrow_nosup_beta_v1.tolk` | the supervisor-free escrow contract (`SwapEscrowNosup`) |
| `contracts/nosup/storage.tolk`, `nosup/messages.tolk` | storage layout, constants, error codes and the `ClaimAsset` message for `SwapEscrowNosup`; standard message structs are imported from `contracts/messages.tolk`, not duplicated |
| `contracts/nft_item_mock.tolk`, `jetton_wallet_mock.tolk`, `jetton_minter_mock.tolk`, `jetton_mock_lib.tolk`, `nft_item_gas_mock.tolk` | NFT and Jetton mocks (and their shared helper code) used by tests only; `nft_item_gas_mock.tolk` models an NFT with a higher gas threshold, for the `SwapEscrowNosup` claim tests |
| `tests/` | 187 tests across 21 test files for `SwapEscrow`, plus a shared test-helper module |
| `tests/nosup/` | 177 tests across 20 test files for `SwapEscrowNosup`, plus a shared test-helper module |
| `wrappers/`, `wrappers-ts/` | generated wrappers for Tolk tests and TypeScript consumers, for both contracts |
| `ts-tests/` | validates both TypeScript wrappers against Tolk-side cell-hash fixtures |
| `scripts/` | deployment and testnet smoke scripts, for both contracts |
| `docs/` | the security reviews |
| `.github/` | CI workflow (build, format check, lint, tests) |

Build artifacts (`build/`, `.acton/`) are generated locally and are not part of
the repository.

## Build and test

Requires Acton 1.2.0.

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

The compiled code hash of `SwapEscrowNosup` is:

```
42883CBEF30F0E8E703A87046E3592B71F8C505CBEA05B92534FC699C3CE874C
```

Run `acton build` and compare against `build/SwapEscrow.json` and
`build/SwapEscrowNosup.json` respectively.

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
