# SwapEscrowNosup — Security Review

**Date:** 2026-09-29
**Subject:** `contracts/escrow_nosup_beta_v1.tolk`, `contracts/nosup/storage.tolk`, `contracts/nosup/accounting.tolk`, `contracts/nosup/messages.tolk`, reviewed as a diff against `contracts/escrow_beta_v1.tolk` (code hash `41F7882FE4445147DAC4907FF6AEB60C32C4F7A5F43BFE5357433C18D41418D3`, covered by `docs/SECURITY-REVIEW-2026-09-11.md`)
**Code hash reviewed:** `A76E7AE03669554882BA6371CCC9A70060E00E583AC9721F001575E25F6B99C0`
**Later addition:** section 7 describes the one-signature jetton flow
(`AcceptDeal`, claimed wallets, per-minter discovery pricing, the no-cut
top-up in `executionShortfall`) added after this review; it records the design
and its tests, and its independent review is pending.
**Toolchain:** Acton 1.2.0 (Tolk 1.4.2). The repository has since moved to Acton 1.2.1 (Tolk 1.5.0); the reviewed source is unchanged and compiles there to `BDECE3AAC1685E18CEF537F2E9F23ADAB49C6BAF363AFC217D9BC06DCCF4BB58`.
**Method:** manual review of the contract's source and of its diff against `escrow_beta_v1.tolk`, plus the project's mutation-testing results: 273 critical-level mutants against `SwapEscrowNosup`, 222 killed, 50 survived (all outside the four security-critical functions — `onBouncedMessage`, `handleClaimAsset`, `runDistributionBatch`, `handleKick` — except two mutants inside them that were confirmed equivalent by manual guard-removal testing), and 1 mutant the mutation harness could not execute because it induces a genuine non-terminating self-message chain rather than a scoreable pass/fail. These mutation-testing counts were not obtained at the code hash stated above as reviewed — the mutation run predates later changes to this code — and mutation testing has not been re-run to confirm they still hold at this hash; no claim is made here that they do. Symbolic execution (TSA) has not been run against this contract — see [Tooling](#tooling) below.

References name functions, constants and messages rather than line numbers,
so they hold across later edits. Since this review the shared types and
settlement math have moved to `contracts/shared/` (`types.tolk`,
`accounting.tolk`, `messages.tolk`); the per-contract storage, error codes and
message union stay in `contracts/nosup/`.

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
| 3 | Design | A bounced delivery marks the asset claimable instead of stalling the deal; an NFT the escrow never recorded can be claimed after cancel; only the asset's rightful recipient can pull an asset, and only to their own address |
| 4 | Design | The batch-completion rule was simplified along with removing retry/park state |
| 5 | Design | `execute_swap` is open to both owners and checks funding through an ordered set of codes |
| 6 | Documented risk | Nine residual ways an asset can remain unrecoverable, none fixable without reintroducing a privileged role |

---

## 1. [Trust] No privileged role exists anywhere in this contract's bytecode

`escrow_beta_v1.tolk` gates six handlers on `sender == sup.supervisor`:
`handleEmergencyCollect`, `handleEmergencyReturn`,
`handleEmergencyWithdraw`, `handleRescueNft`,
`handleRescueJetton` and `handleForceDeliver`, all guarded
through `requireSupervisor`. None of the six exist in
`escrow_nosup_beta_v1.tolk`: `grep -in supervisor` over the contract and its
`nosup/storage.tolk`/`nosup/messages.tolk` files returns only prose comments
that describe the *absence* of the role, never a field, a handler or a check.
There is no `Storage.sup` field, no `SupervisorState`, no `requireSupervisor`,
and no `DIST_COLLECT`/`DIST_RETURN` distribution modes — the contract's
types define only `DIST_IDLE`, `DIST_EXECUTE` and `DIST_CANCEL`.

The message-level surface confirms the same thing from the other direction:
the four supervisor-only opcodes from `escrow_beta_v1` —
`SupervisorAssetReceived` (`0x6d5f0001`), `RescueNft` (`0x6d5f0002`),
`RescueJetton` (`0x6d5f0003`) and `ForceDeliver` (`0x6d5f0005`) — are not part
of the contract's message union (`EscrowInMessage` in
`contracts/nosup/messages.tolk`), so a
message carrying any of them falls through to `onInternalMessage`'s `else`
branch and throws `Errors.UnknownOp`; the
corresponding text commands (`emergency_collect_assets`,
`emergency_return_assets`, `emergency_withdraw_ton`) are likewise absent from
`handleTextCommand` and fall through to
its unknown-command `throw 130`. Both are pinned by
`tests/nosup/smoke.test.tolk`'s `test nosup former supervisor text commands
are unknown` and `test nosup former supervisor binary opcodes are unknown`,
and independently by `ts-tests/nosup.test.ts`'s assertion that
`Errors['Errors.NotSupervisor']` is absent from the generated error enum
(error code 404 does not exist in this contract at all).

`handleKick` is gated on
`sender == st.owner1 || sender == st.owner2` only — the
supervisor branch present in the corresponding check in `escrow_beta_v1.tolk`
has no counterpart here.

## 2. [Trust] `feeWallet` is an ordinary payee, never a custodian

`feeWallet` appears as a message destination in exactly three situations, all
of them read-only value transfers funded by money that was already committed
to leave the contract, never a pull of a deal asset:

- **The combined service fee**, sent once per completed deal
  (`finalizeDistribution` and `executeSwapSingleTx`).
- **The dust sweep**, which drains whatever is left on the balance above the
  storage floor (see the README's [After settlement](../README.md#after-settlement))
  after every other payout in a finalizing transaction has already been sent
  (`finalizeDistribution`, both branches, and `executeSwapSingleTx`) —
  always the function's last statement, after every
  refund, GRAM exchange and asset transfer. A refund below the dust minimum
  (`refundMinimum()`: `DUST`, or two plain forward fees if those ever exceed
  it) is not sent and goes to `feeWallet` with this sweep — on execute, for
  each side's refund (`executeSwapSingleTx` and `finalizeDistribution`'s
  execute branch), and in the cancel finale, for the leftover
  split (`finalizeDistribution`'s cancel branch). Above one forward fee such a refund
  would arrive mostly eaten by forwarding; below it the refund cannot pay its
  own forwarding in mode 0, fails the action phase with result code 37 and
  aborts the whole transaction — on a completing NFT or Jetton deposit that also discards the
  deposit's record, since COMMIT does not survive an action-phase failure
  (pinned by `tests/nosup/execute_refund_min.test.tolk`). The amount is below
  `DUST` per side. The cancel's initiating transaction uses a lower bound for
  each side's refund and the canceller's surplus (`handleCancelSwap`):
  two plain forward fees (`sendableMinimum()`, about 0.00013 TON), enough for
  the message to pay its own forwarding, so the pre-check gas allowance that
  `cancelCost()` adds still comes back to the canceller. Anyone can move the
  refunds with an unattributed inflow (an `Excesses` is credited without
  checks and split equally), so without this rule a stranger could keep a
  deal from being cancelled (pinned by `tests/nosup/cancel_refund_min.test.tolk`).
  On the batch path an amount held back is not counted as queued, so it stays
  in the finale's split or sweep.
- **A stranger's plain TON transfer**, forwarded rather than absorbed
  (`handlePlainTransfer`) — funded by the incoming message's own value
  under `SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE`, not the contract's
  balance, so it cannot be used to drain anything.

No code path sends an NFT, a Jetton, or a party's GRAM deposit to `feeWallet`.
It cannot be substituted at runtime (it is set once, at deploy, alongside
`owner1`/`owner2`), and nothing in this contract treats it as anything other
than a destination address.

## 3. [Design] Bounce-then-claim pull delivery, plus a claim path for an unrecorded NFT

`escrow_beta_v1.tolk`'s recovery for a failed push delivery is the
supervisor's `rescue_nft`/`rescue_jetton`/`force_deliver`. This contract
replaces all three with two small, unprivileged handlers, plus a third claim
path for an NFT the escrow never recorded at all.

**`onBouncedMessage`** is deliberately
minimal, since it is paid for entirely by the bounced value: a short-body
guard (`remainingBitsCount() < 96`), an opcode filter for
`NftTransfer`/`JettonTransfer` only, a sentinel check that
rejects non-asset queryIds (`>= QUERY_ID_NON_ASSET`) followed
by an independent range check against `assetsCount` — the
sentinel `0xFFFE` is always ≥ any real `assetsCount`, so the two checks
overlap by construction, which is why a mutation disabling only the sentinel
check is an equivalent mutant (see the mutation-testing note below) — a phase
gate restricting bounces to the three phases in which asset transfers can
actually be outstanding, and a `received` guard. Once past all of that, it
saturates `a.bounces` at 15 (a `uint4` field) and sets `a.claimable = true`
before a single `save()`. No loop, no distribution logic, no asset leaves
the contract from this handler.

**`handleClaimAsset`** is the only way
a marked asset leaves the contract outside the normal push path. Its checks
run in the same order on every call: the deal must be in a phase where asset
transfers are meaningful (`EXECUTING`/`DONE`/`CANCELLED`,
else `AlreadyFinalized`); the index must be in range (else
`BadAssetIndex`); then a kind- and state-specific claimability gate — a
Jetton must be marked `claimable`; an NFT
that was received follows the delivery cursor instead and needs no bounce
mark at all (`NotClaimable` otherwise), since an NFT item
only ever honours a transfer from its current owner and a second attempt at
one already delivered is simply rejected by the item itself; an NFT that was
**never received** — the registry slot exists, but the item either never
arrived or arrived with a forward too small to be recorded — can only be
claimed once the deal is `CANCELLED`, and only if the same NFT
address does not also occupy a slot on the *other* side
(`Storage.hasCrossSideDuplicate`): the
registry does not forbid listing one address twice, so without this check the
claim could hand the item to the wrong side's owner if the escrow is actually
holding it for the other side. The current-owner check inside the NFT item
itself is what keeps this branch safe even when the item never arrived at
all, since the transfer is then simply refused and nothing moves beyond the
claimer's own attached value. The duplicate scan costs about 1,350 gas per
registry entry and no attachment buys more than the 1,000,000-gas
transaction limit, so on a registry above about 740 entries this branch
always runs out of gas and an unrecorded item there cannot be claimed (see
the README's [Deposits](../README.md#deposits) section). After the
claimability gate, the caller must be
exactly the deal's rightful recipient for that asset and phase (computed
independently of anything the caller supplies, else
`NotRecipient`), and must have attached enough value to fund the transfer
(else `InsufficientBalance`). Only after every check passes
does it clear the `claimable` flag if it was set and send
the asset, funded entirely by the caller's own attached value under
`SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE` — the
contract's own balance is never spent. The recipient computation
reads only `st.owner1`/`st.owner2`/`a.ownerSide`/`st.phase`, so a
caller cannot influence who counts as the recipient, and a depositor of an
asset can never be its own recipient once the swap has executed (`phase ==
CANCELLED` is the only phase in which the depositor is the recipient, and a
completed deal cannot return to `CANCELLED`).

The asymmetry between NFTs and Jettons in the received-asset case is
intentional, not an oversight: an NFT item
accepts a transfer only from its current owner, so re-sending an NFT the
escrow no longer holds is rejected by the NFT contract itself — though not
for free, since the claimer's own attached value funds that rejected attempt
and the bounce it produces returns to the escrow's balance, not to the
claimer (see the README's claim section). The escrow's Jetton wallet for a
minter, by contrast, can hold tokens belonging to more than one asset of the
deal, so re-sending without proof of an earlier bounce could move the wrong
tokens. This is documented for integrators in the source comments directly
above `handleClaimAsset` and `Storage.hasCrossSideDuplicate`, and in the
README.

## 4. [Design] Batch-completion rule simplified along with retry/park removal

`escrow_beta_v1.tolk`'s `runDistributionBatch` carries a `retry` map and a
`retryCount`, drains `retry` at the start of every batch, and distinguishes
three outcomes at the end — finalize, continue, or "park" (stop advancing and
wait for an explicit `kick`) — specifically to give the supervisor's
`force_deliver` something to act on. `Storage.runDistributionBatch` in this
contract has none of that: `DistState`
carries only `mode` and `cursor`, the
loop is a single linear walk over `received` assets, and the
completion rule is two-way, not three-way: the cursor has cleared the
registry **and** this transaction sent nothing → finalize in a separate
transaction (via `finalizeDistribution`); otherwise → send one
more `ContinueDistribution` self-message and keep going. A
bounce can no longer cause a batch to "park" — it is handled entirely by
`onBouncedMessage` outside the distribution loop, so `runDistributionBatch`
itself does not need to know that a send failed.

`handleContinueDistribution` still exists to drive the
self-trigger chain forward and is still restricted to
`sender == contract.getAddress()`; `handleKick`
still exists to resume a chain whose `ContinueDistribution` bounced, gated to
`owner1`/`owner2` only (see item 1 above) — but since there is no
`retry` state left to redeliver from, a `kick` here can only ever resume the
existing cursor, never re-send an asset the contract has already attempted.

Mutation testing exercised both of these two-way branches directly: one
mutant on `runDistributionBatch`'s own internal `d.mode == DIST_IDLE` guard
survives in both directions, but it is unreachable dead code from
every real call site — all four callers (`Storage.executeSwap`,
`handleContinueDistribution`, `handleKick`, `handleCancelSwap`)
already guarantee `dist.mode != DIST_IDLE` before calling it, either by an
assert/early-return immediately above the call or by freshly setting the mode
right before it — so this is a confirmed equivalent mutant, not a gap.

## 5. [Design] `execute_swap` is open to both owners and checks funding through an ordered set of codes

`handleExecuteSwap` accepts either
owner (`sender == st.owner1 || sender == st.owner2`) — unlike
`escrow_beta_v1.tolk`, which restricts manual execution to `owner1`. Whatever
value the caller attaches is credited to that owner's own TON leg before any
check runs, so a single message can both cover a shortfall
and trigger execution. The checks then run from the most specific to the
most general, each with its own error code: each side's TON leg
(`NotEnoughTon1`/`NotEnoughTon2`, 420/421), each side's service
fee (`ServiceFee1`/`ServiceFee2`, 422/423), that both sides
have received every required asset (`NftsNotReceived`, 424),
each side's overall funding share via `Storage.sideFunded`
(`SideUnderfunded1`/`SideUnderfunded2`, 433/434), and finally
that the balance itself covers everything execution is about to send via
`Storage.balanceCovers` (`InsufficientBalance`, 430). Ordering the
checks this way means a caller who is short on exactly one thing is told
which one, rather than getting a single generic failure regardless of cause.
`Storage.sideFunded`/`Storage.sideShare` and the shared-cost split
(`Storage.sharedCosts`) live in `escrow_nosup_beta_v1.tolk` itself; they
build on the pure settlement math in `contracts/shared/accounting.tolk`
(`paidBy`, `transferCost`, `splitRefunds`, `noClampTopUps`), which has no
storage access of its own, and on `Storage.ownTransferCost` and
`Storage.registryTransferCost` in `contracts/nosup/accounting.tolk`. Both are
exercised directly by `tests/nosup/accounting.test.tolk`.

The get-method `executionShortfall()`
exposes, per side, the amount that still has to be paid for the leg check,
the overall funding check and the balance check to pass (the balance deficit
split equally on top of the per-side amounts), so a client can quote a
shortfall before sending anything; `cancelCost()` and
`storageFloor()` do the same for the cancel path and the
post-settlement reserve respectively (see the README's
[Funding before execution](../README.md#funding-before-execution),
[Cancel](../README.md#cancel) and [After settlement](../README.md#after-settlement)
sections).

## 6. [Documented risk] Residual unrecoverable-asset cases

Removing the supervisor removes the recovery mechanism for the cases its
rescue handlers existed to cover, and the pull-delivery mechanism in item 3
above closes every one a rightful recipient can fund themselves out of their
own attached value. What is left is nine narrow cases where no contract-side
mechanism can help without reintroducing exactly the kind of privileged role
this contract is built to avoid — from an underfunded Jetton overpayment
refund and a foreign asset sent without enough gas for a return, to a large
rise in the network's gas price outliving a deployed deal and a batch deal
left one self-message short of finalization. They are listed and explained
for integrators in the README's
[Risks this variant does not remove](../README.md#risks-this-variant-does-not-remove)
section, together with the settlement, funding and cancel mechanics
described in the sections immediately above it. None of the nine have a
cheaper remedy than the one already chosen for each (reject at deploy time,
size the attached gas correctly, keep a storage-floor reserve, or accept the
residual risk) without adding a role capable of moving other people's assets.

The same README section also records one risk that strands no asset but
blocks a deal: a TON leg smaller than one forward fee (about 0.00007 TON)
cannot be delivered — its plain message cannot pay its own forwarding, the
action phase fails with result code 37, and every execution attempt aborts,
leaving cancel as the only exit (checked in the emulator with a 1,000-nanoton
leg). The contract does not reject such a leg at deploy; whoever builds the
deal must keep every TON leg at least `DUST`.

---

## 7. [Design] Jetton deal in one signature: claimed wallets the minter confirms

**`handleAcceptDeal`** is accepted only
from `owner2` (402) and only in SETUP or ACTIVE (410). Its value is credited
to side 2 (fee, then TON leg, then reserve) before anything else and is never
refused for being small: discovery starts only if the value covers
`discoveryCost`, otherwise the message only credits. A registry whose claim
and discovery passes could exceed one transaction's gas
(`Storage.acceptWorkUnits`, a measured model with about 1.2x
margin) also only credits. A first message that fails in its handler still
deploys the account (pinned by a test), so the transfers of the same batch
reach the contract's code.

**`Storage.writeClaims`** writes a claimed address only into a
side-2 jetton slot with no wallet, setting `walletUnverified`. The matching
rule for notifications is unchanged (`Storage.jettonAssetMatches`): the
sender must equal the slot's wallet and the depositor the
slot's side owner. Consequences checked by tests: a stranger's notification
matches neither a claimed nor a confirmed address; a claim never touches side
1, so side 1's assets cannot be obtained with a false claim; owner2's false
claim can record a provisional deposit, which nothing can execute on, because
execution requires ACTIVE and ACTIVE requires every minter's answer.

**`handleTakeWalletAddress`** treats a minter as resolving when
it has at least one pending slot (no wallet or `walletUnverified`) — not
`jettonWallet == null`, which would leave a fully claimed deal in SETUP
forever. A received slot whose claim the minter contradicts (another address
or `addr_none`) is un-received and the counters are reduced; the TON the
deposit carried stays credited to side 2. `addr_none` erases the claim and
does not decrement `pendingWallets`. When the last minter answers, the state
is saved and committed before `tryAutoExecuteAfterWalk`, whose
gas limit is execution's units on top of the gas already used, capped at the
transaction ceiling: if execution runs out, ACTIVE and the resolution survive
and `execute_swap` settles. The answer is still ignored outside SETUP.

**Discovery pricing** (`Storage.provideValueFor`) is per minter:
the request, a walk of the registry, and the worst write (an undone
provisional deposit) for each of that minter's slots. An owner's `deploy_fee`
is credited to that owner; a stranger's is unattributed and shared.

**`executionShortfall`** adds top-ups (`noClampTopUps`,
`contracts/shared/accounting.tolk`) so that neither side's settlement share is
cut at zero:
without them, a side that prepaid more (owner2 pays deployment and discovery
up front) would cover part of the other side's half. The execution gate
(`sideFunded`) is unchanged; the top-up is about exact halves, not safety.

Residual risks: transfers that reach the escrow's address before any message
deployed it are lost (the client places `AcceptDeal` first and checks the
wallet balance); a minter whose slots exceed `TAKE_MAX_SLOTS` may never
answer within one transaction (the deal stays cancellable).

## Adversarial audit pass

After the implementation was complete, the contract was examined again from
four independent angles, each starting from the source rather than from the
work that produced it: theft and authorization; permanent loss, lockup and
accounting; gas, griefing and limits; and drift against `escrow_beta_v1`.

No exploitable defect was found. One theory raised during the pass does not
hold up, and it rests on a distinction worth stating explicitly, so it is
recorded here rather than dropped:

- **"An outsider can drain the balance with cheap, underfunded messages that
  trigger the registry scans in `handleDeployFee` / `handleTakeWalletAddress`."**
  It cannot. For an internal message, the compute-phase gas limit starts as
  the lesser of the network maximum and the gas the incoming value can buy; a
  contract spends its own balance on compute only after raising that limit —
  via `accept_message` or, as this contract does, `setGasLimit`
  (in `tryAutoExecute`, `tryAutoExecuteAfterWalk`, `handleExecuteSwap` and
  `handleCancelSwap`). The theory above still
  does not hold up, but not because the contract never raises the limit: it
  does, through `setGasLimit`, but only after the funding gate has already
  passed —
  auto-execution's `canAutoExecute` checks, `execute_swap`'s own checks
  (420-434, 430), or cancel's balance check (430 via `quoteCancel`) — so an
  *underfunded* message that never gets past those checks simply runs out of
  gas on the value it carried and changes nothing.

  That reasoning does not, by itself, cover a **fully funded** `deploy_fee`
  call, which does forward real value through the contract:
  `handleDeployFee` sends one TEP-89
  `ProvideWalletAddress` per unresolved minter, and a caller who pays exactly
  for those sends — without also paying for the registry scan that finds
  them — could repeat the call, fully funded every time, and have the
  escrow's own balance quietly cover the scan on each repetition: what such a
  call spends beyond its own attached value is the escrow's own gas walking
  the registry, not a forwarding fee handed to anyone. `handleDeployFee` prices
  that scan directly: `Storage.discoveryCost` adds
  `calculateGasFee(BASECHAIN, DEPLOY_BASE_GAS_UNITS + DEPLOY_GAS_UNITS_PER_ASSET
  × assetsCount)` to the per-minter provide values, and the call asserts
  `value >= discoveryCost` before sending anything, so the caller who triggers
  the scan is
  the one who pays for it, on every call, not only on ones that happen to be
  cheap for the escrow.

Two things this pass surfaced live in the documentation rather than above.
`required1Count`/`required2Count` are named explicitly in the
README's deal-validity section, because a registry can be well-formed while
those counts release one side from depositing anything. The claim section
states that the value check is against the arriving value, so a claim
attached with exactly the minimum under-funds the transfer it pays for. The
residual-risk list also covers two cases beyond the ones the implementation
itself surfaced: a rise in the network's gas price outliving a deployed deal,
and a batch deal left one self-message short of finalization when both owners
walk away.

Also noted and deliberately left alone: `QUERY_ID_NON_ASSET` (`0xFFFE`) sits
inside the registry's theoretical `uint16` index space, unreachable because
the compute ceiling caps a deployable deal two orders of magnitude below it.

---

## Checked and found sound

- **No new external-message surface.** `onInternalMessage` and
  `onBouncedMessage` are the only entry points, matching `escrow_beta_v1`;
  no `onExternalMessage` handler was introduced.
- **`ClaimAsset`'s recipient cannot be forged.** The recipient
  in `handleClaimAsset` is computed from storage the caller
  does not control (`owner1`, `owner2`, `a.ownerSide`, `st.phase`), never from
  a field of the incoming message.
- **Double-claim of a Jetton is prevented before the send.** `handleClaimAsset`
  clears `a.claimable` and calls `st.save()` *before*
  sending the transfer, so a second `claim_asset` for the
  same index arriving before the first is confirmed sees `claimable == false`
  and is rejected with `NotClaimable`, not a double transfer.
- **A repeated claim of an already-delivered NFT does not move the asset
  twice, but is not free.** Re-sending an NFT the escrow no longer owns is
  rejected by the NFT item itself, so the asset never moves a second time —
  but the claimer's own attached value funded that rejected attempt, and the
  bounce it produces is not returned to them. `tests/nosup/claim.test.tolk`
  asserts a gas ceiling on this call (the real path costs 7388 gas; a
  mutant that writes storage unconditionally on this branch costs 10059), so
  a regression that starts writing storage unconditionally here fails the
  test, not just costs more gas silently.
- **The bounce-diagnostic counter cannot overflow.** `a.bounces` is a
  `uint4` and the increment in `onBouncedMessage` is gated on
  `a.bounces < 15`;
  `tests/nosup/bounce.test.tolk` includes a dedicated 20-bounce test that
  exercises this guard past saturation.
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
- **A transaction's own action phase is atomic; the batch chain as a whole is
  not all-or-nothing.** Every finalizing handler sets `phase` before
  distributing, and an action-phase failure reverts that transaction's
  storage write, so any single transaction's own sends go out in full or not
  at all — unchanged from `escrow_beta_v1`. A large deal's distribution,
  though, spans several transactions (`Storage.runDistributionBatch`,
  chained through `continueMsgValue` and
  `batchChainReserve`), and the chain as a whole can stop
  partway: a self-triggered `ContinueDistribution` can bounce, and its bounce
  is deliberately ignored (item 4), leaving the chain waiting for `kick`; a
  single asset send inside an otherwise-successful batch can itself bounce,
  in which case the batch keeps going and the failed asset is marked
  claimable rather than rolling the whole batch back (`onBouncedMessage`).
  This is a liveness cost of pricing the chain at a set gas budget per
  batch, not a correctness gap: `claim_asset` (item 3) exists precisely so a
  bounced send never blocks the rest of the deal, and `kick` exists precisely
  so a stalled chain never needs anything more privileged than either owner
  to resume.
- **The hot loop is untouched.** `executeSwapSingleTx` was copied from
  `escrow_beta_v1` without a single changed instruction in its per-asset send
  loops (its two `while (r.isFound)` loops), preserving the gas calibration
  `tests/nosup/gas_probe.test.tolk` pins.
- **Unwind paths still scale with the registry.** `handleCancelSwap` and
  `Storage.executeSwap` both gate the fast-path/batch-path decision on
  `assetsCount`, matching `escrow_beta_v1`'s
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
acton test                 # full suite
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
