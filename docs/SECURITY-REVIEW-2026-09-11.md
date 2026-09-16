# SwapEscrow — Security Review

**Date:** 2026-09-11
**Subject:** `contracts/escrow_beta_v1.tolk`, `contracts/storage.tolk`, `contracts/messages.tolk`
**Code hash reviewed:** `41F7882FE4445147DAC4907FF6AEB60C32C4F7A5F43BFE5357433C18D41418D3`
**Toolchain:** Acton 1.1.0 (9cf4d1f, 2026-05-22)
**Method:** manual source review plus symbolic execution with TSA (TON Symbolic Analyzer) v0.5.5, following the `espritoxyz/ton-ai-audit-skill` procedure.

Line numbers refer to the source at the hash above, as published in this
repository.

## What this is and is not

This is an **automated-plus-manual security review**, not an audit by a
professional audit firm. No such audit has been performed on this contract.
Treat it as evidence that the code has been examined systematically, not as
assurance that it is free of defects.

## Result

No exploitable defect was found at this hash. Every item below is a design
property or an operational caveat that an integrator should understand before
deploying or depositing — not a flaw to be fixed.

The single most important of them is the first: **the supervisor can take
everything.** That is deliberate, and it is the dominant risk in this contract.

| # | Class | Item |
|---|-------|------|
| 1 | **Trust** | Supervisor holds unilateral custody of all assets and TON |
| 2 | **Trust** | The registry is trusted as deployed — no on-chain validation of storage invariants, and no check of token identity beyond the recorded minter |
| 3 | Design | `execute_swap` is `owner1`-only |
| 4 | Operational | Repeated `kick` against a permanently rejecting recipient burns balance |

---

## 1. [Trust] Supervisor holds unilateral custody

Six handlers are gated only on `sender == sup.supervisor`, with no participant
consent and no time lock:

| Handler | Power |
|---|---|
| `emergency_withdraw_ton` | Sweeps the **entire balance** to the supervisor. No phase gate — it works in `ACTIVE`, mid-deal, over both sides' deposits and service fees. |
| `emergency_collect_assets` | Sends every received deal asset to the supervisor and finalizes the deal. |
| `emergency_return_assets` | Finalizes the deal, returning assets to depositors. |
| `rescue_nft` / `rescue_jetton` | Transfers an arbitrary NFT, or an arbitrary amount from the escrow's jetton wallet, to the supervisor. No phase gate. |
| `force_deliver` (`fallback: true`) | Marks an asset abandoned; the swap can then finalize with a party never receiving it, while the remaining balance is swept to `feeWallet`. |

A compromised or malicious supervisor key can take everything at any point in a
deal's life. Depositing into a deal means trusting whoever holds that key as
much as a conventional custodian, and verifying who the supervisor is before
depositing is the depositor's responsibility.

This is stated in the README's *Trust model* section, which also describes the
supervisor-free variant planned alongside this contract.

---

## 2. [Trust] The registry is trusted exactly as deployed

The contract is deployed with its full registry inside `stateInit` and trusts
that state unconditionally at runtime. Two consequences follow, and both land on
whoever builds the deal rather than on the contract.

**Well-formedness is not checked.**

- `assets` is assumed to hold exactly the keys `0 .. assetsCount-1`.
  `handleDeployFee:767`, `handleTakeWalletAddress:841`, `matchJettonAsset:1533`
  and `runDistributionBatch:351` all use `mustGet(i)` over that range; a short
  map makes the corresponding handler throw permanently.
- `jettonsCount` selects which distribution loop `executeSwapSingleTx:540`
  takes. Set to 0 on a registry containing jetton assets, the NFT-only loop
  sends a TIP-4 `NftTransfer` to a jetton *minter*, and `assetTransferCost`
  underestimates the distribution cost.
- `pendingWallets` is not derived from the registry. Too high leaves the deal in
  `SETUP` forever; set to 0 with unresolved jetton assets, the
  `st.pendingWallets -= 1` at `escrow_beta_v1.tolk:861` underflows a `uint16`
  and serialization throws, permanently breaking discovery.

**Token identity is only as good as the recorded minter.** Deposit validation
is genuine — a jetton deposit is accepted only from the wallet TEP-89 discovery
resolved for the minter in the registry, only from the side's own owner, and
only for exactly the recorded amount — but every one of those checks is relative
to that registry entry. The contract stores a minter address and never a name or
symbol, so a registry naming a different minter is executed faithfully.

Because the address is a hash of code and data, a malformed or substituted deal
is simply a *different address*, and a user reaches it only if something sends
them there. The README section *What the contract validates, and what it cannot*
describes the client-side address-derivation check that detects both cases.

---

## 3. [Design] `execute_swap` is `owner1`-only

`handleExecuteSwap:910` asserts `sender == st.owner1`, so `owner2` cannot
trigger manual execution even with every precondition met. Auto-execution covers
the normal path — the deposit that completes the deal executes it — so this
matters only when auto-execution has not fired and `owner1` is unavailable.

Worth surfacing to integrators, and worth revisiting alongside the
supervisor-restricted variant: opening this call up would also let a service
address trigger execution, which keeps the distribution out of a user's own
transaction.

Note that manual execution deliberately performs **no balance check**;
`canAutoExecute` does, and `available` inside `executeSwap` clamps to 0 if the
balance is short. Any change to who may call it should add that check.

---

## 4. [Operational] Repeated `kick` burns balance against a rejecting recipient

Each `kick` that redelivers from `retry` sends real transfers funded from the
contract's balance (`NFT_TRANSFER_VALUE` / `JETTON_TRANSFER_VALUE` each) and
then parks. Against a recipient that permanently rejects, repeated kicks consume
balance without progress.

`handleKick:952` is restricted to `owner1`, `owner2` and the supervisor, so this
is not an anonymous attack — but one owner can degrade the other's refund this
way. The automatic continue chain deliberately does not redeliver from `retry`
for the same reason; only an explicit kick does.

---

## Checked and found sound

- **No external-message surface.** No `onExternalMessage` handler exists, so
  there is no `accept_message` gas-drain path and no external replay surface.
- **No signature-based authorization anywhere**, so the replay-attack class does
  not apply.
- **Carry-value discipline.** NFT receipt verifies `assets[hint].addr == sender`
  before accepting a hinted index; jetton receipt requires the TEP-89-resolved
  wallet to match the sender *and* the depositor to match the side owner. A
  forged index cannot introduce a foreign asset.
- **No unprivileged value extraction.** Every unauthenticated return path —
  `returnForeignNft:1416`, `returnJettons:1474` — is funded by the inbound
  message via `SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE`, never from the
  contract's balance.
- **Bounce handling cannot be spoofed.** Validators rewrite `src` and the
  `bounced` flag, so a contract cannot forge either. Transfers that are not
  registry assets carry reserved queryId sentinels (`QUERY_ID_NON_ASSET`,
  `QUERY_ID_RESCUE_REGISTRY`) that `onBouncedMessage` filters, so a bounce of
  one can never be mistaken for a bounce of asset index 0.
- **Atomicity.** `phase` is set before distribution in every finalizing handler,
  and an action-phase failure reverts the compute phase's `c4`, so a
  distribution either goes out whole or not at all. Re-entry is impossible.
- **Arithmetic.** Pro-rata refunds multiply before dividing
  (`available * contrib1 / totalContrib`) and take the remainder for the second
  side, so no nanoton is created or lost. The two `divide-before-multiply` lint
  suppressions are ceiling divisions (`(n + K - 1) / K`) multiplied afterwards —
  correct as written.
- **`Asset.bounces`** saturates at 15, so the `uint4` cannot overflow.
- **`ContinueDistribution`** is gated on `sender == contract.getAddress()`; no
  external party can drive the batch chain.
- **`Excesses`** is accepted silently rather than thrown, so a legitimate
  TEP-74 excess refund is not bounced back.
- **Unwind paths scale with the registry.** `cancel_swap`,
  `emergency_return_assets` and `emergency_collect_assets` all gate on
  `assetsCount`, matching `Storage.executeSwap`, so a deal with a large registry
  and few deposits routes into the batch engine rather than exhausting the
  1,000,000-gas ceiling in a single transaction. Pinned by
  `tests/batch_cancel.test.tolk`.

---

## Tooling: what TSA did and did not cover

TSA analyses TVM bytecode, so the source language is irrelevant in principle.
Two runs were made, and they differ in how much they are worth.

### Symbolic `c4` — crippled, do not rely on

With unconstrained persistent data, the symbolic interpreter reaches a
cell-building instruction it does not implement — one the Acton/Tolk compiler
emits inside a lambda in this contract:

```
kotlin.NotImplementedError: An operation is not implemented:
TvmCellBuildStirInst(location=Lambda:#14, ...)
    at org.usvm.machine.interpreter.TvmCellInterpreter.visitCellBuildInst
```

v0.5.5 tolerates it but drops every symbolic state that reaches the
instruction. The setup itself is sound — the three Tolk-compiled mocks in this
repository (`NftItemMock`, `JettonMinterMock`, `JettonWalletMock`) analyse to
completion — so the limitation is specific to this contract's bytecode.

That run produced 257 results (158 `cell-underflow`, 67 `integer-out-of-range`,
32 `user-defined-error 65535`). None are treated as findings: all three classes
are artifacts of handing arbitrary persistent data to a contract that assumes
well-formed storage — item 2 above — and the `65535` is the contract's own
`Errors.UnknownOp`, i.e. intended behaviour.

### Concrete `c4` — meaningful

Repeating the analysis with real persistent data avoids the unimplemented
instruction entirely (**zero** `NotImplementedError` occurrences) and explores
the contract properly. The `c4` was built from `wrappers-ts/SwapEscrow.gen.ts`;
its cell hash `7503F91E…` matches the Tolk reference fixture from
`scripts/gen_init_fixture.tolk` bit for bit, so the analysed state is a genuine
deal state rather than a hand-made approximation.

The `drain-check` checker — "can a non-privileged sender receive more TON than
it sent?" — was run against a funded 3-asset deal in `PHASE_ACTIVE` with a 5 TON
balance. It explored 23 exported executions and reached, among others, exit
codes `0` (81 successful paths), `9`, `403` (`NotOwners`), `404`
(`NotSupervisor`), `130` (unknown text command) and `65535` (`UnknownOp`) —
i.e. it genuinely walked the dispatcher and the handlers.

**Result: no findings.**

To confirm the checker can fire at all, it was also run against a deliberately
drainable FunC contract (`recv_internal` sweeping the balance to the sender with
mode 128). That positive control reported the expected violation (exit code
1000), so the negative above is a real negative — for this storage
configuration. It is not a statement about every reachable state.

The **inter-contract `bounce-check`** was run on the same concrete state,
pairing the escrow with a contract that throws on every message (exit 256) so
that all of the escrow's outgoing messages bounce back. The checker asserts two
properties: that handling a bounce does not itself fail, and that the escrow
sends no messages while processing one. Neither was violated — the checker's own
code 1000 does not appear anywhere in the results. The 39 reported terminations
are the escrow's ordinary rejections (`403`, `404`, `410`, `130`, `65535`), the
thrower's deliberate `256`, and exit `9` on malformed bodies.

The `replay-attack` checker was not run: the contract has no signature-based
authorization and no external-message handler, so the property is vacuous here.

**Recommendation:** report the unimplemented instruction upstream at
`github.com/espritoxyz/tsa`, so that symbolic analysis over *arbitrary* storage
becomes available for Tolk contracts as well.

---

## Reproducing

```bash
acton build                # verify the code hash above
acton test                 # full suite: 186 passed, 2 skipped
npm install && npm test    # TypeScript wrapper against Tolk-side fixtures
```

TSA:

```bash
npm i tsa-installer && npx tsa-installer install
java -jar tsa-cli.jar boc -i SwapEscrow.boc -o report.sarif --timeout 900
java -jar tsa-cli.jar custom-checker --checker drain-check.fc \
     -c Boc SwapEscrow.boc -o drain.sarif
```
