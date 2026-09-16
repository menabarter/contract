// SwapEscrow — escrow swap contract for TON: NFT, GRAM and Jetton deposits.
// Copyright (C) 2026 MENA
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License
// for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import "@acton/tolk-stdlib/gas-payments"
import "messages"
import "storage"

contract SwapEscrow {
    author: "MENA"
    version: "2.0.0-stage2"
    description: "Escrow swap v2 stage 2: NFT + GRAM + Jetton deposits"
    storage: Storage
    incomingMessages: EscrowBinaryMessage
}

// `textCmdIs(cmd: slice, expected: slice)` does not compile: every call site
// such as `textCmdIs(cmd, "deploy_fee")` fails with "can not pass `string` to
// `slice`", because Tolk — unlike FunC — does not implicitly coerce string
// literals to slice. So `expected` takes a `string`, and the comparison goes
// through slice.hash() (common.tolk:652, a representation hash of the
// content) on its `.beginParse()` — the same function used for `cmd` (not
// string.hash(), which is a different algorithm, FNV-1a — the two must not
// be mixed, since the outputs would not match).
fun textCmdIs(cmd: slice, expected: string): bool {
    return cmd.hash() == expected.beginParse().hash();
}

// Early stub signatures took `in: InMessage` as an ordinary parameter
// (`fun handlePlainTransfer(in: InMessage) { ... }`), but the compiler
// rejects this: "using `in` as an object is prohibited, because `InMessage`
// is a built-in struct, its fields are mapped to TVM instructions"
// (common.tolk:1906 — `in.senderAddress`/`in.body` are not fields of an
// ordinary struct but accesses that get expanded into asm instructions;
// `InMessage` itself cannot be passed around as a value). So the router
// unpacks the needed fields (`senderAddress`, `valueCoins`) at call time and
// passes them to the handlers as ordinary `address`/`coins` parameters —
// exactly what the real handler implementations need for checking the
// sender and amount.
fun onInternalMessage(in: InMessage) {
    if (in.body.isEmpty()) {
        handlePlainTransfer(in.senderAddress, in.valueCoins);
        return;
    }
    val op = in.body.preloadUint(32);
    if (op == 0) {
        var cmd = in.body;
        cmd.skipBits(32);
        handleTextCommand(in.senderAddress, in.valueCoins, cmd);
        return;
    }
    val msg = lazy EscrowBinaryMessage.fromSlice(in.body);
    match (msg) {
        OwnershipAssigned => {
            handleNftReceived(in.senderAddress, in.valueCoins, msg);
        }
        TakeWalletAddress => {
            handleTakeWalletAddress(in.senderAddress, in.valueCoins, msg);
        }
        SupervisorAssetReceived => {
            handleSupervisorAssetReceived(in.senderAddress, in.valueCoins, msg);
        }
        RescueNft => {
            handleRescueNft(in.senderAddress, in.valueCoins, msg);
        }
        RescueJetton => {
            handleRescueJetton(in.senderAddress, in.valueCoins, msg);
        }
        JettonTransferNotification => {
            handleJettonNotification(in.senderAddress, in.valueCoins, msg);
        }
        Excesses => {
            // leftover gas from a jetton wallet (if someone set the escrow as
            // responseDestination) — silently credited to the balance; NOT
            // 0xFFFF, or a legitimate excesses message would get bounced
        }
        ContinueDistribution => {
            handleContinueDistribution(in.senderAddress);
        }
        ForceDeliver => {
            handleForceDeliver(in.senderAddress, in.valueCoins, msg);
        }
        else => {
            throw Errors.UnknownOp;
        }
    }
}

// Text commands — part of the wire protocol integrators depend on
fun handleTextCommand(sender: address, value: coins, cmd: slice) {
    if (textCmdIs(cmd, "deploy_fee")) {
        handleDeployFee(sender, value);
        return;
    }
    if (textCmdIs(cmd, "deposit_ton1")) {
        handleDepositGram(sender, value, 1);
        return;
    }
    if (textCmdIs(cmd, "deposit_ton2")) {
        handleDepositGram(sender, value, 2);
        return;
    }
    if (textCmdIs(cmd, "service_fee_owner1")) {
        handleServiceFee(sender, value, 1);
        return;
    }
    if (textCmdIs(cmd, "service_fee_owner2")) {
        handleServiceFee(sender, value, 2);
        return;
    }
    if (textCmdIs(cmd, "execute_swap")) {
        handleExecuteSwap(sender, value);
        return;
    }
    if (textCmdIs(cmd, "cancel_swap")) {
        handleCancelSwap(sender, value);
        return;
    }
    if (textCmdIs(cmd, "emergency_collect_assets")) {
        handleEmergencyCollect(sender, value);
        return;
    }
    if (textCmdIs(cmd, "emergency_return_assets")) {
        handleEmergencyReturn(sender, value);
        return;
    }
    if (textCmdIs(cmd, "emergency_withdraw_ton")) {
        handleEmergencyWithdraw(sender, value);
        return;
    }
    if (textCmdIs(cmd, "kick")) {
        handleKick(sender, value);
        return;
    }
    // Unknown text command -> exit 130; part of the wire contract
    throw 130;
}

// Single point for computing the gas reserve for a distribution of `sends`
// transfers. GETGASFEE includes a flat price component (the first
// flat_gas_limit units) — one call over the TOTAL units, rather than `sends`
// separate calls: the flat component is counted once, so the result is ≥ the
// linear estimate (the margin errs on the safe side).
fun execGasReserve(sends: int): coins {
    return calculateGasFee(BASECHAIN, EXEC_GAS_UNITS_BASE + EXEC_GAS_UNITS_PER_SEND * sends);
}

// Extra gas reserve for the additional transactions in the batch chain for
// finalizing operations (cancel/emergency_return/emergency_collect). Same
// formula as gasReserveForSwap (execute path): ceil(sends/K) surcharges —
// one per batch of assets beyond the first, PLUS a separate final
// transaction (see runDistributionBatch). No surcharge for
// <=100 sends (fast path is single-transaction).
// The result MUST feed into the asserted `required` value of cancel's
// balance check, or a long chain will come up short on gas for its trailing
// batches.
fun batchExtraReserve(sends: int): coins {
    if (sends <= FAST_PATH_MAX_ASSETS) {
        return 0;
    }
    val batches = (sends + BATCH_MAX_SENDS - 1) / BATCH_MAX_SENDS;
    // `batches` is a ceiling division: (n + K - 1) / K. Multiplying the batch
    // COUNT by the per-batch gas cost is the intended arithmetic — multiplying
    // before dividing would compute a different quantity entirely.
    // check-disable-next-line divide-before-multiply
    return calculateGasFee(BASECHAIN, BATCH_EXTRA_GAS_UNITS * batches);
}

// The gas-reserve and minimum-balance formulas are computed from the deal's
// PARAMETERS (gram1Amount/gram2Amount from GramState, assetsCount), never
// from the current received counters. This is deliberate: a threshold derived
// from what has arrived so far would drift as deposits come in, so the same
// deposit could pass or fail depending on ordering.
fun Storage.gasReserveForSwap(self, g: GramState): coins {
    val totalNfts = self.assetsCount as int;
    var numExtra = 3; // fee_wallet + refund1 + refund2
    if (g.gram1Amount > 0) {
        numExtra += 1;
    }
    if (g.gram2Amount > 0) {
        numExtra += 1;
    }
    var reserve = execGasReserve(totalNfts + numExtra);
    // For <=100 assets there is no chain surcharge. Larger deals use the
    // batch chain:
    if (totalNfts > FAST_PATH_MAX_ASSETS) {
        // Additional chain transactions: ceil(n/K) batches of assets (the
        // first rides along in the last deposit's transaction, whose base is
        // already in execGasReserve) minus 1, PLUS a separate final
        // transaction — exactly ceil(n/K) surcharges in total.
        val batches = (totalNfts + BATCH_MAX_SENDS - 1) / BATCH_MAX_SENDS;
        // `batches` is a ceiling division: (n + K - 1) / K. Multiplying the batch
        // COUNT by the per-batch gas cost is the intended arithmetic — multiplying
        // before dividing would compute a different quantity entirely.
        // check-disable-next-line divide-before-multiply
        reserve += calculateGasFee(BASECHAIN, BATCH_EXTRA_GAS_UNITS * batches);
    }
    return reserve;
}

// The cost must be split by asset kind, not priced uniformly. Jetton assets
// are pricier to send than NFTs (JETTON_TRANSFER_VALUE = 0.05 against 0.03,
// because a jetton takes two hops: our wallet -> internal_transfer -> the
// recipient's wallet). Pricing every asset at the NFT rate makes
// `explicitOut`/`minBalanceForSwap` underestimate the real distribution cost,
// and a jetton deal then aborts its execution cascade with
// action_result_code=37 ("Not enough Toncoin") — pinned by the
// overpaymentOnFinalDepositStillExecutes test. For pure-NFT deals
// (jettonsCount == 0) this reduces to NFT_TRANSFER_VALUE * assetsCount.
fun Storage.assetTransferCost(self): coins {
    val jettons = self.jettonsCount as int;
    val nfts = (self.assetsCount as int) - jettons;
    return NFT_TRANSFER_VALUE * nfts + JETTON_TRANSFER_VALUE * jettons;
}

fun Storage.minBalanceForSwap(self, g: GramState): coins {
    return g.gram1Amount + g.gram2Amount + g.serviceFee1 + g.serviceFee2 +
    self.assetTransferCost() +
    self.gasReserveForSwap(g) +
    DUST;
}

// contract.getOriginalBalance() (common.tolk:363) — the contract's balance
// at the start of this transaction's Computation Phase, i.e. BEFORE this
// same transaction's gas is deducted — i.e. it includes the incoming
// message's attached value but not this message's own processing cost.
fun Storage.canAutoExecute(self, committedOut: coins): bool {
    if (self.phase != PHASE_ACTIVE) {
        return false;
    }
    if (self.received1Count < self.required1Count) {
        return false;
    }
    if (self.received2Count < self.required2Count) {
        return false;
    }
    val g = self.grams.load();
    if (g.gram1Received < g.gram1Amount) {
        return false;
    }
    if (g.gram2Received < g.gram2Amount) {
        return false;
    }
    if (g.serviceFee1 < SERVICE_FEE) {
        return false;
    }
    if (g.serviceFee2 < SERVICE_FEE) {
        return false;
    }
    return contract.getOriginalBalance() - committedOut >= self.minBalanceForSwap(g);
}

// ── Fast-path / batch-path gate ──
// Deals of up to FAST_PATH_MAX_ASSETS (100) assets are distributed in a
// single transaction (executeSwapSingleTx below). Larger deals switch to
// EXECUTING and are distributed in batches through the self-trigger chain.
fun Storage.executeSwap(mutate self, committedOut: coins) {
    if ((self.assetsCount as int) <= FAST_PATH_MAX_ASSETS) {
        // Small deal: the single-transaction path.
        self.executeSwapSingleTx(committedOut);
        return;
    }
    // Large deal: point of no return — EXECUTING, batches.
    self.phase = PHASE_EXECUTING;
    self.dist = DistState {
        mode: DIST_EXECUTE,
        cursor: 0,
        retryCount: 0,
        retry: [],
    }.toCell();
    self.runDistributionBatch(false);
}

// ── Recipient addressing and sending a single asset ──
// The recipient (dest) and responseDestination of an asset transfer, based
// on the delivery mode. The response rules:
// for a jetton, excesses go to the jetton recipient; for an NFT in execute,
// they go to the previous owner.
fun Storage.assetRecipient(self, a: Asset, mode: int): (address, address) {
    if (mode == DIST_EXECUTE) {
        val newOwner = a.ownerSide == 1 ? self.owner2 : self.owner1;
        val resp = a.kind == 1 ? newOwner : (a.ownerSide == 1 ? self.owner1 : self.owner2);
        return (newOwner, resp);
    }
    if (mode == DIST_COLLECT) {
        val supervisor = self.sup.load().supervisor;
        return (supervisor, supervisor);
    }
    // DIST_CANCEL / DIST_RETURN: to the depositor
    val backTo = a.ownerSide == 1 ? self.owner1 : self.owner2;
    return (backTo, backTo);
}

fun sendAsset(a: Asset, idx: int, dest: address, resp: address) {
    if (a.kind == 1) {
        sendJettonTransfer(
            a.jettonWallet!,
            idx,
            a.amount,
            dest,
            resp,
            JETTON_TRANSFER_VALUE,
            SEND_MODE_REGULAR,
        );
    } else {
        sendNftTransfer(
            a.addr,
            idx,
            dest,
            resp,
            NFT_TRANSFER_VALUE,
            SEND_MODE_REGULAR,
        );
    }
}

// ── One delivery batch ──
// Walks the registry with a cursor; redelivery from retry happens ONLY
// when drainRetry=true (kick). Progress is written with a SINGLE write to
// the dist cell. A batch transaction is atomic: if
// compute/action fails, the cursor does not move, no actions go out, and a
// kick resumes from the same point (double-send is ruled out).
//
// The automatic continue chain deliberately does NOT redeliver from retry.
// Doing so lets a permanently-bouncing asset — a recipient that systematically
// rejects the transfer — spin forever: a batch sends from retry (sends>0) ->
// continue -> the bounce puts it back in retry -> the next batch sends it
// again -> ... On a real network that unbounded chain burns the balance down
// to nothing; a test pins that it cannot happen. The model is instead
// "bounce -> the asset is delivered by the next KICK" — redelivery only
// happens on an explicit kick (drainRetry=true), and the auto-chain PARKS
// when retry is non-empty (see the completion rule below). A kick that
// redelivered at least one asset also parks (does not send continue): a
// repeat bounce needs time to arrive — otherwise finalization could outrun
// the bounce and strand the asset; the next kick either
// finalizes or redelivers again.
fun Storage.runDistributionBatch(mutate self, drainRetry: bool) {
    var d = self.dist.load();
    if (d.mode == DIST_IDLE) {
        return;
    }
    var sends = 0;
    var drained = 0;

    // 1) Redeliver bounced assets (kick ONLY): the entry is REMOVED from
    // retry BEFORE sending (idempotency); a repeat bounce will put it back.
    if (drainRetry) {
        var rr = d.retry.findFirst();
        while (
            rr.isFound && sends < BATCH_MAX_SENDS && getGasConsumedAtTheMoment() <
            BATCH_GAS_SOFT_CAP
        ) {
            val idx = rr.getKey();
            d.retry.delete(idx);
            d.retryCount -= 1;
            var a = self.assets.mustGet(idx);
            if (!a.abandoned) {
                // Redelivery clears the saturating bounces counter:
                // otherwise bounces>0 would stay set FOREVER even after a
                // successful redelivery, and the resend gate in force_deliver
                // would let through a resend of an asset that was already
                // delivered (a jetton double-send).
                // An asset that is genuinely still undelivered will come
                // back to retry via a new bounce (the counter increments
                // again). A per-asset set is a rare path (bounced assets
                // only), so the extra gas cost is acceptable here.
                if (a.bounces > 0) {
                    a.bounces = 0;
                    self.assets.set(idx, a);
                }
                val (dest, resp) = self.assetRecipient(a, d.mode as int);
                sendAsset(a, idx as int, dest, resp);
                sends += 1;
                drained += 1;
            }
            rr = d.retry.findFirst();
        }
    }

    // 2) Walk the registry with the cursor. eligible: received && !abandoned
    // — in DIST_EXECUTE, received is guaranteed true (canAutoExecute); in
    // cancel/collect/return it filters out assets never received; skips are
    // bounded by the gas soft cap.
    val n = self.assetsCount as int;
    while (
        (d.cursor as int) < n && sends < BATCH_MAX_SENDS && getGasConsumedAtTheMoment() <
        BATCH_GAS_SOFT_CAP
    ) {
        val a = self.assets.mustGet(d.cursor);
        if (a.received && !a.abandoned) {
            val (dest, resp) = self.assetRecipient(a, d.mode as int);
            sendAsset(a, d.cursor as int, dest, resp);
            sends += 1;
        }
        d.cursor += 1;
    }

    // FINALIZATION — ONLY AS A SEPARATE TRANSACTION WITH NO ASSET SENDS.
    // If THIS batch sent any assets (sends > 0), finalization is deferred with
    // one more ContinueDistribution —
    // otherwise the finalization refund formula would compute `available`
    // from getOriginalBalance() WITHOUT subtracting the value of assets sent
    // in this same transaction (up to 50×0.03/0.05), and the action phase
    // would fail with code=37 on almost every large deal. In a separate
    // finalization transaction, getOriginalBalance() already reflects all
    // transfers from previous batches, `available` is correct, and the
    // execGasReserve(numExtra) reserve is enough (finalization sends ≤6
    // messages). The last batch is exactly "GRAM exchange/fee/refund/DONE"
    // as its own batch (see finalizeDistribution below).
    // Completion rule:
    //   cursor<n                                   -> continue (cursor chain is still running);
    //   cursor>=n, retry empty, sends==0            -> FINALIZE;
    //   cursor>=n, retry empty, sends>0, drained==0 -> continue (finalize next tx);
    //   otherwise (retry non-empty OR redeliveries happened) -> PARK: send
    //     nothing, delivery waits for a kick ("delivered by the next kick").
    if ((d.cursor as int) >= n && d.retryCount == 0 && sends == 0) {
        self.finalizeDistribution(d.mode as int);
        d.mode = DIST_IDLE;
    } else if ((d.cursor as int) < n || (d.retryCount == 0 && drained == 0)) {
        val m = createMessage({
            bounce: true,
            value: CONTINUE_MSG_VALUE,
            dest: contract.getAddress(),
            body: ContinueDistribution { queryId: d.cursor as int },
        });
        m.send(SEND_MODE_REGULAR);
    }
    // else: parked — state saved, resumes on the next kick.
    //
    // Residual window: the bounce for the LAST cursor wave's transfer (or a
    // double-kick faster than bounce latency) can arrive after finalization
    // (mode==IDLE) — such a bounce is silently ignored by
    // onBouncedMessage, the asset physically stays with us, and is
    // collected via rescue (the documented exception to "every received
    // asset is delivered or returned"). A double
    // successful send is impossible in any case.
    self.dist = d.toCell();
}

// ── Delivery finalization ──
// Called ONLY from a batch that sent no assets (see runDistributionBatch,
// the sends == 0 gate): getOriginalBalance() here already reflects
// the spending of all previous batches, so the refund is honestly computed
// FROM THE CURRENT balance, and execGasReserve(numExtra) covers
// the actual finalization (≤6 messages). DIST_EXECUTE: GRAM exchange,
// fee, pro-rata refund, dust sweep, DONE. DIST_CANCEL: sweep only (the GRAM
// refunds already went out in the initiating transaction). DIST_COLLECT/
// DIST_RETURN: nothing — a return deliberately performs no sweep.
fun Storage.finalizeDistribution(mutate self, mode: int) {
    if (mode == DIST_EXECUTE) {
        self.phase = PHASE_DONE;
        val g = self.grams.load();
        val feeTotal = g.serviceFee1 + g.serviceFee2;
        val explicitOut = g.gram1Amount + g.gram2Amount + feeTotal;
        var numExtra = 3;
        if (g.gram1Amount > 0) {
            numExtra += 1;
        }
        if (g.gram2Amount > 0) {
            numExtra += 1;
        }
        var available = contract.getOriginalBalance() - explicitOut - execGasReserve(numExtra) -
        DUST;
        if (available < 0) {
            available = 0;
        }
        val contrib1 = g.gram1Received + g.gram1DepositReserve;
        val contrib2 = g.gram2Received + g.gram2DepositReserve;
        val totalContrib = contrib1 + contrib2;
        var refund1: coins = 0;
        var refund2: coins = 0;
        if (totalContrib > 0 && available > 0) {
            refund1 = available * contrib1 / totalContrib;
            refund2 = available - refund1; // strict pro-rata
        }
        if (g.gram2Amount > 0) {
            createMessage({ bounce: false, value: g.gram2Amount, dest: self.owner1 }).send(
                SEND_MODE_REGULAR,
            );
        }
        if (g.gram1Amount > 0) {
            createMessage({ bounce: false, value: g.gram1Amount, dest: self.owner2 }).send(
                SEND_MODE_REGULAR,
            );
        }
        if (feeTotal > 0) {
            createMessage({ bounce: false, value: feeTotal, dest: self.feeWallet }).send(
                SEND_MODE_REGULAR,
            );
        }
        if (refund1 > 0) {
            createMessage({ bounce: false, value: refund1, dest: self.owner1 }).send(
                SEND_MODE_REGULAR,
            );
        }
        if (refund2 > 0) {
            createMessage({ bounce: false, value: refund2, dest: self.owner2 }).send(
                SEND_MODE_REGULAR,
            );
        }
        // SAFETY: last statement of the DIST_EXECUTE branch (phase is already
        // PHASE_DONE and every computed payout above — gram legs, service
        // fee, pro-rata refunds — has been sent). What remains on the
        // balance is only the unused portion of the gas reserve, so
        // draining it here is the intended dust settlement to feeWallet.
        createMessage({ bounce: false, value: 0, dest: self.feeWallet }).send(
            SEND_MODE_CARRY_ALL_BALANCE,
        );
        return;
    }
    if (mode == DIST_CANCEL) {
        // SAFETY: DIST_CANCEL only reaches this branch to run the dust
        // sweep — GRAM-side refunds for a cancelled distribution were
        // already sent in the transaction that initiated the cancel, not
        // here. This call has no other obligation to fund, so handing the
        // whole remaining balance to feeWallet is correct.
        createMessage({ bounce: false, value: 0, dest: self.feeWallet }).send(
            SEND_MODE_CARRY_ALL_BALANCE,
        );
    }
}

// executeSwapSingleTx — distributes the whole deal in one transaction. The
// fast path (<=100 assets) calls it directly; larger deals use the batch path
// above.
fun Storage.executeSwapSingleTx(mutate self, committedOut: coins) {
    self.phase = PHASE_DONE;
    val g = self.grams.load();

    val feeTotal = g.serviceFee1 + g.serviceFee2;
    val explicitOut = g.gram1Amount + g.gram2Amount + self.assetTransferCost() + feeTotal;
    val gasReserve = self.gasReserveForSwap(g);

    var available = contract.getOriginalBalance() - committedOut - explicitOut - gasReserve - DUST;
    if (available < 0) {
        available = 0;
    }

    // Strict pro-rata: refund2 is the remainder of available, NOT a
    // second proportional computation (otherwise rounding could drift by 1
    // nanoton and "lose"/"create" TON relative to available).
    val contrib1 = g.gram1Received + g.gram1DepositReserve;
    val contrib2 = g.gram2Received + g.gram2DepositReserve;
    val totalContrib = contrib1 + contrib2;
    var refund1: coins = 0;
    var refund2: coins = 0;
    if (totalContrib > 0 && available > 0) {
        refund1 = available * contrib1 / totalContrib;
        refund2 = available - refund1;
    }

    // 1. GRAM exchange: each side receives the amount deposited by the
    // OPPOSITE side.
    if (g.gram2Amount > 0) {
        createMessage({ bounce: false, value: g.gram2Amount, dest: self.owner1 }).send(
            SEND_MODE_REGULAR,
        );
    }
    if (g.gram1Amount > 0) {
        createMessage({ bounce: false, value: g.gram1Amount, dest: self.owner2 }).send(
            SEND_MODE_REGULAR,
        );
    }

    // 2. NFT — each side gets the assets of the opposite side; queryId =
    // asset_index (map key) — prep for future bounce handling.
    //
    // CONSTRAINT: the distribution loop must stay READ-ONLY. Writing back per
    // asset — `a.sent = true; self.assets.set(idx, a)` — rebuilds O(log N)
    // dictionary cells on every iteration, around 9000 gas per NFT, and that
    // breaks the auto-cascade at as few as 61 total NFTs
    // (action_result_code=37).
    // The sent flags are only needed for batching; in this single-transaction
    // path, re-entry is already ruled out by `phase = DONE` (set BEFORE the
    // distribution — the transaction is atomic, so the distribution either
    // goes out in full or rolls back in full).
    // NOTE: the batching path does not restore them either — it tracks its
    // progress with `DistState.cursor` alone and never writes `sent`. The
    // field stays in the Asset layout as a reserved slot: removing it would
    // change the storage layout, and therefore every deal address.
    // The loop must also dispatch on `a.kind`. Without that branch, jetton
    // assets receive a TIP-4 `NftTransfer` addressed to the MINTER — for
    // kind=1, `a.addr` is the minter, not a wallet — and the action fails with
    // exit_code=63 ("prefix does not match"), since a minter does not
    // understand that opcode. Pinned by the
    // `overpaymentOnFinalDepositStillExecutes` test. Jetton assets go out via
    // sendJettonTransfer to the RESOLVED a.jettonWallet! (guaranteed
    // non-null: canAutoExecute requires received1Count/received2Count to be
    // met, and the per-asset jetton-receipt gate resolves the wallet before
    // marking received).
    //
    // CONSTRAINT: that branch must sit OUTSIDE the loop. The gas boundary here
    // is calibrated to the edge — gas_probe pins 115x115 OK against 116x116
    // FAIL — so the hot loop has no headroom for extra instructions. A single
    // additional `a.kind == 1` check per iteration is enough to push 115x115
    // and 230x1 into exit_code=-14.
    // So `self.jettonsCount == 0` is tested EXACTLY ONCE per transaction:
    // pure-NFT deals run the tight loop with no per-iteration dispatch, while
    // mixed and jetton deals take a separate loop that branches on kind. The
    // asymmetry is affordable because jetton deals are always small in asset
    // count — NFT_TRANSFER_VALUE against JETTON_TRANSFER_VALUE makes a
    // comparable volume uneconomical.
    if (self.jettonsCount == 0) {
        var r = self.assets.findFirst();
        while (r.isFound) {
            val idx = r.getKey();
            val a = r.loadValue();
            val newOwner = a.ownerSide == 1 ? self.owner2 : self.owner1;
            val resp = a.ownerSide == 1 ? self.owner1 : self.owner2;
            sendNftTransfer(
                a.addr,
                idx,
                newOwner,
                resp,
                NFT_TRANSFER_VALUE,
                SEND_MODE_REGULAR,
            );
            r = self.assets.iterateNext(r);
        }
    } else {
        var r = self.assets.findFirst();
        while (r.isFound) {
            val idx = r.getKey();
            val a = r.loadValue();
            val newOwner = a.ownerSide == 1 ? self.owner2 : self.owner1;
            val resp = a.ownerSide == 1 ? self.owner1 : self.owner2;
            if (a.kind == 1) {
                // responseDest = newOwner (not resp, unlike the NFT branch
                // below): TEP-74 excess-refund goes to the jetton recipient,
                // not the original depositor.
                sendJettonTransfer(
                    a.jettonWallet!,
                    idx,
                    a.amount,
                    newOwner,
                    newOwner,
                    JETTON_TRANSFER_VALUE,
                    SEND_MODE_REGULAR,
                );
            } else {
                sendNftTransfer(
                    a.addr,
                    idx,
                    newOwner,
                    resp,
                    NFT_TRANSFER_VALUE,
                    SEND_MODE_REGULAR,
                );
            }
            r = self.assets.iterateNext(r);
        }
    }

    // 3. Service fee — combined into a single transfer.
    if (feeTotal > 0) {
        createMessage({ bounce: false, value: feeTotal, dest: self.feeWallet }).send(
            SEND_MODE_REGULAR,
        );
    }

    // 4. Pro-rata refunds.
    if (refund1 > 0) {
        createMessage({ bounce: false, value: refund1, dest: self.owner1 }).send(SEND_MODE_REGULAR);
    }
    if (refund2 > 0) {
        createMessage({ bounce: false, value: refund2, dest: self.owner2 }).send(SEND_MODE_REGULAR);
    }

    // 5. Dust sweep — sent LAST: whatever is physically left on the balance
    // after all the messages above (rounding, leftovers) goes to feeWallet
    // via mode 128 (CARRY_ALL_BALANCE).
    // SAFETY: step 5 of 5 in this function — every asset/NFT/jetton
    // transfer, the service fee, and both pro-rata refunds (steps 1-4
    // above) have already been sent, and this is the function's final
    // statement. Only rounding leftovers remain on the balance, so
    // sweeping them to feeWallet here is safe.
    createMessage({ bounce: false, value: 0, dest: self.feeWallet }).send(
        SEND_MODE_CARRY_ALL_BALANCE,
    );
}

// Called after every deposit/service-fee, BEFORE save() in each handler
// (the ordering is already set — not rearranged here).
fun Storage.tryAutoExecute(mutate self, committedOut: coins) {
    if (self.canAutoExecute(committedOut)) {
        self.executeSwap(committedOut);
    }
}

// Fallback for a message with an empty body: from an owner it is treated as
// an ordinary GRAM deposit for that side; from anyone else it is forwarded to
// feeWallet, since there is no reason to hold a stranger's TON on the escrow's
// balance.
//
// Note for integrators: crediting an owner's bare transfer also calls
// st.tryAutoExecute(), so a plain TON transfer with no command can complete a
// deal — auto-execution is not limited to the text deposit commands. It runs
// behind the full canAutoExecute gate (the same phase/received/gram/fee/
// balance checks as everywhere else), but it is observable at the wire level
// and worth knowing about.
fun handlePlainTransfer(sender: address, value: coins) {
    var st = Storage.load();
    var g = st.grams.load();
    if (sender == st.owner1) {
        g.gram1Received += value;
    } else if (sender == st.owner2) {
        g.gram2Received += value;
    } else {
        // Funded by the incoming message's own value (mode 64), NOT from the
        // balance — the same idiom as returnForeignNft / returnJettons below.
        // Forwarding the full `value` under SEND_MODE_REGULAR would make every
        // stranger's transfer a net loss: the contract would hand on everything
        // it received while paying this transaction's compute gas out of its
        // own balance, so anyone could grind the escrow's reserve down —
        // below minBalanceForSwap (auto-execution stops firing) or below
        // cancel_swap's `required` (throw 430). Mode 64 carries what remains
        // of the inbound value after gas, leaving the balance untouched.
        val fwd = createMessage({
            bounce: false,
            value: 0,
            dest: st.feeWallet,
        });
        fwd.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        return;
    }
    st.grams = g.toCell();
    st.tryAutoExecute(0);
    st.save();
}

// The deploy command's value is deliberately NOT credited to the gram
// counters — it pays for the discovery sends below, not for a side's deposit.
// If the deal contains jettons, the contract deploys
// into SETUP — provide_wallet_address (TEP-89) is sent to every UNIQUE
// unresolved minter. A repeat deploy_fee while in SETUP is a legal manual
// retry (the minter didn't respond): it only sends provide to minters not
// yet resolved. The sender is deliberately not gated — instead, the caller
// supplies the value for the provide sends.
//
// That pairing is the point. Funding the provide sends from the CONTRACT'S
// BALANCE without checking the caller's value opens a griefing vector: with
// SETUP stuck because a minter stays silent, a third party can drain the
// owners' GRAM deposits toward that dead minter using cheap (~0.001 TON)
// deploy_fee calls, each costing the escrow ~0.08 TON at 100 positions, since
// every call re-sends the full distribution. So the caller pays, enforced by
// an assert BEFORE the distribution.
// perMinterProvideValue must match byte-for-byte
// the formula in tests/escrow_helpers.tolk:deployEscrow (the same
// PROVIDE_WALLET_VALUE + calculateGasFee(BASECHAIN,
// TAKE_WALLET_GAS_UNITS_PER_ASSET × assetsCount) — otherwise the deploy
// transaction, which already covers this same formula, would start failing
// this assert).
fun handleDeployFee(_sender: address, value: coins) {
    val st = Storage.load();
    assert (st.phase == PHASE_ACTIVE || st.phase == PHASE_SETUP) throw Errors.AlreadyFinalized;
    if (st.phase != PHASE_SETUP) {
        return; // NFT-only deal: no action needed
    }
    // O(n·log n) minter dedup over the jetton assets: a transaction-local map
    // of seen minters, NOT persisted in Storage — it lives only for the
    // duration of the call. The map is what keeps this sub-quadratic; deduping
    // by re-scanning all previous assets on every iteration walls a jetton
    // deal at 38-39 total assets, where the quadratic compute growth aborts
    // the deploy with action_result_code=37 ("Not enough Toncoin").
    val n = st.assetsCount as int;
    // A flat PROVIDE_WALLET_VALUE (0.02 TON) only covers the
    // TakeWalletAddress response while a minter owns a handful of assets.
    // handleTakeWalletAddress scans all n assets and calls `.set()` on EVERY
    // match — legitimate work, it resolves jettonWallet — so its cost grows
    // with how many assets belong to one minter. At total=100 with a single
    // minter this measures ~597,172 gas, while 0.02 TON buys only ~293,000:
    // the deploy cascade then dies with exit_code=-14 ("Out of gas") ON THE
    // MINTER'S RESPONSE, not in handleDeployFee itself. We add a gas reserve of
    // TAKE_WALLET_GAS_UNITS_PER_ASSET × n to each provide message (the same
    // units+calculateGasFee scheme, see storage.tolk) — covering the worst
    // case (the queried minter owns all n assets).
    val takeWalletReserve = calculateGasFee(BASECHAIN, TAKE_WALLET_GAS_UNITS_PER_ASSET * n);
    val perMinterProvideValue = PROVIDE_WALLET_VALUE + takeWalletReserve;
    // A SINGLE pass over the n assets (not two — DEPLOY_GAS_UNITS_PER_ASSET
    // is calibrated for one scan, see storage.tolk): minters are deduped as
    // before, but instead of sending immediately, the addresses of first
    // occurrences are collected into a separate map<index, address> — the
    // distribution happens in a SECOND, cheap pass AFTER the value gate,
    // over only the unique minters (usually far fewer than n), rather than
    // over all n assets again.
    var seen: map<address, bool> = [];
    var toNotify: map<uint16, address> = [];
    var unresolvedCount: int = 0;
    var i: int = 0;
    while (i < n) {
        val a = st.assets.mustGet(i as uint16);
        if (a.kind == 1 && a.jettonWallet == null) {
            val isFirst = seen.addIfNotExists(a.addr, true);
            if (isFirst) {
                toNotify.set(unresolvedCount as uint16, a.addr);
                unresolvedCount += 1;
            }
        }
        i += 1;
    }
    assert (value >= perMinterProvideValue * unresolvedCount) throw Errors.InsufficientBalance;
    var k: int = 0;
    while (k < unresolvedCount) {
        val dest = toNotify.mustGet(k as uint16);
        val m = createMessage({
            bounce: true,
            value: perMinterProvideValue,
            dest,
            body: ProvideWalletAddress {
                queryId: k,
                ownerAddress: contract.getAddress(),
                includeAddress: false,
            },
        });
        m.send(SEND_MODE_REGULAR);
        k += 1;
    }
}

// TEP-89 take_wallet_address: accepted ONLY from the address the request
// was sent to (sender == the minter of some jetton asset), written into ALL
// of that minter's assets (a minter can be on both sides), pendingWallets--.
// Idempotency: a repeat response from an already-resolved minter / a
// response from a non-minter / a response outside SETUP is silently
// ignored (not thrown: these are external messages, and failing them gains
// us nothing).
fun handleTakeWalletAddress(sender: address, _value: coins, msg: TakeWalletAddress) {
    var st = Storage.load();
    if (st.phase != PHASE_SETUP) {
        return;
    }
    var resolvedAny = false;
    val n = st.assetsCount as int;
    var i: int = 0;
    while (i < n) {
        var a = st.assets.mustGet(i as uint16);
        if (a.kind == 1 && a.addr == sender && a.jettonWallet == null) {
            a.jettonWallet = msg.walletAddress;
            st.assets.set(i as uint16, a);
            resolvedAny = true;
        }
        i += 1;
    }
    if (!resolvedAny) {
        return;
    }
    st.pendingWallets -= 1;
    if (st.pendingWallets == 0) {
        st.phase = PHASE_ACTIVE;
        // Defensive call: by the time the last minter resolves, all
        // NON-jetton deposits may already have arrived (NFT/GRAM are
        // accepted during SETUP). A jetton deposit for an unresolved minter
        // could not have arrived (per-asset gate), so right now the
        // condition is almost certainly false — but the call is cheap and
        // closes off future paths to ACTIVE.
        st.tryAutoExecute(0);
    }
    st.save();
}

fun handleDepositGram(sender: address, value: coins, side: int) {
    var st = Storage.load();
    assert (st.phase == PHASE_ACTIVE || st.phase == PHASE_SETUP) throw Errors.AlreadyFinalized;
    var g = st.grams.load();
    if (side == 1) {
        assert (sender == st.owner1) throw Errors.NotOwner1;
        g.gram1Received += value;
    } else {
        assert (sender == st.owner2) throw Errors.NotOwner2;
        g.gram2Received += value;
    }
    st.grams = g.toCell();
    st.tryAutoExecute(0);
    st.save();
}

fun handleServiceFee(sender: address, value: coins, side: int) {
    var st = Storage.load();
    assert (st.phase == PHASE_ACTIVE || st.phase == PHASE_SETUP) throw Errors.AlreadyFinalized;
    var g = st.grams.load();
    if (side == 1) {
        assert (sender == st.owner1) throw Errors.NotOwner1;
        g.serviceFee1 += value;
    } else {
        assert (sender == st.owner2) throw Errors.NotOwner2;
        g.serviceFee2 += value;
    }
    st.grams = g.toCell();
    st.tryAutoExecute(0);
    st.save();
}

// Manual execution trigger. Deliberately NO balance check: canAutoExecute
// checks the balance, manual execute does not; `available` inside
// executeSwap is simply clamped to 0 if the real balance isn't enough).
fun handleExecuteSwap(sender: address, _value: coins) {
    var st = Storage.load();
    assert (sender == st.owner1) throw Errors.NotOwner1;
    assert (st.phase == PHASE_ACTIVE) throw Errors.AlreadyFinalized;
    val g = st.grams.load();
    assert (g.gram1Received >= g.gram1Amount) throw Errors.NotEnoughTon1;
    assert (g.gram2Received >= g.gram2Amount) throw Errors.NotEnoughTon2;
    assert (g.serviceFee1 >= SERVICE_FEE) throw Errors.ServiceFee1;
    assert (g.serviceFee2 >= SERVICE_FEE) throw Errors.ServiceFee2;
    assert (st.received1Count >= st.required1Count) throw Errors.NftsNotReceived;
    assert (st.received2Count >= st.required2Count) throw Errors.NftsNotReceived;
    st.executeSwap(0);
    st.save();
}

// ── Self-trigger for the next batch ──
// ONLY from itself — no other sender should be able to drive the batch
// chain; any other sender gets 403; phase gate:
// delivery must be in progress (mode != IDLE — otherwise this is the tail
// of an already-finalized chain, and we stay silent).
fun handleContinueDistribution(sender: address) {
    assert (sender == contract.getAddress()) throw Errors.NotOwners;
    var st = Storage.load();
    val d = st.dist.load();
    if (d.mode == DIST_IDLE) {
        return; // tail of an already-finalized chain — silently
    }
    // The auto-chain does NOT redeliver from retry — only a kick does.
    st.runDistributionBatch(false);
    st.save();
}

// ── kick — safety valve for a stalled chain ──
// Restarts delivery from the current point, funded by the attached value.
// A text command rather than a dedicated binary opcode, so that it can be
// sent as a plain comment from any wallet. Idempotency is guaranteed by the
// cursor/retry state: if there is nothing left to deliver — finalization
// (cursor==n && retry==0 && sends==0), or 410 when mode==IDLE.
// The ONLY call into the engine with drainRetry=true: kick redelivers
// bounced assets; a kick that redelivered at least one parks (does not
// finalize or send continue) — a repeat bounce needs time to arrive; the
// next kick closes out delivery.
fun handleKick(sender: address, _value: coins) {
    var st = Storage.load();
    val sup = st.sup.load();
    assert (
        sender == st.owner1 || sender == st.owner2 || sender == sup.supervisor
    ) throw Errors.NotOwners;
    val d = st.dist.load();
    assert (d.mode != DIST_IDLE) throw Errors.AlreadyFinalized;
    st.runDistributionBatch(true);
    st.save();
}

// ── force_deliver — supervisor-triggered delivery of a stuck asset ──
// (the "permanently stuck asset" case): resends to the current
// mode's recipient; fallback=true marks it abandoned (the asset is
// excluded from waiting and collected later via rescue) and, if it was the
// last undelivered asset, finalizes delivery (DONE/sweep are not blocked
// forever by one broken recipient).
fun handleForceDeliver(sender: address, value: coins, msg: ForceDeliver) {
    var st = Storage.load();
    requireSupervisor(sender, st);
    var d = st.dist.load();
    assert (d.mode != DIST_IDLE) throw Errors.AlreadyFinalized;
    val idx = msg.assetIndex;
    // The asset must exist and already be past the cursor (otherwise the
    // regular batch will deliver it — nothing to force).
    assert ((idx as int) < (st.assetsCount as int)) throw Errors.BadAssetIndex;
    assert ((idx as int) < (d.cursor as int)) throw Errors.BadAssetIndex;
    var a = st.assets.mustGet(idx);
    val wasInRetry = d.retry.delete(idx);
    if (wasInRetry) {
        d.retryCount -= 1;
    }
    if (msg.fallback) {
        if (!a.abandoned) {
            a.abandoned = true;
            st.assets.set(idx, a); // rare path — extra per-asset gas cost is acceptable here
        }
        if ((d.cursor as int) >= (st.assetsCount as int) && d.retryCount == 0) {
            st.finalizeDistribution(d.mode as int);
            d.mode = DIST_IDLE;
        }
    } else {
        // Resend gate: the asset must be KNOWN to be undelivered —
        // membership in retry, or bounces > 0. Without this, the supervisor
        // could resend an asset that was already delivered or "in flight":
        // the NFT item would reject the transfer (the escrow is no longer
        // the owner) -> a spurious bounce -> the asset goes back into retry
        // -> retryCount never reaches zero -> finalization deadlocks. The
        // cursor-based model has no other signal for "undelivered," so this
        // check is required by that design.
        assert (wasInRetry || a.bounces > 0) throw Errors.BadAssetIndex;
        // The resend is funded by the attached value: the supervisor must
        // attach at least the transfer's cost (the margin principle).
        val need = a.kind == 1 ? JETTON_TRANSFER_VALUE : NFT_TRANSFER_VALUE;
        assert (value >= need) throw Errors.InsufficientBalance;
        // Resend also clears bounces (as the retry drain loop does): otherwise
        // bounces>0 would stay set forever after a successful resend, and a
        // SECOND force_deliver would pass the resend gate on an asset that was
        // already delivered (the same jetton double-send, a different
        // trigger). An asset that is genuinely still undelivered will
        // reopen the gate via a new bounce.
        if (a.bounces > 0) {
            a.bounces = 0;
            st.assets.set(idx, a);
        }
        val (dest, resp) = st.assetRecipient(a, d.mode as int);
        sendAsset(a, idx as int, dest, resp);
    }
    st.dist = d.toCell();
    st.save();
}

// The only handler with an explicit balance check (throw 430). That check is
// what makes cancel all-or-nothing: it must either fully succeed — every
// refund and NFT return sent — or fully roll back, never leaving the deal
// CANCELLED without the balance to cover what it owes.
fun handleCancelSwap(sender: address, _value: coins) {
    var st = Storage.load();
    assert (sender == st.owner1 || sender == st.owner2) throw Errors.NotOwners;
    assert (st.phase == PHASE_ACTIVE || st.phase == PHASE_SETUP) throw Errors.AlreadyFinalized;

    val g = st.grams.load();
    // Return cost: NFT at 0.03, jettons at 0.05 — the received sub-type
    // counters are maintained incrementally (receivedJettonsN), no map scan
    // needed.
    val jet1On = st.receivedJettons1 as int;
    val jet2On = st.receivedJettons2 as int;
    val nfts1On = (st.received1Count as int) - jet1On;
    val nfts2On = (st.received2Count as int) - jet2On;
    val return1Cost = NFT_TRANSFER_VALUE * nfts1On + JETTON_TRANSFER_VALUE * jet1On;
    val return2Cost = NFT_TRANSFER_VALUE * nfts2On + JETTON_TRANSFER_VALUE * jet2On;

    var refund1 = g.gram1Received + g.serviceFee1;
    val reserve1Rem = g.gram1DepositReserve - return1Cost;
    if (reserve1Rem > 0) {
        refund1 += reserve1Rem;
    }
    var refund2 = g.gram2Received + g.serviceFee2;
    val reserve2Rem = g.gram2DepositReserve - return2Cost;
    if (reserve2Rem > 0) {
        refund2 += reserve2Rem;
    }

    // Balance check: the sum of all mandatory outgoing amounts (asset
    // returns + the distribution gas reserve + both refunds) must not
    // exceed the contract's real balance at transaction entry.
    val receivedTotal = (st.received1Count as int) + (st.received2Count as int);
    val registrySize = st.assetsCount as int;
    val sendCount = receivedTotal + 3;
    // The batch surcharge is INSIDE the asserted `required`: otherwise
    // a long cancel chain would come up short on gas for its trailing
    // batches. It is gated on the REGISTRY SIZE, not on sendCount and not on
    // receivedTotal: the chain's length is set by how far the cursor has to
    // walk (every registry entry is visited, received or not), while the +3
    // (feeWallet+refund1+refund2) are not part of the chain at all — refunds
    // go out in the initiating tx and the DIST_CANCEL finale only sweeps.
    // Using sendCount instead would, right at receivedTotal==100 (the
    // production cap 50×50), make sendCount==103 add the surcharge to a
    // SINGLE-transaction fast-path cancel, inflating `required` and risking
    // rejection of a valid cancel.
    // For a registry of <=100, batchExtraReserve == 0 — the fast-path formula
    // is byte-for-byte unchanged.
    val fwdReserve = execGasReserve(sendCount) + batchExtraReserve(registrySize);
    var required = return1Cost + return2Cost + fwdReserve;
    if (refund1 > 0) {
        required += refund1;
    }
    if (refund2 > 0) {
        required += refund2;
    }
    assert (contract.getOriginalBalance() >= required) throw Errors.InsufficientBalance;

    st.phase = PHASE_CANCELLED;

    // GRAM refunds go out IMMEDIATELY, in the initiating transaction (both
    // branches): their amount is accounted for in `required`, and the batch
    // finale (DIST_CANCEL) only sends the sweep.
    if (refund1 > 0) {
        createMessage({ bounce: false, value: refund1, dest: st.owner1 }).send(SEND_MODE_REGULAR);
    }
    if (refund2 > 0) {
        createMessage({ bounce: false, value: refund2, dest: st.owner2 }).send(SEND_MODE_REGULAR);
    }

    // The gate is the REGISTRY SIZE, not the number of received assets: the
    // loop below walks every registry entry, so its cost is driven by
    // assetsCount. Gating on receivedTotal sent a large-registry deal with
    // few deposits down the single-transaction path and exhausted the
    // 1,000,000-gas ceiling, leaving the deal impossible to cancel — the
    // state a deal is in BEFORE deposits arrive, i.e. exactly when a party
    // is most likely to cancel. Storage.executeSwap has always gated on
    // assetsCount; these handlers now match it.
    if (registrySize <= FAST_PATH_MAX_ASSETS) {
        // Fast path (<=100): single-transaction return + sweep.
        //
        // Returns only the assets actually received — to their own
        // depositors. The loop must stay read-only (no per-asset
        // `sent=true` + assets.set) for the gas reason described at
        // executeSwap; re-entry is ruled out by phase=CANCELLED.
        //
        // `a.jettonWallet!` is safe: received == true is only possible
        // after the minter is resolved (the per-asset jetton-receipt gate
        // in handleJettonNotification resolves the wallet before marking
        // received) — same pattern as in executeSwap.
        var r = st.assets.findFirst();
        while (r.isFound) {
            val idx = r.getKey();
            val a = r.loadValue();
            if (a.received) {
                val backTo = a.ownerSide == 1 ? st.owner1 : st.owner2;
                if (a.kind == 1) {
                    sendJettonTransfer(
                        a.jettonWallet!,
                        idx,
                        a.amount,
                        backTo,
                        backTo,
                        JETTON_TRANSFER_VALUE,
                        SEND_MODE_REGULAR,
                    );
                } else {
                    sendNftTransfer(
                        a.addr,
                        idx,
                        backTo,
                        backTo,
                        NFT_TRANSFER_VALUE,
                        SEND_MODE_REGULAR,
                    );
                }
            }
            r = st.assets.iterateNext(r);
        }

        // The remainder goes to fee_wallet, sent LAST.
        // SAFETY: fast-path cancel — GRAM refunds were already sent above
        // (see the refund1/refund2 blocks before this loop) and every
        // received asset has just been returned to its original
        // depositor. This is the function's last statement before
        // st.save(). The leftover gas reserve goes to feeWallet rather than
        // being split back to depositors — deliberate, and the reason cancel
        // sweeps while emergency_return does not.
        createMessage({ bounce: false, value: 0, dest: st.feeWallet }).send(
            SEND_MODE_CARRY_ALL_BALANCE,
        );
        st.save();
        return;
    }

    // Batch return (>100): GRAM refunds already sent above; assets go out
    // in batches through the engine; the sweep happens in the final batch
    // (finalizeDistribution DIST_CANCEL, mode 128). Auto-chain
    // (drainRetry=false): retry only via kick. We do NOT send a sweep in
    // the initiating transaction.
    st.dist = DistState {
        mode: DIST_CANCEL,
        cursor: 0,
        retryCount: 0,
        retry: [],
    }.toCell();
    st.runDistributionBatch(false);
    st.save();
}

// Supervisor emergency operations.
// A shared gate for all 5 entry points: sender must match sup.supervisor,
// or throw 404 — before any other checks/state mutations.
fun requireSupervisor(sender: address, st: Storage): SupervisorState {
    val sup = st.sup.load();
    assert (sender == sup.supervisor) throw Errors.NotSupervisor;
    return sup;
}

// emergency_collect_assets — finalizes WITHOUT returning assets to
// the owners: all deal assets already received (assets[].received) go to
// the supervisor, and THEN the isolated rescue registry (sup.rescueAssets,
// populated by handleSupervisorAssetReceived) also goes to the supervisor,
// in the same call. The two sets are physically different NFTs (deal
// assets vs. unrelated rescue NFTs), but this handler sweeps both — unlike
// emergency_return (below), which only touches deal assets.
fun handleEmergencyCollect(sender: address, _value: coins) {
    var st = Storage.load();
    val sup = requireSupervisor(sender, st);
    assert (st.phase == PHASE_ACTIVE || st.phase == PHASE_SETUP) throw Errors.AlreadyFinalized;
    st.phase = PHASE_CANCELLED;

    // Gated on the REGISTRY SIZE, not on the number of received assets — the
    // loop below visits every registry entry. See handleCancelSwap for why.
    if ((st.assetsCount as int) <= FAST_PATH_MAX_ASSETS) {
        // Fast path (<=100): the previous single-transaction collection of deal
        // assets to the supervisor, byte-for-byte.
        // The loop must stay read-only (no per-asset `sent=true` +
        // assets.set) for the gas reason described at executeSwap;
        // re-entry is ruled out by phase=CANCELLED.
        var r = st.assets.findFirst();
        while (r.isFound) {
            val idx = r.getKey();
            val a = r.loadValue();
            if (a.received) {
                if (a.kind == 1) {
                    sendJettonTransfer(
                        a.jettonWallet!,
                        idx,
                        a.amount,
                        sup.supervisor,
                        sup.supervisor,
                        JETTON_TRANSFER_VALUE,
                        SEND_MODE_REGULAR,
                    );
                } else {
                    sendNftTransfer(
                        a.addr,
                        idx,
                        sup.supervisor,
                        sup.supervisor,
                        NFT_TRANSFER_VALUE,
                        SEND_MODE_REGULAR,
                    );
                }
            }
            r = st.assets.iterateNext(r);
        }
    } else {
        // Batch collection (>100): deal assets go to the supervisor in batches
        // through the engine (DIST_COLLECT). No sweep at finalization
        // (finalizeDistribution DIST_COLLECT sends nothing).
        // The rescue registry is swept BELOW, in this same initiating
        // transaction (it's small and not part of the deal's registry).
        st.dist = DistState {
            mode: DIST_COLLECT,
            cursor: 0,
            retryCount: 0,
            retry: [],
        }.toCell();
        st.runDistributionBatch(false);
    }

    // The rescue registry (rescueAssets) — NFT semantics unchanged: this
    // isolated registry is only populated by handleSupervisorAssetReceived
    // (NFT); jettons never land there (for those, use handleRescueJetton,
    // a one-off, outside this registry).
    var rr = sup.rescueAssets.findFirst();
    while (rr.isFound) {
        sendNftTransfer(
            rr.loadValue(),
            QUERY_ID_RESCUE_REGISTRY,
            sup.supervisor,
            sup.supervisor,
            NFT_TRANSFER_VALUE,
            SEND_MODE_REGULAR,
        );
        rr = sup.rescueAssets.iterateNext(rr);
    }
    st.save();
}

// emergency_return_assets — the same finalizing phase transition
// (CANCELLED), but the assets and refunds go to the CONTRIBUTORS (their own
// owners), as in handleCancelSwap. Two deliberate divergences from cancel:
//   - no balance check (`contract.getOriginalBalance() >= required`) — the
//     supervisor supplies the distribution gas themselves, at their own
//     responsibility;
//   - no sweep of the remainder to feeWallet via mode 128 — emergency_return
//     never touches feeWallet.
// Only affects st.assets (deal assets); rescueAssets is NOT touched — that
// isolated registry is only swept via emergency_collect.
fun handleEmergencyReturn(sender: address, _value: coins) {
    var st = Storage.load();
    requireSupervisor(sender, st);
    assert (st.phase == PHASE_ACTIVE || st.phase == PHASE_SETUP) throw Errors.AlreadyFinalized;
    st.phase = PHASE_CANCELLED;

    val g = st.grams.load();
    // Return cost: NFT at 0.03, jettons at 0.05 — same formula as handleCancelSwap.
    val jet1On = st.receivedJettons1 as int;
    val jet2On = st.receivedJettons2 as int;
    val nfts1On = (st.received1Count as int) - jet1On;
    val nfts2On = (st.received2Count as int) - jet2On;
    val return1Cost = NFT_TRANSFER_VALUE * nfts1On + JETTON_TRANSFER_VALUE * jet1On;
    val return2Cost = NFT_TRANSFER_VALUE * nfts2On + JETTON_TRANSFER_VALUE * jet2On;

    var refund1 = g.gram1Received + g.serviceFee1;
    val rem1 = g.gram1DepositReserve - return1Cost;
    if (rem1 > 0) {
        refund1 += rem1;
    }
    if (refund1 > 0) {
        createMessage({ bounce: false, value: refund1, dest: st.owner1 }).send(SEND_MODE_REGULAR);
    }

    var refund2 = g.gram2Received + g.serviceFee2;
    val rem2 = g.gram2DepositReserve - return2Cost;
    if (rem2 > 0) {
        refund2 += rem2;
    }
    if (refund2 > 0) {
        createMessage({ bounce: false, value: refund2, dest: st.owner2 }).send(SEND_MODE_REGULAR);
    }

    // Gated on the REGISTRY SIZE, not on the number of received assets — the
    // loop below visits every registry entry. See handleCancelSwap for why.
    if ((st.assetsCount as int) <= FAST_PATH_MAX_ASSETS) {
        // Fast path (<=100): the previous single-transaction return to
        // depositors, byte-for-byte.
        // The loop must stay read-only (no per-asset `sent=true` +
        // assets.set) for the gas reason described at executeSwap;
        // re-entry is ruled out by phase=CANCELLED.
        var r = st.assets.findFirst();
        while (r.isFound) {
            val idx = r.getKey();
            val a = r.loadValue();
            if (a.received) {
                val backTo = a.ownerSide == 1 ? st.owner1 : st.owner2;
                if (a.kind == 1) {
                    sendJettonTransfer(
                        a.jettonWallet!,
                        idx,
                        a.amount,
                        backTo,
                        backTo,
                        JETTON_TRANSFER_VALUE,
                        SEND_MODE_REGULAR,
                    );
                } else {
                    sendNftTransfer(
                        a.addr,
                        idx,
                        backTo,
                        backTo,
                        NFT_TRANSFER_VALUE,
                        SEND_MODE_REGULAR,
                    );
                }
            }
            r = st.assets.iterateNext(r);
        }
        st.save();
        return;
    }

    // Batch return (>100): GRAM refunds already sent above; assets go out
    // to depositors in batches through the engine (DIST_RETURN).
    // Finalization has NO sweep — finalizeDistribution DIST_RETURN sends
    // nothing, because a return never touches feeWallet. No balance check
    // either: the gas is the supervisor's to supply.
    st.dist = DistState {
        mode: DIST_RETURN,
        cursor: 0,
        retryCount: 0,
        retry: [],
    }.toCell();
    st.runDistributionBatch(false);
    st.save();
}

// emergency_withdraw_ton — NO phase gate, deliberately: it works even after
// DONE/CANCELLED, when the deal is already finished but TON could still be
// sitting on the balance from rounding or undelivered messages.
// No state mutation and no st.save() — this is a pure balance sweep, and
// the supervisor supplies their own gas to process this transaction.
fun handleEmergencyWithdraw(sender: address, _value: coins) {
    val st = Storage.load();
    val sup = requireSupervisor(sender, st);
    // SAFETY: this is the entire function body — requireSupervisor above
    // has already asserted the sender is the configured supervisor, and
    // there is no other state to protect (no phase gate, no st.save()).
    // Emergency withdrawal is defined as a full balance sweep to the
    // supervisor by design, so CARRY_ALL_BALANCE is the correct mode here.
    createMessage({ bounce: false, value: 0, dest: sup.supervisor }).send(
        SEND_MODE_CARRY_ALL_BALANCE,
    );
}

// Outgoing TIP-4 transfer, reused by execute/cancel/rescue — all of them
// send NFTs onward through this same body builder.
fun sendNftTransfer(
    nft: address,
    queryId: int,
    newOwner: address,
    responseDest: address,
    value: coins,
    mode: int,
) {
    val m = createMessage({
        bounce: true,
        value,
        dest: nft,
        body: NftTransfer {
            queryId,
            newOwner,
            responseDestination: responseDest,
            customPayload: null,
            forwardAmount: 0,
            forwardPayload: zeroBitSlice(),
        },
    });
    m.send(mode);
}

// Auto-return of a foreign, duplicate or late NFT, so that it does not simply
// sit on the escrow's balance. NEVER throw in any case — the
// incoming transaction must stay successful, or the NFT master would see a
// failed tx on OwnershipAssigned, which looks like a bug.
fun returnForeignNft(nft: address, to: address, incomingValue: coins) {
    if (incomingValue < RETURN_TRANSFER_VALUE) {
        return; // underpaid gas — the NFT stays with the escrow, for supervisor rescue
    }
    // mode 64 (CARRY_ALL_REMAINING_MESSAGE_VALUE): the return is funded by
    // the value attached to THIS incoming message, not by the contract's balance.
    val m = createMessage({
        bounce: false,
        value: 0,
        dest: nft,
        body: NftTransfer {
            queryId: 0,
            newOwner: to,
            responseDestination: to,
            customPayload: null,
            forwardAmount: 0,
            forwardPayload: zeroBitSlice(),
        },
    });
    m.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

// Outgoing TEP-74 transfer from OUR jetton wallet. Reused by: distribution,
// returns (returnJettons below), cancel/emergency/rescue.
// forwardTonAmount = 0 — no recipient notification, matching how NFTs are
// distributed; leftover gas from the transfer comes back to responseDest
// as excesses.
fun sendJettonTransfer(
    wallet: address,
    queryId: int,
    amount: coins,
    dest: address,
    responseDest: address,
    value: coins,
    mode: int,
) {
    val m = createMessage({
        bounce: true,
        value,
        dest: wallet,
        body: JettonTransfer {
            queryId,
            amount,
            destination: dest,
            responseDestination: responseDest,
            customPayload: null,
            forwardTonAmount: 0,
            forwardPayload: zeroBitSlice(),
        },
    });
    m.send(mode);
}

// Auto-return of jettons (underpaid/duplicate/foreign/late) — mirrors
// returnForeignNft. NO throw at all. The return is a
// reverse transfer through sender() (our wallet); a fake notification from
// a foreign address gets a transfer message back that does nothing there.
// bounce: false so the reply to the fake does not bounce back to us.
fun returnJettons(ourWallet: address, to: address, amount: coins, incomingValue: coins) {
    if (incomingValue < RETURN_TRANSFER_VALUE) {
        return; // underpaid gas — the tokens stay in the wallet, for supervisor rescue
    }
    val m = createMessage({
        bounce: false,
        value: 0,
        dest: ourWallet,
        body: JettonTransfer {
            queryId: 0,
            amount,
            destination: to,
            responseDestination: to,
            customPayload: null,
            forwardTonAmount: 0,
            forwardPayload: zeroBitSlice(),
        },
    });
    m.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

// Hint from forward_payload: either bit 0 + uint16.
// Anything else (ref-payload, shorter than 17 bits) means "no hint" -> -1.
fun parseAssetIndexHint(payload: slice): int {
    if (payload.remainingBitsCount() < 17) {
        return -1;
    }
    val isRef = payload.loadBool();
    if (isRef) {
        return -1;
    }
    return payload.loadUint(16);
}

// Verifies the registry entry against the actual sender (the
// index is a hint that requires verification; the pair (our wallet,
// depositor) is used because one minter can be on both sides of the deal).
fun Storage.jettonAssetMatches(self, a: Asset, ourWallet: address, depositor: address): bool {
    if (a.kind != 1 || a.received) {
        return false;
    }
    if (a.jettonWallet == null) {
        return false; // per-asset gate: the minter is not resolved yet
    }
    if (a.jettonWallet! != ourWallet) {
        return false;
    }
    val sideOwner = a.ownerSide == 1 ? self.owner1 : self.owner2;
    return sideOwner == depositor;
}

// Asset lookup: hint first (O(1) after bounds checking; does NOT verify
// the amount — the hint explicitly addresses a slot, and
// underpayment/overpayment are handled further up the call stack).
// Fallback runs in TWO passes: (1) exact amount match — otherwise, with
// several assets from the same minter on ONE side at different amounts, a
// deposit would match the first slot by key order and a legitimate
// transfer would be rejected as "underpayment"; (2) any match on the
// (wallet, depositor) pair. -1 = not found.
fun Storage.matchJettonAsset(
    self,
    ourWallet: address,
    depositor: address,
    hintIdx: int,
    amount: coins,
): int {
    val n = self.assetsCount as int;
    if (hintIdx >= 0 && hintIdx < n) {
        val a = self.assets.mustGet(hintIdx as uint16);
        if (self.jettonAssetMatches(a, ourWallet, depositor)) {
            return hintIdx;
        }
    }
    var i: int = 0;
    while (i < n) {
        if (i != hintIdx) {
            val a = self.assets.mustGet(i as uint16);
            if (self.jettonAssetMatches(a, ourWallet, depositor) && a.amount == amount) {
                return i;
            }
        }
        i += 1;
    }
    i = 0;
    while (i < n) {
        if (i != hintIdx) {
            val a = self.assets.mustGet(i as uint16);
            if (self.jettonAssetMatches(a, ourWallet, depositor)) {
                return i;
            }
        }
        i += 1;
    }
    return -1;
}

// Jetton receipt (the "receipt rules", items 2-4). WITHOUT A SINGLE throw.
fun handleJettonNotification(sender: address, value: coins, msg: JettonTransferNotification) {
    var st = Storage.load();

    // terminal phases (DONE/CANCELLED/EXECUTING) -> a late transfer, return it
    if (st.phase != PHASE_ACTIVE && st.phase != PHASE_SETUP) {
        returnJettons(sender, msg.sender, msg.amount, value);
        return;
    }

    val payload = msg.forwardPayload;
    val idx = st.matchJettonAsset(sender, msg.sender, parseAssetIndexHint(payload), msg.amount);
    if (idx < 0) {
        // foreign jetton / fake notification / duplicate / wallet not resolved yet
        returnJettons(sender, msg.sender, msg.amount, value);
        return;
    }
    var asset = st.assets.mustGet(idx as uint16);

    if (msg.amount < asset.amount) {
        // underpayment: topping up in parts is not supported — return it in full
        returnJettons(sender, msg.sender, msg.amount, value);
        return;
    }

    var reserveCredit = value;
    var committedOut: coins = 0; // value already queued for send by this transaction
    if (msg.amount > asset.amount) {
        // overpayment: return the excess in the same transaction if the value
        // covers it; otherwise the excess stays in our wallet and goes to
        // supervisor-rescue
        if (value >= RETURN_TRANSFER_VALUE) {
            // queryId MUST be a non-asset sentinel, not 0: sendJettonTransfer
            // builds the message with bounce: true, and a bounce of this
            // refund carrying queryId 0 would be read by onBouncedMessage as
            // a bounce of asset index 0 — inflating retryCount (which blocks
            // finalization until a kick) and opening the resend gate in
            // force_deliver for an asset that may already be delivered.
            sendJettonTransfer(
                sender,
                QUERY_ID_NON_ASSET,
                msg.amount - asset.amount,
                msg.sender,
                msg.sender,
                RETURN_TRANSFER_VALUE,
                SEND_MODE_REGULAR,
            );
            reserveCredit = value - RETURN_TRANSFER_VALUE;
            committedOut = RETURN_TRANSFER_VALUE; // the auto-execution formulas must subtract this
        }
    }

    asset.received = true;
    st.assets.set(idx as uint16, asset);

    var g = st.grams.load();
    if (asset.ownerSide == 1) {
        st.received1Count += 1;
        st.receivedJettons1 += 1;
        g.gram1DepositReserve += reserveCredit;
    } else {
        st.received2Count += 1;
        st.receivedJettons2 += 1;
        g.gram2DepositReserve += reserveCredit;
    }
    st.grams = g.toCell();

    st.tryAutoExecute(committedOut);
    st.save();
}

fun handleNftReceived(sender: address, value: coins, msg: OwnershipAssigned) {
    var st = Storage.load();
    val nft = sender;

    // Accepted only in SETUP/ACTIVE; in DONE/CANCELLED/EXECUTING — return to sender
    if (st.phase != PHASE_ACTIVE && st.phase != PHASE_SETUP) {
        returnForeignNft(nft, msg.previousOwner, value);
        return;
    }

    var foundIdx = -1;
    var asset: Asset = Asset {
        kind: 0,
        ownerSide: 0,
        addr: nft,
        jettonWallet: null,
        amount: 0,
        received: false,
        sent: false,
        bounces: 0,
        abandoned: false,
    };

    // O(1) hint for NFT receipt: the frontend puts asset_index in the
    // deposit's forward_payload (the same either-0 + uint16 format as the
    // jetton hint; the mock/real item passes the
    // payload straight through in OwnershipAssigned). THE INDEX IS ONLY A
    // HINT, NOT A SOURCE OF TRUTH: after the lookup, a mandatory
    // CHECK verifies assets[hint].addr == nft (the NFT item's address = the
    // actual sender). There is no way to forge the index to sneak in the
    // wrong/a foreign NFT — the address check catches the substitution, and
    // the path falls through to the linear fallback below, then to
    // auto-return. The hint only replaces an O(N) scan with an O(1) lookup,
    // removing the deposit ceiling (~850 -> no ceiling).
    val hintIdx = parseAssetIndexHint(msg.forwardPayload);
    if (hintIdx >= 0 && hintIdx < (st.assetsCount as int)) {
        val a = st.assets.mustGet(hintIdx as uint16);
        if (a.kind == 0 && !a.received && a.addr == nft) {
            foundIdx = hintIdx;
            asset = a;
        }
    }

    // Fallback: no hint / malformed / address mismatch -> linear search
    // The asset is captured directly during the scan, so there is no repeat
    // dictionary lookup (`mustGet`) after the loop.
    if (foundIdx < 0) {
        var r = st.assets.findFirst();
        while (r.isFound && foundIdx < 0) {
            val a = r.loadValue();
            if (a.kind == 0 && a.addr == nft) {
                foundIdx = r.getKey();
                asset = a;
            }
            r = st.assets.iterateNext(r);
        }
    }

    if (foundIdx < 0) {
        // not from the deal's registry (a foreign NFT) -> auto-return
        returnForeignNft(nft, msg.previousOwner, value);
        return;
    }

    if (asset.received) {
        // duplicate (the NFT came back to the escrow again) -> return
        returnForeignNft(nft, msg.previousOwner, value);
        return;
    }

    asset.received = true;
    st.assets.set(foundIdx as uint16, asset);

    var g = st.grams.load();
    if (asset.ownerSide == 1) {
        st.received1Count += 1;
        g.gram1DepositReserve += value;
    } else {
        st.received2Count += 1;
        g.gram2DepositReserve += value;
    }
    st.grams = g.toCell();

    st.tryAutoExecute(0);
    st.save();
}

// Registers a foreign/stuck NFT in the ISOLATED rescue registry
// (sup.rescueAssets), unrelated to deal assets (st.assets). This registry
// is later swept only via handleEmergencyCollect.
fun handleSupervisorAssetReceived(sender: address, _value: coins, msg: SupervisorAssetReceived) {
    var st = Storage.load();
    var sup = requireSupervisor(sender, st);
    sup.rescueAssets.set(sup.rescueCount, msg.assetAddr);
    sup.rescueCount += 1;
    st.sup = sup.toCell();
    st.save();
}

// A one-off rescue of a single specific NFT (not necessarily from the
// registry above — the supervisor can point at any stuck address
// directly). No phase gate and no state mutation — just a forward.
fun handleRescueNft(sender: address, _value: coins, msg: RescueNft) {
    val st = Storage.load();
    val sup = requireSupervisor(sender, st);
    sendNftTransfer(
        msg.nftAddr,
        QUERY_ID_NON_ASSET,
        sup.supervisor,
        sup.supervisor,
        NFT_TRANSFER_VALUE,
        SEND_MODE_REGULAR,
    );
}

// Same semantics as RescueNft, but for jettons: a one-off rescue of
// leftovers from OUR jetton wallet (overpayment excess, jettons stranded
// after an undetectable second-hop failure, or `abandoned` assets). The
// escrow does not know its own wallet's balance — the supervisor supplies
// the amount. No phase gate and no state mutation.
// queryId is the reserved non-asset sentinel (see storage.tolk).
fun handleRescueJetton(sender: address, _value: coins, msg: RescueJetton) {
    val st = Storage.load();
    val sup = requireSupervisor(sender, st);
    sendJettonTransfer(
        msg.jettonWallet,
        QUERY_ID_NON_ASSET,
        msg.amount,
        sup.supervisor,
        sup.supervisor,
        JETTON_TRANSFER_VALUE,
        SEND_MODE_REGULAR,
    );
}

// Bounce handling for outgoing distribution transfers.
// bounce-body = 0xFFFFFFFF + the first 256 bits of the original
// body (docs.ton.org, internal messages) — op(32) + queryId(64) are always
// available; the queryId of outgoing transfers = asset_index.
fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();
    if (in.bouncedBody.remainingBitsCount() < 96) {
        return;
    }
    val op = in.bouncedBody.loadUint(32);
    if (op == 0x6d5f0004) {
        return; // ContinueDistribution failed (out of gas, etc.) — recovered via kick
    }
    if (op != 0x5fcc3d14 && op != 0x0f8a7ea5) {
        return; // not NftTransfer and not JettonTransfer — this bounce is not our concern
    }
    val queryId = in.bouncedBody.loadUint(64);
    if (queryId >= QUERY_ID_NON_ASSET) {
        return; // reserved sentinels — outside the deal's registry
    }
    var st = Storage.load();
    if ((queryId as int) >= (st.assetsCount as int)) {
        return;
    }
    var d = st.dist.load();
    if (d.mode == DIST_IDLE) {
        // fast-path distribution, or a bounce after finalization: the transfer
        // did NOT go through, the asset physically stays with us (an NFT
        // stays owned by the escrow, jettons stay in our wallet) ->
        // supervisor-rescue (rescue_nft/rescue_jetton). The documented
        // exception to "every received asset is delivered or returned".
        return;
    }
    val idx = queryId as uint16;
    var a = st.assets.mustGet(idx);
    if (a.bounces < 15) {
        a.bounces += 1; // saturating counter — no uint4 overflow
    }
    st.assets.set(idx, a); // rare path — extra per-asset gas cost is acceptable here
    if (!a.abandoned) {
        val isNew = d.retry.addIfNotExists(idx, true);
        if (isNew) {
            d.retryCount += 1;
        }
    }
    st.dist = d.toCell();
    st.save();
}

// The straightforward approach would call
// `lazy Storage.fromCell(contract.getData())` directly, bypassing the
// Storage.load() wrapper, since `lazy` is compiler magic for
// T.fromCell/fromSlice and does not apply through a user-defined wrapper
// function. In practice, `lazy Storage.load()` also deserializes lazily, so
// we keep a single consistent style for accessing storage through
// Storage.load()/save().
get fun phase(): int {
    val st = lazy Storage.load();
    return st.phase;
}

get fun swapId(): int {
    val st = lazy Storage.load();
    return st.swapId;
}

get fun canAutoExecuteNow(): bool {
    val st = lazy Storage.load();
    return st.canAutoExecute(0);
}

get fun receivedCounts(): (int, int) {
    val st = lazy Storage.load();
    return (st.received1Count, st.received2Count);
}

get fun gramState(): GramState {
    val st = lazy Storage.load();
    return st.grams.load();
}

get fun pendingWalletsLeft(): int {
    val st = lazy Storage.load();
    return st.pendingWallets;
}

get fun assetJettonWallet(idx: int): address? {
    val st = lazy Storage.load();
    val a = st.assets.mustGet(idx as uint16);
    return a.jettonWallet;
}

// Batch distribution progress (mode, cursor, retryCount).
get fun distributionProgress(): (int, int, int) {
    val st = lazy Storage.load();
    val d = st.dist.load();
    return (d.mode as int, d.cursor as int, d.retryCount as int);
}
