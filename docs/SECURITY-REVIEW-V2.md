# SwapEscrowV2 — Security Review

**Subject:** `contracts/escrow_beta_v2.tolk`, `contracts/v2/storage.tolk`, `contracts/v2/messages.tolk`, `contracts/v2/accounting.tolk`, reviewed as the supervisor's additions to `SwapEscrowNosup` (`contracts/escrow_nosup_beta_v1.tolk`, covered by [SECURITY-REVIEW-NOSUP.md](SECURITY-REVIEW-NOSUP.md)) and compared with the supervisor of `SwapEscrow` (`contracts/escrow_beta_v1.tolk`, covered by [SECURITY-REVIEW-2026-09-11.md](SECURITY-REVIEW-2026-09-11.md))
**Code hash:** `D8F57AC6FDB816172157AA098818CCF7C9883EFD2A6E8E2699B0483461B7C7EA` (Acton 1.2.1, Tolk 1.5.0)
**Status:** written by the contract's authors. **An independent review is pending.** Symbolic execution has not been run against this contract.

## What this is and is not

This document records the supervisor's attack surface in `SwapEscrowV2`, each
command's worst outcome, and the tests that pin each property. It is not an
audit and not an independent review: treat it as a map of what to check, not
as assurance that the code is free of defects.

## Scope: only the supervisor's code is new

Outside the blocks marked `// sup:begin` … `// sup:end`, `SwapEscrowV2` is
`SwapEscrowNosup` line for line; regions marked `// variant:begin` …
`// variant:end` exist in both files and may differ (the header, the imports,
the incoming-message union, the registry walk's send condition and the storage
floor's base). `ts-tests/v2-sync.test.ts` enforces this on every `npm test`.
`tests/v2/` runs the complete `SwapEscrowNosup` suite against `SwapEscrowV2`;
the differences it allows are listed with reasons in
`ts-tests/v2-test-overrides.json` and are of two kinds only:

- measurements that move with the larger code and state (the storage floor, a
  gas edge, two refund figures that depend on the floor);
- the two `SwapEscrowNosup` checks that the supervisor's commands do not exist,
  which on `SwapEscrowV2` become checks that they fail with 404 for anyone but
  the supervisor.

Everything `SECURITY-REVIEW-NOSUP.md` establishes about settlement, funding,
`claim_asset`, distribution and the one-signature flow therefore applies here
unchanged. This document covers the rest.

## Result

| # | Class | Item |
|---|-------|------|
| 1 | **Trust** | The supervisor can take every asset of the deal and the whole balance |
| 2 | **Trust** | The supervisor cannot change a deal's terms or move anything without its own command |
| 3 | Design | Every supervisor command checks the sender before anything else |
| 4 | Design | `emergency_return_assets` settles by the deal's own rules and charges the supervisor for the operation |
| 5 | Design | `emergency_collect_assets` leaves jetton slots whose wallet is unconfirmed |
| 6 | Design | `ForceDeliver` follows `claim_asset`'s admission, and an asset is delivered once |
| 7 | Documented risk | Supervisor actions that cost the parties or leave the escrow exposed |

---

## 1. [Trust] The supervisor can take every asset of the deal and the whole balance

`emergency_collect_assets` sends every received asset and every NFT in the
rescue registry to the supervisor; `emergency_withdraw_ton` sends the whole
balance to the supervisor in any phase; `RescueNft` and `RescueJetton` send a
named NFT or a named jetton amount to the supervisor in any phase;
`ForceDeliver` with `fallback = true` delivers a recorded asset to the
supervisor. This is the same custody `SwapEscrow`'s supervisor has: anyone
depositing into a `SwapEscrowV2` deal trusts whoever holds the supervisor's
key. The supervisor is fixed per deal in the storage cell `sup`
(`SupervisorState`), part of `stateInit`, so it is visible before depositing
and through the getter `supervisor()`.

## 2. [Trust] What the supervisor cannot do

The registry, amounts, owners and fee wallet are fixed in `stateInit`; no
supervisor command writes them. The supervisor cannot execute the swap on
different terms, cannot send an asset to anyone but its rightful recipient or
itself, and cannot make the contract send anything without sending one of its
seven commands itself.

## 3. [Design] The sender check comes first

Every supervisor handler starts with `requireSupervisor`, which throws 404
before any other check or state change. `tests/v2/sup_basic.test.tolk` sends
all seven commands from an owner and expects 404 and an unchanged deal; the
generated `smoke.test.tolk` does the same for the text commands.

## 4. [Design] `emergency_return_assets`

Phases `SETUP` and `ACTIVE`; the deal becomes `CANCELLED`.

- **Settlement.** The refunds split `R = balance − attachment − own returns −
  DUST − storage floor` with `splitRefunds`, the same function cancel and
  execute use: each side gets what it paid less its own returns and half of
  what the deal shared. The attachment is excluded from `R`, so the
  supervisor pays this transaction's gas and the parties do not pay for an
  operation they did not ask for. `sup_return.test.tolk` checks the refund sum
  to within 0.00001 TON and the two sides' outlays to within one nanoton.
- **No sweep.** Nothing is sent to `feeWallet`; `DUST` and the storage floor
  stay on the escrow, where `emergency_withdraw_ton` can reach them.
- **Rollback.** If the balance cannot pay the returns, the action phase fails
  and the whole transaction rolls back (tested).
- **Batch chain.** Above 100 registry entries the returns run as a chain of
  self-messages whose later transactions are paid from the balance; the
  attachment must cover them (`emergencyChainReserve`), or the command fails
  with 430 and nothing changes (tested at the boundary). Without that check a
  small attachment would let the chain spend the storage floor and stop
  halfway.
- **Unconfirmed jetton slots** go back through the wallet side 2 claimed in
  `AcceptDeal`; the deposit was made through that wallet, so returning through
  it reaches the depositor (tested).

**Difference from `SwapEscrow`:** there each side was refunded its recorded
payments less its own returns, regardless of what the balance held (deposit
gas is credited gross, so the sum could exceed it), and a batch return had no
chain reserve check.

## 5. [Design] `emergency_collect_assets`

Phases `SETUP` and `ACTIVE`; the deal becomes `CANCELLED`; no TON is refunded.
A jetton slot recorded against a claimed wallet that the minter has not
confirmed (`walletUnverified`) is not sent, on the fast path and on the batch
path alike (`Storage.sendReceived`, `runDistributionBatch`): the claimed
address may not be the escrow's wallet, and the escrow cannot tell. A minter's
answer after the command is ignored because the deal has left `SETUP`, so the
slot stays unconfirmed; the supervisor can check the wallet and take the
tokens with `RescueJetton`. `sup_collect.test.tolk` covers both paths,
including an unconfirmed slot at the end of a 101-entry registry. The same
chain reserve as in section 4 applies above 100 entries (430).

**Difference from `SwapEscrow`:** unconfirmed slots do not exist there.

## 6. [Design] `ForceDeliver`

Phases `EXECUTING`, `DONE`, `CANCELLED` — where `claim_asset` is open — with
`claim_asset`'s admission for recorded assets: a jetton only while marked
claimable, an NFT once received and passed by the distribution. An NFT the
escrow never recorded is `RescueNft`'s case. `fallback = false` delivers to
`claim_asset`'s recipient (the counterparty after execution, the depositor
after cancel); `fallback = true` delivers to the supervisor. The transfer is
paid by the attachment (mode 64, at least the asset's transfer value, else
430), and the claimable mark is cleared before sending.

An asset goes out once: a jetton needs the mark that the first delivery
clears (`claim_asset` then `ForceDeliver` → 432, tested), and an NFT item
refuses a transfer from an escrow that no longer owns it (tested both ways).

After `emergency_collect_assets` the phase is `CANCELLED`, so an asset whose
delivery to the supervisor bounced is pulled by whoever comes first: the
depositor with `claim_asset` or the supervisor with `fallback = true`
(tested).

**Difference from `SwapEscrow`:** there `ForceDeliver` worked on the
distribution's retry state, and `fallback` parked an asset for a later rescue.

## 7. [Documented risk] Supervisor actions that cost the parties or leave the escrow exposed

1. **A compromised or hostile supervisor key** takes everything (section 1).
2. **`emergency_withdraw_ton` removes the storage floor.** After it the
   escrow's balance is zero; storage fees accrue as debt, and a long-unpaid
   escrow freezes. `claim_asset` is funded by its own attachment, but a frozen
   account cannot run it until someone pays the debt.
3. **A `ForceDeliver` that the asset refuses** costs the supervisor's
   attachment, which bounces back to the escrow's balance, not to the
   supervisor. A refused NFT is then marked claimable again although the
   escrow no longer holds it; a client should check the item's owner before
   offering a claim (as for `SwapEscrowNosup`).
4. **`RescueNft` and `RescueJetton` are paid from the balance**, as in
   `SwapEscrow`: each sends a fixed `NFT_TRANSFER_VALUE` or
   `JETTON_TRANSFER_VALUE` in mode 0 regardless of what the supervisor
   attached. On an active deal that is the parties' money; on a settled one it
   comes out of the storage floor. `RescueJetton` sends to whatever wallet the
   supervisor names; the escrow does not know its wallets' balances.
5. **`emergency_collect_assets` on a deal in `SETUP`** leaves any unconfirmed
   jetton deposit for `RescueJetton` (section 5); until then the depositor
   cannot pull it, since `claim_asset` only serves recorded deliveries that
   bounced.

## Tests

- `tests/v2/sup_basic.test.tolk` — the sender check, the getter, withdraw,
  rescue, the rescue registry.
- `tests/v2/sup_return.test.tolk` — settlement, rollback, the chain reserve,
  an unconfirmed jetton, a repeated command (410).
- `tests/v2/sup_collect.test.tolk` — the rescue registry, unconfirmed slots on
  both paths, the chain reserve, a repeated command (410).
- `tests/v2/sup_force_deliver.test.tolk` — both recipients, both phases,
  single delivery, the gates, the batch cursor, the case after collect.
- `tests/v2/sup_code_hash.test.tolk` — the code hash above.
- `tests/v2/*` (generated) — the whole `SwapEscrowNosup` suite.

## Tooling

**Mutation testing** (Acton 1.2.1, critical and major levels, at the hash
above): every line `SwapEscrowV2` adds or changes relative to
`SwapEscrowNosup` — the supervisor's blocks, the variant lines and the storage
floor — gave 104 mutants against `tests/v2/`: 102 killed, 0 survived, 2 did not
compile. The rest of the contract is `SwapEscrowNosup`'s code, whose mutants
are covered by that contract's own runs; the lines `SwapEscrowNosup` changed
for this release (the owner's `deploy_fee` on an active deal and the storage
floor's variant line) gave 42 mutants against `tests/nosup/`, all killed.

**Testnet:** `scripts/smoke_v2_supervisor_testnet.tolk` (`emergency_return_assets`
on a 1x1 deal; `ForceDeliver` with both `fallback` values after both
deliveries of a deal bounced) and `scripts/smoke_v2_onesig_testnet.tolk` (the
one-signature jetton flow) passed on the TON testnet.

Symbolic execution (TSA) has not been run.
