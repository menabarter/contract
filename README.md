# SwapEscrow

An escrow swap contract for [TON](https://ton.org): two parties deposit assets —
NFTs, GRAM (native TON), and Jettons — and the swap executes automatically once
both sides are fully funded. Either party can cancel before completion. A
supervisor role can also intervene at any time — see
[Trust model](#trust-model) below for exactly what that role can do.

Written in [Tolk](https://docs.ton.org/tolk/overview), built and tested with
[Acton](https://ton-blockchain.github.io/acton/) 1.2.1 (Tolk 1.5.0).

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
that value minus this transaction's own cost: attaching exactly the minimum
measures 0.029332 TON delivered of the 0.03 TON NFT minimum, and 0.048852 TON
of the 0.05 TON Jetton minimum. Attach headroom — 0.1 TON for an NFT, 0.2 TON
for a Jetton is comfortable. If the transfer bounces — an NFT the escrow no
longer owns, a Jetton wallet that rejects the credit — the bounce returns to
the escrow's own balance, not to the claimer, so a bounced claim costs the
claimer whatever value they attached, even though it moves nothing. An
under-funded Jetton claim additionally clears the claimable mark before
sending, so if the failure is severe enough that no bounce comes back, the
asset cannot be marked claimable again. Check `get_nft_data()` on the item
before claiming an NFT, to avoid paying for a claim it will simply reject.

Two getters expose this state for a client to build a claim UI against:
`claimableAssets()` returns the indices currently marked claimable, and
`assetStatus(idx)` returns one asset's `(received, claimable, bounces)`. One
caveat worth knowing before wiring up a "claim" button: an NFT's `claimable`
flag can be **stale** — claiming an NFT that was in fact already delivered
does not move the asset (the NFT contract rejects the transfer since the
escrow is no longer the owner), but still costs the claimer the value they
attached, and the bounce from that rejected attempt sets `claimable = true`
again regardless. So check who currently owns the NFT — `get_nft_data()` —
before offering the button, rather than trusting the flag alone. Jetton
claimability does not have this staleness problem, since a Jetton bounce is
proof the tokens are still on the escrow's wallet.

#### Settlement

Every coin that arrives is recorded against the side that sent it, and each
side pays for moving its own assets — sending an NFT costs `NFT_TRANSFER_VALUE`
(0.03 TON), a Jetton costs `JETTON_TRANSFER_VALUE` (0.05 TON), whether the
transfer is a delivery on execute or a return on cancel. Everything else the
deal spends belongs to neither side alone — execution or cancel gas, the
self-triggered batch messages, and the storage floor described below — and is
split equally between the two. On execute, `feeWallet` receives `2 ×
SERVICE_FEE` plus the final sweep — the unused part of the execution gas
reserve, plus `DUST`, plus any refund below the dust minimum; whatever a side
paid above its own `SERVICE_FEE` is part of its contribution and comes back to
it in its refund. A refund smaller than the dust minimum (`DUST`, or two plain
forward fees if those ever exceed it) is not sent: below one forward fee it
could not pay its own forwarding and would abort the whole execution, so it
goes to `feeWallet` with the sweep instead, as a sub-`DUST` leftover does on
cancel. A small round-up over the `executionShortfall()` figure therefore
settles the deal and ends up with `feeWallet`. On cancel no service
fee is charged at all — each side's own `SERVICE_FEE` payment is simply part
of its contribution and comes back to it through its refund like anything
else — and `feeWallet` receives only the sweep: the unused part of this
transaction's own gas and any leftover below the threshold for splitting
between the two owners (sub-`DUST` amounts). A side's refund or the
canceller's surplus below two plain forward fees (about 0.00013 TON) is not
sent by the cancel either and goes to `feeWallet` with the sweep: anyone can
move the refunds with an unattributed inflow, and an amount below one forward
fee would otherwise abort the cancel. The bound here is the forwarding cost
rather than the dust minimum, so the pre-check gas allowance `cancelCost()`
adds (about 0.0027 TON) still comes back to the canceller. In both cases a side's refund is
its own contribution minus half of the shared costs, computed from the actual
balance rather than from the per-side counters alone, so an overstated
counter can never pay out more than the balance holds.

#### Funding before execution

Before the swap can run, each side must cover its own TON leg (if the deal has
one), its `SERVICE_FEE`, the cost of sending its own assets onward, and half
of the shared costs above. `executionShortfall()` returns, per side, the
amount after which the leg checks (420/421), the per-side funding checks
(433/434) and the balance check (430) pass, assuming the `SERVICE_FEE` is paid
through its own command (`service_fee_owner1`/`service_fee_owner2`) and the
rest is paid as a TON payment — `deposit_ton1`/`deposit_ton2`, a plain
transfer, or `execute_swap` itself. It does not look at the fee counter: an
unpaid `SERVICE_FEE` still fails with 422/423 even after paying the returned
amount. Per side it first takes the larger of what the per-side check and the
leg check still need. The gas spent processing each deposit comes out of the
shared balance rather than out of the per-side counters (which credit deposit
value gross), so these two amounts together can leave the balance short of
what execution needs; while the deal is in SETUP or ACTIVE, that deficit is
split equally on top of the two figures (side 2 takes the odd nanoton). The
balance check counts the paying message's value before its own gas, so the
payment that completes the deal needs nothing extra. When both sides pay
figures read at the same time, the first payment's own gas (758,401 nanoton
for a `deposit_ton1`/`deposit_ton2` at today's gas price) is already gone
when the second arrives: each side adds 0.001 TON to its figure. Once one
side's payment has landed, re-reading shows that side owing only its half of
the remaining deficit; the other side can then pay both figures and the deal
executes. `execute_swap`
credits whatever value the caller attaches to that owner's own contribution
before checking anything, so a single message can both pay a shortfall and
execute. A side with only a TON leg and no assets pays its half of the shared
costs on top of the leg and the fee, since it has no transfer cost of its own
to offset it.

#### Execution

A deposit that completes the deal's funding is recorded in storage before the
contract attempts to execute the swap, so the record survives even if the
execution attempt itself runs short of gas; execution's own gas comes from a
reserve the funding check has already confirmed is on the balance, not from
the value the completing message happened to carry. If a deposit could record
itself but not pay for the funding check, the deal simply waits: either owner
can then call `execute_swap` to finish it. `execute_swap` is open to both
owners, credits whatever value the caller attaches to that owner's own
contribution before checking anything — so a single message can both pay a
shortfall and execute — and checks funding in this order, most specific
first: each side's TON leg (codes 420/421), each side's service fee (422/423),
that both sides have deposited every required asset (424), each side's
overall funding share (433/434, naming which side is short), and finally that
the balance itself covers everything execution is about to send (430).

#### Cancel

`cancelCost()` returns `(required, value to attach)` for a cancel sent right
now. The canceller's attachment covers any shortfall — its own side first,
then the other side's — and anything left over comes back to the canceller.
Because cancel must always be possible, a side that underfunded its own
deposits can make the other side pay to get out of the deal; that is the
price of cancel never getting stuck on an underfunded counterparty.

#### After settlement

A settled escrow — executed or cancelled — keeps `storageFloor()` on its
balance: a year of storage fees for the deal's own state, so the account does
not freeze while `claim_asset` may still be needed. A TON account whose
storage debt passes roughly 0.1 TON is frozen by the network; without this
reserve, a settled escrow that ended with a near-zero balance would eventually
freeze exactly when a stuck asset still needed pulling. The last transaction's
unused execution gas — on the order of 0.04 TON on a 50×50 deal, more on
larger ones — goes to `feeWallet` along with the rest of what settlement
sweeps. A bounce — of a claim, of a delivery, of any other outgoing message —
and a late `Excesses` message both simply stay on the escrow's balance above
the floor once settled; nothing sweeps either afterwards. Other late arrivals
are handled individually: an owner's plain TON transfer bounces once the deal
is finalized, a stranger's plain transfer is forwarded on to `feeWallet`
rather than kept, and a late NFT deposit carrying enough value to fund a
return is sent back to its sender rather than staying on the balance.

#### Deposits

An NFT deposit's sender is checked against the registry only when the
notification carries at least 0.03 TON (`RETURN_TRANSFER_VALUE`, enough to
fund returning it); below that, the item is credited to whichever side's free
slot it matches, regardless of who actually sent it. Sending a registry item with a forward amount below about 0.00072 TON
(measured on a 10×10 deal; the exact figure moves with deal size) means the
notification cannot pay for the escrow's own transaction to record it: that
transaction runs out of gas before the registry update commits, so the item
is not recorded and does not count toward the deal's funding, even though it
has already moved to the escrow. Once the deal is cancelled, that side's
owner can still pull such an item out with `claim_asset` — but the claim is
refused with 432 if the same NFT address also occupies a slot on the *other*
side (recorded or not), since the escrow may be holding it for that side
instead; such an item then stays with the escrow, so never list one NFT
address on both sides of the same deal. The claim scans the whole registry
for this check at the claimer's own expense, about 1,350 gas per entry: on a
typical deal (up to 100 entries) the claim transaction uses about 135,000 gas,
about 0.009 TON at today's gas price, paid from the attachment. The scan
cannot exceed the 1,000,000-gas limit of a single transaction whatever the
attachment, so on a registry above about 740 entries this claim always runs
out of gas (measured: 740 entries 993,827 gas; 760 entries out of gas) and
such an unrecorded item cannot be pulled out at all. Running out of gas
simply bounces the attached value back without moving anything. A foreign NFT or
Jetton — one that matches no free slot — is
returned to its sender only if its notification carries the same 0.03 TON;
below that, it simply stays with the escrow. A Jetton sent with a zero
`forward_ton_amount` never triggers a transfer notification at all, so it
lands in the escrow's Jetton wallet without the escrow ever learning of it.

The `forward_payload` index hint on an NFT deposit is checked by exactly the
same rule the fallback search uses — a free (unreceived) registry slot for
that item's address, and, when the value can fund a return, that address's
side owner as the sender — so a wrong or stale hint simply falls through to
the search rather than being accepted at face value. The search itself skips
any slot already marked received, so, absent a hint, an item address listed
in two registry slots fills its first free slot on its first arrival and its
second slot on its second — but a valid hint is checked directly against the
slot it names, so it can land the item in whichever of that address's free
slots the hint points to, not necessarily the one the search would pick.

#### Jetton wallets

The escrow trusts the wallet address a Jetton's minter names in its TEP-89
`take_wallet_address` response and has no way to verify it independently —
this is the trust TEP-89 discovery always carries, not something specific to
this contract.

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
5. **An NFT belonging to the deal that arrives late and without enough gas**
   for a bounce — say, sent again by mistake by whoever now holds it — can
   still be pulled out by the deal's rightful recipient via `claim_asset`;
   without that, it would be stuck the same way risk 2 describes.
6. **A Jetton bounce that never reaches the escrow** (this needs a
   non-standard Jetton wallet on the escrow's side — in practice essentially
   never, since 0.05 TON comfortably covers a standard wallet's bounce) leaves
   the tokens neither delivered nor claimable.
7. **The value carried by a bounced delivery or a late arrival after
   settlement is not returned to anyone.** A bounce, or a late `Excesses`
   that reaches the escrow after it has settled, lands on the balance above
   the storage floor described in [After settlement](#after-settlement) rather than being
   forwarded anywhere, and nothing sweeps it afterwards: `claim_asset` is
   funded by the value the claimer attaches and forwards that value onward,
   and this variant has no privileged withdrawal to reach it instead. It
   affects only deals where a delivery bounced or something arrived late,
   never the assets themselves, and it is the direct cost of having no
   privileged role to redirect that value.
8. **A large rise in the network's gas price outlives a deployed deal.** The
   contract prices its own compute dynamically, so its internal reserves
   follow the network, but the values it hands to other contracts —
   `NFT_TRANSFER_VALUE` (0.03 TON), `JETTON_TRANSFER_VALUE` (0.05),
   `PROVIDE_WALLET_VALUE` (0.02), `RETURN_TRANSFER_VALUE` (0.03) — are set at
   deploy and cannot be raised for a deal that already exists. If gas becomes
   materially more expensive, deliveries in already-deployed deals start
   failing for want of gas. This is survivable rather than fatal precisely
   because of `claim_asset`: a failed delivery leaves the asset with its
   rightful recipient to pull, at whatever value the network then demands. A
   deal still in SETUP is the harder case, since TEP-89 discovery has no pull
   equivalent — `cancel_swap` is the exit. Separately, a settled escrow with no
   storage-floor reserve would eventually be frozen by the network once its
   storage debt passed roughly 0.1 TON; `storageFloor()` (see
   [After settlement](#after-settlement)) exists precisely to keep that from
   happening while `claim_asset` may still be needed.
9. **A batch deal one message short of finalization needs a `kick`.** When
   the final batch of a large deal is the one that sent assets, the contract
   defers finalization — the GRAM legs, the service fee, the refunds
   and the sweep — to one more self-message. That message is ordinary: it can
   fail, and its bounce is deliberately ignored. Either owner resumes the
   chain with `kick`, and the assets themselves are already delivered by that
   point; but if both owners walk away believing the deal is finished, the
   TON legs stay on the contract, and unlike registry assets they have no
   pull equivalent. A client should watch `distributionProgress()` and offer
   `kick` while it reports anything other than idle. On the batch execute
   path specifically, each self-triggered continue message's value is paid
   out of what the funding check left on the balance for exactly this
   purpose — mainly the `2 × SERVICE_FEE` that has not yet been sent to
   `feeWallet` — which at today's gas price holds up to roughly a 4×
   increase in the network's gas price before it runs short; beyond that the
   chain can stop partway and needs `kick` the same way.

One more risk leaves no asset stuck but blocks the deal: **a TON leg smaller
than one forward fee (about 0.00007 TON) cannot be delivered.** The leg goes
out as a plain message that pays its own forwarding; below one forward fee
that fails the action phase, so every execution attempt — `execute_swap` and
the deposit that completes the deal alike — aborts, and the deal can only be
cancelled. The contract does not reject such a leg at deploy: whoever builds
the deal must not create one, and should keep every TON leg at least `DUST`
(0.003 TON).

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
(`76×76` fails where `152×0` of the same total passes).

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
| `contracts/nosup/accounting.tolk` | pure settlement math for `SwapEscrowNosup` — who paid what, per-side transfer costs, and the refund split — with no storage access of its own |
| `contracts/nft_item_mock.tolk`, `jetton_wallet_mock.tolk`, `jetton_minter_mock.tolk`, `jetton_mock_lib.tolk`, `nft_item_gas_mock.tolk` | NFT and Jetton mocks (and their shared helper code) used by tests only; `nft_item_gas_mock.tolk` models an NFT with a higher gas threshold, for the `SwapEscrowNosup` claim tests |
| `tests/` | 189 tests across 21 test files for `SwapEscrow`, plus a shared test-helper module |
| `tests/nosup/` | 260 tests across 29 test files for `SwapEscrowNosup`, plus a shared test-helper module |
| `wrappers/`, `wrappers-ts/` | generated wrappers for Tolk tests and TypeScript consumers, for both contracts |
| `ts-tests/` | validates both TypeScript wrappers against Tolk-side cell-hash fixtures |
| `scripts/` | deployment and testnet smoke scripts, for both contracts |
| `docs/` | the security reviews |
| `.github/` | CI workflow (build, format check, lint, tests) |

Build artifacts (`build/`, `.acton/`) are generated locally and are not part of
the repository.

## Build and test

Requires Acton 1.2.1, which bundles Tolk 1.5.0.

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

A code hash depends on the compiler as well as the source.

The deployed `SwapEscrow` was built with Acton 1.2.0 (Tolk 1.4.2), which
compiles it to:

```
41F7882FE4445147DAC4907FF6AEB60C32C4F7A5F43BFE5357433C18D41418D3
```

The same source compiles to a different hash with the current toolchain
(Acton 1.2.1, Tolk 1.5.0):

```
25811004DF61AAB86E8A06292804E9AE88E18A06CC6FF54E88CAFE510BEA9B3B
```

To check the deployed contract, build this source with Acton 1.2.0.

The compiled code hash of `SwapEscrowNosup` with the current toolchain is:

```
BDECE3AAC1685E18CEF537F2E9F23ADAB49C6BAF363AFC217D9BC06DCCF4BB58
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
