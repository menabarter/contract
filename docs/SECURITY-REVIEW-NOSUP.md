# SwapEscrowNosup — Security Review

**Date:** 2026-09-18
**Subject:** `contracts/escrow_nosup_beta_v1.tolk`, `contracts/nosup/storage.tolk`, `contracts/nosup/messages.tolk`, reviewed as a diff against `contracts/escrow_beta_v1.tolk` (code hash `41F7882FE4445147DAC4907FF6AEB60C32C4F7A5F43BFE5357433C18D41418D3`, covered by `docs/SECURITY-REVIEW-2026-09-11.md`)
**Code hash reviewed:** `42883CBEF30F0E8E703A87046E3592B71F8C505CBEA05B92534FC699C3CE874C`
**Toolchain:** Acton 1.2.0
**Method:** manual review of the contract's source and of its diff against `escrow_beta_v1.tolk`, plus the project's mutation-testing results: 273 critical-level mutants against `SwapEscrowNosup`, 222 killed, 50 survived (all outside the four security-critical functions — `onBouncedMessage`, `handleClaimAsset`, `runDistributionBatch`, `handleKick` — except two mutants inside them that were confirmed equivalent by manual guard-removal testing), and 1 mutant the mutation harness could not execute because it induces a genuine non-terminating self-message chain rather than a scoreable pass/fail. Symbolic execution (TSA) has not been run against this contract — see [Tooling](#tooling) below.

Line numbers refer to the source at the hash above, as published in this
repository, and were checked against the current file as of this review's
date.

## What this is and is not

This is a **manual security review**, not an audit by a professional audit
firm. No such audit has been performed on this contract. Treat it as evidence
that the diff against the already-reviewed `escrow_beta_v1.tolk` has been
examined systematically, together with the mutation-testing results, not as
assurance that the code is free of defects.

## Result

No exploitable defect was found at this hash. Every item below is a design
property, a trust-model fact, or a documented limitation an integrator should
understand before deploying or depositing — not a flaw to be fixed.

The dominant fact about this contract is the mirror image of the one that
dominates `escrow_beta_v1`: **no address holds unilateral custody over deal
assets or the contract's balance.** That is the entire reason this contract
exists alongside the supervised one, and most of this review is spent
verifying that the diff actually achieves it, rather than cataloguing what a
privileged role could do.

| # | Class | Item |
|---|-------|------|
| 1 | **Trust** | No privileged role exists anywhere in this contract's bytecode |
| 2 | **Trust** | `feeWallet` is an ordinary payee, never a custodian |
| 3 | Design | A bounced delivery marks the asset claimable instead of stalling the deal; only the asset's rightful recipient can pull it, and only to their own address |
| 4 | Design | The batch-completion rule was simplified along with removing retry/park state |
| 5 | Design | `execute_swap` remains `owner1`-only, carried over unchanged |
| 6 | Documented risk | Seven residual ways an asset can remain unrecoverable, none fixable without reintroducing a privileged role |

---

## 1. [Trust] No privileged role exists anywhere in this contract's bytecode

`escrow_beta_v1.tolk` gates six handlers on `sender == sup.supervisor`:
`handleEmergencyCollect` (:1193), `handleEmergencyReturn` (:1279),
`handleEmergencyWithdraw` (:1373), `handleRescueNft` (:1743),
`handleRescueJetton` (:1762) and `handleForceDeliver` (:970), all guarded
through `requireSupervisor` (:1180). None of the six exist in
`escrow_nosup_beta_v1.tolk`: `grep -in supervisor` over the contract and its
`nosup/storage.tolk`/`nosup/messages.tolk` files returns only prose comments
that describe the *absence* of the role, never a field, a handler or a check.
There is no `Storage.sup` field, no `SupervisorState`, no `requireSupervisor`,
and no `DIST_COLLECT`/`DIST_RETURN` distribution modes — `contracts/nosup/storage.tolk`
defines only `DIST_IDLE`, `DIST_EXECUTE` and `DIST_CANCEL` (lines 143-145).

The message-level surface confirms the same thing from the other direction:
the four supervisor-only opcodes from `escrow_beta_v1` —
`SupervisorAssetReceived` (`0x6d5f0001`), `RescueNft` (`0x6d5f0002`),
`RescueJetton` (`0x6d5f0003`) and `ForceDeliver` (`0x6d5f0005`) — are not part
of `EscrowNosupBinaryMessage` (`contracts/nosup/messages.tolk:17-23`), so a
message carrying any of them falls through to `onInternalMessage`'s `else`
branch and throws `Errors.UnknownOp` (`escrow_nosup_beta_v1.tolk:90-92`); the
corresponding text commands (`emergency_collect_assets`,
`emergency_return_assets`, `emergency_withdraw_ton`) are likewise absent from
`handleTextCommand` (`escrow_nosup_beta_v1.tolk:97-132`) and fall through to
the unknown-command `throw 130` (line 131). Both are pinned by
`tests/nosup/smoke.test.tolk`'s `test nosup former supervisor text commands
are unknown` and `test nosup former supervisor binary opcodes are unknown`,
and independently by `ts-tests/nosup.test.ts`'s assertion that
`Errors['Errors.NotSupervisor']` is absent from the generated error enum
(error code 404 does not exist in this contract at all).

`handleKick` (`escrow_nosup_beta_v1.tolk:850-857`) is gated on
`sender == st.owner1 || sender == st.owner2` only (line 852) — the
supervisor branch present in the corresponding check in `escrow_beta_v1.tolk`
has no counterpart here.

## 2. [Trust] `feeWallet` is an ordinary payee, never a custodian

`feeWallet` appears as a message destination in exactly three situations, all
of them read-only value transfers funded by money that was already committed
to leave the contract, never a pull of a deal asset:

- **The combined service fee**, sent once per completed deal
  (`finalizeDistribution:403`, `executeSwapSingleTx:572`).
- **The dust sweep**, which drains whatever is left on the balance after every
  other payout in a finalizing transaction has already been sent
  (`finalizeDistribution:422,433`, `executeSwapSingleTx:597`,
  `handleCancelSwap:990`) — always the function's last statement, after every
  refund, GRAM exchange and asset transfer.
- **A stranger's plain TON transfer**, forwarded rather than absorbed
  (`handlePlainTransfer:641`) — funded by the incoming message's own value
  under `SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE`, not the contract's
  balance, so it cannot be used to drain anything.

No code path sends an NFT, a Jetton, or a party's GRAM deposit to `feeWallet`.
It cannot be substituted at runtime (it is set once, at deploy, alongside
`owner1`/`owner2`), and nothing in this contract treats it as anything other
than a destination address.

## 3. [Design] Bounce-then-claim pull delivery

`escrow_beta_v1.tolk`'s recovery for a failed push delivery is the
supervisor's `rescue_nft`/`rescue_jetton`/`force_deliver`. This contract
replaces all three with two small, unprivileged handlers.

**`onBouncedMessage`** (`escrow_nosup_beta_v1.tolk:1421-1452`) is deliberately
minimal, since it is paid for entirely by the bounced value: a short-body
guard (`remainingBitsCount() < 96`, lines 1423-1425), an opcode filter for
`NftTransfer`/`JettonTransfer` only (lines 1427-1429), a sentinel check that
rejects non-asset queryIds (`>= QUERY_ID_NON_ASSET`, lines 1431-1433) followed
by an independent range check against `assetsCount` (lines 1435-1437) — the
sentinel `0xFFFE` is always ≥ any real `assetsCount`, so the two checks
overlap by construction, which is why a mutation disabling only the sentinel
check is an equivalent mutant (see the mutation-testing note below) — a phase
gate restricting bounces to the three phases in which asset transfers can
actually be outstanding (lines 1438-1440), and a `received` guard (lines
1443-1445). Once past all of that, it saturates `a.bounces` at 15 (lines
1446-1448, a `uint4` field) and sets `a.claimable = true` (line 1449) before a
single `save()` (line 1451). No loop, no distribution logic, no asset leaves
the contract from this handler.

**`handleClaimAsset`** (lines 1026-1073) is the only way a marked asset
leaves the contract outside the normal push path. Its checks run in a fixed
order: the deal must be in a phase where asset transfers are meaningful
(`EXECUTING`/`DONE`/`CANCELLED`, lines 1028-1030, else `AlreadyFinalized`);
the index must be in range (line 1032, else `BadAssetIndex`); the
kind-specific claimability gate (lines 1034-1040) — a Jetton must be marked
`claimable` (line 1035), an NFT must simply be `received` and already behind
the distribution cursor or the distribution already idle (lines 1037-1039,
otherwise `NotClaimable`); the caller must be exactly the deal's rightful
recipient for that asset and phase (lines 1041-1044, computed independently of
anything the caller supplies, else `NotRecipient`); and the caller must have
attached enough value to fund the transfer (lines 1045-1046, else
`InsufficientBalance`). Only after every check passes does it clear the
`claimable` flag if it was set (lines 1048-1052) and send the asset, funded
entirely by the caller's own attached value under
`SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE` (lines 1053-1072) — the
contract's own balance is never spent. The recipient computation
(lines 1041-1043) reads only `st.owner1`/`st.owner2`/`a.ownerSide`/`st.phase`,
so a caller cannot influence who counts as the recipient, and a depositor of
an asset can never be its own recipient once the swap has executed (`phase ==
CANCELLED` is the only phase in which the depositor is the recipient, and a
completed deal cannot return to `CANCELLED`).

The asymmetry between NFTs and Jettons in the second check (line 1035 vs.
1037-1039) is intentional, not an oversight: an NFT item accepts a transfer
only from its current owner, so re-sending an NFT the escrow no longer holds
is harmlessly rejected by the NFT contract, while the escrow's Jetton wallet
for a minter can hold tokens belonging to more than one asset of the deal, so
re-sending without proof of an earlier bounce could move the wrong tokens.
This is documented for integrators in the source comment directly above
`handleClaimAsset` (lines 1009-1025) and in the README.

## 4. [Design] Batch-completion rule simplified along with retry/park removal

`escrow_beta_v1.tolk`'s `runDistributionBatch` carries a `retry` map and a
`retryCount`, drains `retry` at the start of every batch, and distinguishes
three outcomes at the end — finalize, continue, or "park" (stop advancing and
wait for an explicit `kick`) — specifically to give the supervisor's
`force_deliver` something to act on. `Storage.runDistributionBatch` in this
contract (`escrow_nosup_beta_v1.tolk:322-355`) has none of that: `DistState`
carries only `mode` and `cursor` (`contracts/nosup/storage.tolk:147-150`), the
loop is a single linear walk over `received` assets (lines 329-340), and the
completion rule is two-way, not three-way: the cursor has cleared the
registry **and** this transaction sent nothing → finalize in a separate
transaction (lines 342-344, via `finalizeDistribution`); otherwise → send one
more `ContinueDistribution` self-message and keep going (lines 345-353). A
bounce can no longer cause a batch to "park" — it is handled entirely by
`onBouncedMessage` outside the distribution loop, so `runDistributionBatch`
itself does not need to know that a send failed.

`handleContinueDistribution` (lines 835-844) still exists to drive the
self-trigger chain forward and is still restricted to
`sender == contract.getAddress()` (line 836); `handleKick` (lines 850-857)
still exists to resume a chain whose `ContinueDistribution` bounced, gated to
`owner1`/`owner2` only (line 852, see item 1 above) — but since there is no
`retry` state left to redeliver from, a `kick` here can only ever resume the
existing cursor, never re-send an asset the contract has already attempted.

Mutation testing exercised both of these two-way branches directly: one
mutant on `runDistributionBatch`'s own internal `d.mode == DIST_IDLE` guard
(line 324) survives in both directions, but it is unreachable dead code from
every real call site — all four callers (`Storage.executeSwap:263`,
`handleContinueDistribution:842`, `handleKick:855`, `handleCancelSwap:1005`)
already guarantee `dist.mode != DIST_IDLE` before calling it, either by an
assert/early-return immediately above the call or by freshly setting the mode
right before it — so this is a confirmed equivalent mutant, not a gap.

## 5. [Design] `execute_swap` remains `owner1`-only

`handleExecuteSwap` (lines 816-829) asserts `sender == st.owner1` (line 818),
unchanged from `escrow_beta_v1.tolk`. `owner2` cannot trigger manual
execution even with every precondition met; auto-execution
(`Storage.tryAutoExecute`, lines 604-608, invoked from every deposit handler)
covers the normal path, so this only matters when auto-execution has not
fired and `owner1` is unavailable. This asymmetry was carried over
deliberately rather than revisited, since resolving it is unrelated to
removing the supervisor role.

## 6. [Documented risk] Residual unrecoverable-asset cases

Removing the supervisor removes the recovery mechanism for the cases its
rescue handlers existed to cover, and the pull-delivery mechanism in item 3
above closes the ones a rightful recipient can fund themselves out of their
own attached value. What is left is seven narrow cases where no contract-side
mechanism can help without reintroducing exactly the kind of privileged role
this contract is built to avoid. They are listed and explained for
integrators in the README's
["Risks this variant does not remove"](../README.md#risks-this-variant-does-not-remove)
section: an underfunded Jetton overpayment refund, a foreign asset sent
without enough gas for a return, a Jetton whose second internal hop fails
inside the Jetton contract itself, a recipient whose own wallet rejects the
incoming transfer, `owner1`-only manual execution (item 5 above), a
same-deal NFT deposited late without enough gas (recoverable via
`claim_asset`, unlike the fully-foreign case), and a Jetton bounce that never
reaches the escrow. None of the seven were found to have a cheaper fix than
the one already chosen (reject at deploy time, size the attached gas
correctly, or accept the residual risk) without adding a role capable of
moving other people's assets.

The README list has since grown to ten: two further cases surfaced during the
audit pass described below — a rise in the network's gas price outliving a
deployed deal, and a batch deal left one self-message short of finalization
when both owners walk away. Neither is a defect in the code; both are
consequences of pricing a deal at deploy time and of having nobody privileged
to finish it.

---

## Adversarial audit pass

After the implementation was complete, the contract was examined again from
four independent angles, each starting from the source rather than from the
work that produced it: theft and authorization; permanent loss, lockup and
accounting; gas, griefing and limits; and drift against `escrow_beta_v1`.

No exploitable defect was found. Two candidate findings were rejected, and
both rest on the same kind of mistake, so they are recorded here rather than
dropped:

- **"A contract can forge a bounce and mark a Jetton claimable."** It cannot.
  An outbound internal message is normalized during the action phase:
  `bounced` is forced to `false` and `src` is replaced with the sending
  account's address (https://docs.ton.org/foundations/actions/send, "message
  normalization"). Only a genuine failed delivery produces a message the
  recipient sees as bounced, which is why `onBouncedMessage` needs no sender
  check. The emulator can build such a message directly — that is how the
  guard tests reach the handler — but no contract can.
- **"An outsider can drain the balance with cheap messages that trigger the
  registry scans in `handleDeployFee` / `handleTakeWalletAddress`."** It
  cannot. For an internal message, the compute-phase gas limit is the lesser
  of the network maximum and the gas the incoming value can buy; a contract
  spends its own balance on compute only after calling `accept_message`, which
  neither escrow ever does. An underfunded message runs out of gas and changes
  nothing.

What the pass did change is documentation. `required1Count`/`required2Count`
are now named explicitly in the README's deal-validity section, because a
registry can be well-formed while those counts release one side from
depositing anything; the claim section now states that the value check is
against the arriving value, so a claim attached with exactly the minimum
under-funds the transfer it pays for; and the residual-risk list gained the
two cases named above.

Also noted and deliberately left alone: the pro-rata refund weights a side's
whole GRAM contribution rather than only its excess, which can skew leftover
dust by a fraction of the deal's gas — inherited unchanged from
`escrow_beta_v1`; and `QUERY_ID_NON_ASSET` (`0xFFFE`) sits inside the
registry's theoretical `uint16` index space, unreachable because the compute
ceiling caps a deployable deal two orders of magnitude below it.

---

## Checked and found sound

- **No new external-message surface.** `onInternalMessage` and
  `onBouncedMessage` are the only entry points, matching `escrow_beta_v1`;
  no `onExternalMessage` handler was introduced.
- **`ClaimAsset`'s recipient cannot be forged.** The recipient
  (`escrow_nosup_beta_v1.tolk:1041-1043`) is computed from storage the caller
  does not control (`owner1`, `owner2`, `a.ownerSide`, `st.phase`), never from
  a field of the incoming message.
- **Double-claim of a Jetton is prevented before the send.** `handleClaimAsset`
  clears `a.claimable` and calls `st.save()` (lines 1048-1052) *before*
  sending the transfer (lines 1053-1072), so a second `claim_asset` for the
  same index arriving before the first is confirmed sees `claimable == false`
  and is rejected with `NotClaimable`, not a double transfer.
- **Double-claim of an already-delivered NFT is harmless, not free, and its
  gas cost is pinned.** Re-sending an NFT the escrow no longer owns is
  rejected by the NFT item itself; mutation testing found and closed a gap
  where a forced-true claimable-write branch was observably more expensive
  than the real one (7388 gas unmutated vs. 10059 gas mutated on the same
  call), and `tests/nosup/claim.test.tolk` now asserts a gas ceiling on that
  path so a regression that starts writing storage unconditionally would fail
  the test, not just cost more gas silently.
- **The bounce-diagnostic counter cannot overflow.** `a.bounces` is a
  `uint4` and the increment is gated on `a.bounces < 15`
  (line 1446); mutation testing found this guard was never exercised past
  saturation by any pre-existing test and a dedicated 20-bounce test was
  added (`tests/nosup/bounce.test.tolk`).
- **Bounce handling cannot be spoofed.** As in `escrow_beta_v1`, an outbound
  internal message is normalized during the action phase: `bounced` is forced
  to `false` and `src` is replaced with the sending account's address
  (https://docs.ton.org/foundations/actions/send, "message normalization"), so
  a contract cannot emit a message that another contract sees as a bounce. The
  emulator can build such a message directly, which is how the guard tests in
  `tests/nosup/bounce.test.tolk` and `tests/nosup/claim.test.tolk` reach
  `onBouncedMessage`; that is a test-harness capability, not an on-chain one.
  This is why the handler needs no sender check. The
  `QUERY_ID_NON_ASSET` sentinel keeps a non-asset bounce (e.g. a Jetton
  overpayment refund) from ever being misread as a bounce of asset index 0.
- **Atomicity is unchanged from `escrow_beta_v1`.** Every finalizing handler
  sets `phase` before distributing, and an action-phase failure reverts the
  compute phase's storage write, so a distribution goes out whole or not at
  all.
- **The hot loop is untouched.** `executeSwapSingleTx`
  (`escrow_nosup_beta_v1.tolk:442-600`) was copied from `escrow_beta_v1`
  without a single changed instruction in its per-asset send loops (lines
  519-568), preserving the gas calibration `tests/nosup/gas_probe.test.tolk`
  pins.
- **Unwind paths still scale with the registry.** `handleCancelSwap` and
  `Storage.executeSwap` both gate the fast-path/batch-path decision on
  `assetsCount` (lines 941 and 252 respectively), matching `escrow_beta_v1`'s
  reasoning for not exhausting the 1,000,000-gas ceiling on a large,
  lightly-deposited deal.

---

## Tooling

Symbolic execution (TSA) has not been run against `SwapEscrowNosup`. This
review is manual-plus-mutation-testing only; a symbolic run, following the
same drain-check / bounce-check methodology used for `escrow_beta_v1` in
`docs/SECURITY-REVIEW-2026-09-11.md`, is planned but has not happened yet, and
no symbolic-analysis results — positive or negative — are claimed here.

---

## Reproducing

```bash
acton build                # verify both code hashes (see README's "Verifying the build")
acton test                 # full suite: 364 passed, 3 skipped
npm install && npm test    # TypeScript wrappers against Tolk-side fixtures, both contracts
```

Mutation testing (critical level, this contract only):

```bash
acton test tests/nosup --mutate --mutate-contract SwapEscrowNosup --mutation-levels critical
```

Note: on Acton 1.2.0, the toolchain this review was produced with, that exact
invocation hangs on one specific mutant (removing the `save()` in
`handleContinueDistribution`), which induces a genuine non-terminating
self-message cascade the harness had no timeout for — a tooling limitation,
not a defect in the contract. The totals above were obtained by selecting
mutation IDs in batches that exclude it (`--mutation-id <list>`). The
behaviour was reported upstream and fixed after 1.2.0
(https://github.com/ton-blockchain/acton/issues/1282), so a newer toolchain
runs the command in one pass.
