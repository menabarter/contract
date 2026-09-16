// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Bounce handling: onBouncedMessage, the retry mechanism, and a mock of a
// broken recipient (SetNftReject). kick/force_deliver tests live in this
// same file.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/SwapEscrow.gen"
import "escrow_helpers"

// Toggle the mock's rejectTransfers directly (a test opcode, accepted from
// anyone — see contracts/nft_item_mock.tolk).
fun setNftReject(sender: address, nft: address, reject: bool): SendResultList {
    val m = createMessage({
        bounce: false,
        value: ton("0.05"),
        dest: nft,
        body: SetNftReject {
            queryId: 0,
            reject,
        },
    });
    return net.send(sender, m);
}

// ─────────────────────────────────────────────────────────────────────────

// Rule: "bounce → the asset gets delivered by the next KICK". If retry
// redelivery ran on every batch (including every self-triggered continue), a
// permanently rejecting asset would create an infinite
// send→bounce→retry→continue chain (an emulator stack overflow; on a real
// network, balance burn). So in runDistributionBatch(drainRetry) the
// auto-chain (drainRetry=false) does NOT touch retry and PARKS when the
// cursor has passed the registry with retryCount>0; redelivery only happens
// via kick (drainRetry=true), and a kick that redelivered even one asset also
// parks (a repeat bounce needs time to arrive before finalizing). The asserts
// below specifically pin down the PARKED state: EXECUTING (not DONE),
// cursor==n, retryCount==1, the asset physically held by the escrow.
struct ParkedFixture {
    escrow: EscrowFixture
    badNft: address
    o1: Treasury
    o2: Treasury
    fw: Treasury
    sup: Treasury
    n: int
}

// Shared fixture: a large deal (51×50 = 101 assets > fast-path), where ONE
// mock NFT (global index 5, side 1) enables rejectTransfers AFTER its own
// deposit — auto-execution goes down the batched path, the badNft transfer
// bounces, onBouncedMessage puts it in retry, and the auto-chain PARKS.
// Returns the parked state (EXECUTING, retryCount==1).
fun parkWithBadNft(tag: string): ParkedFixture {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val sup = testing.treasury(tagged(tag, "-sup"));

    val n1 = 51;
    val n2 = 50;
    var nfts1: map<uint16, address> = [];
    var badNft: address = fw.address; // placeholder, overwritten below
    var i = 0;
    while (i < n1) {
        val nft = deployNft(o1, 9000 + i);
        nfts1.set(i as uint16, nft);
        if (i == 5) {
            badNft = nft;
        }
        i += 1;
    }
    var nfts2: map<uint16, address> = [];
    var j = 0;
    while (j < n2) {
        nfts2.set(j as uint16, deployNft(o2, 9500 + j));
        j += 1;
    }

    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        supervisor: sup.address,
        nfts1,
        nfts1Count: n1,
        nfts2,
        nfts2Count: n2,
        gram1Amount: 0,
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);
    val fwd = ton("0.20");

    var last = escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE);
    expect(last).toHaveAllSuccessfulTxs();

    // Side-1 deposits: index 5 (badNft) is deposited as an ordinary NFT,
    // THEN (after being successfully received) the owner enables transfer
    // rejection on the mock — simulating a "broken recipient" that broke
    // AFTER the deposit.
    var r1 = nfts1.findFirst();
    while (r1.isFound) {
        val idx = r1.getKey();
        val nft = r1.loadValue();
        last = sendNftToEscrow(o1, nft, escrow.address, fwd);
        expect(last).toHaveAllSuccessfulTxs();
        if (idx == 5) {
            last = setNftReject(o1.address, nft, true);
            expect(last).toHaveAllSuccessfulTxs();
        }
        r1 = nfts1.iterateNext(r1);
    }

    last = escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE);
    expect(last).toHaveAllSuccessfulTxs();

    var r2 = nfts2.findFirst();
    var j2 = 0;
    while (r2.isFound) {
        last = sendNftToEscrow(o2, r2.loadValue(), escrow.address, fwd);
        if (j2 < n2 - 1) {
            expect(last).toHaveAllSuccessfulTxs();
        }
        // The last deposit is NOT asserted with toHaveAllSuccessfulTxs: its
        // auto-execution cascade INTENTIONALLY CONTAINS a failing badNft
        // transfer (rejectTransfers → exit 999 → bounce) — that is exactly
        // the scenario under test; the tests' own asserts pin down the
        // cascade's integrity.
        j2 += 1;
        r2 = nfts2.iterateNext(r2);
    }

    // The last deposit's cascade includes the badNft bounce and its
    // handling by onBouncedMessage (the emulator delivers the self-send and
    // the bounce within a single net.send, see STEP0 in
    // distribution.test.tolk).
    expect(last).toHaveBouncedTx({ to: escrow.address });
    return ParkedFixture {
        escrow,
        badNft,
        o1,
        o2,
        fw,
        sup,
        n: n1 + n2,
    };
}

get fun `test bounced NFT transfer lands in retry and redelivers`() {
    val f = parkWithBadNft("bnc1");
    val progress = f.escrow.distributionProgress();
    // Parked-state asserts (redelivery via kick — tests below).
    expect(progress.0).toEqual(DIST_EXECUTE);
    expect(progress.1).toEqual(f.n);                   // cursor reached the end of the registry
    expect(
        progress.2,
    ).toEqual(1);                                      // exactly one asset is waiting for redelivery
    expect(f.escrow.phase()).toEqual(PHASE_EXECUTING); // NOT DONE — retry is non-empty

    // The asset physically stayed with the escrow (the transfer did not go through).
    expect(readMockOwner(f.badNft)).toEqual(f.escrow.address);
}

get fun `test bounce with sentinel queryId ignored`() {
    // RescueNft (queryId 0xFFFE, hardcoded in handleRescueNft) targeting a
    // broken NFT → the bounce is ignored by the earliest sentinel check
    // (queryId >= 0xFFFE), touching no deal state at all.
    val o1 = testing.treasury("bnc2-o1");
    val o2 = testing.treasury("bnc2-o2");
    val fw = testing.treasury("bnc2-fw");
    val sup = testing.treasury("bnc2-sup");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));

    // The NFT must physically belong to the escrow by the time of rescue
    // (handleRescueNft does not gate on ownership, but an outgoing
    // NftTransfer from the escrow will only pass the mock's owner check if
    // it actually owns the asset): the default dust deposit (forward <
    // RETURN_TRANSFER_VALUE) leaves the NFT stuck at the escrow without
    // registering it in the deal's registry (the same pattern as
    // supervisor.test.tolk "rescue_nft transfers stuck NFT to supervisor").
    // Reject is enabled AFTER the mock is already owned by the escrow —
    // otherwise the dust deposit itself would bounce.
    val nft = deployNft(o1, 9901);
    expect(sendNftToEscrow(o1, nft, escrow.address, ton("0.005"))).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nft)).toEqual(escrow.address);
    expect(setNftReject(o1.address, nft, true)).toHaveAllSuccessfulTxs();

    val before = escrow.distributionProgress();
    val res = escrow.sendRescueNft(sup.address, nft, { value: ton("0.1") });
    // The RescueNft transaction on the escrow succeeds (handleRescueNft only
    // sends the transfer); the child transfer TO the mock fails (999) and
    // bounces back — both facts are asserted separately rather than with
    // toHaveAllSuccessfulTxs() on the whole tree.
    expect(res).toHaveFailedTx({ to: nft, exitCode: 999 });
    expect(res).toHaveBouncedTx({ to: escrow.address });

    val after = escrow.distributionProgress();
    expect(after.0).toEqual(before.0);
    expect(after.1).toEqual(before.1);
    expect(after.2).toEqual(0); // retryCount untouched by the sentinel
    expect(readMockOwner(nft)).toEqual(
        escrow.address,
    );                          // owner unchanged (the transfer did not go through)
}

get fun `test bounce in DONE phase ignored, asset recoverable by rescue`() {
    // A small deal (fast-path, 1x1 NFT) — one NFT with reject enabled AFTER
    // the deposit. Auto-execution (the last deposit) goes to PHASE_DONE via
    // the single-transaction path (executeSwapSingleTx, ≤100 assets); the
    // rejecting NFT's transfer bounces only AFTER phase == DONE has already
    // been committed — onBouncedMessage must silently swallow it
    // (dist.mode == DIST_IDLE is a documented exception), without touching
    // retryCount.
    val o1 = testing.treasury("bnc3-o1");
    val o2 = testing.treasury("bnc3-o2");
    val fw = testing.treasury("bnc3-fw");
    val sup = testing.treasury("bnc3-sup");

    val nft1 = deployNft(o1, 9801);
    val nft2 = deployNft(o2, 9802);
    var nfts1: map<uint16, address> = [];
    nfts1.set(0, nft1);
    var nfts2: map<uint16, address> = [];
    nfts2.set(0, nft2);
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        supervisor: sup.address,
        nfts1,
        nfts1Count: 1,
        nfts2,
        nfts2Count: 1,
        gram1Amount: 0,
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, nft1, escrow.address, ton("0.20"))).toHaveAllSuccessfulTxs();
    // nft1 already has received=true at the escrow — now we enable transfer
    // rejection (the transfer for this NFT at deal execution is still ahead).
    expect(setNftReject(o1.address, nft1, true)).toHaveAllSuccessfulTxs();

    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    // The last deposit triggers auto-execute: fast-path (2 assets ≤ 100) →
    // executeSwapSingleTx, phase=DONE is set BEFORE distribution (see
    // Storage.executeSwapSingleTx), so finalization happens INDEPENDENTLY of
    // the nft1 transfer later bouncing.
    val last = sendNftToEscrow(o2, nft2, escrow.address, ton("0.20"));
    expect(last).toHaveBouncedTx({ to: escrow.address });
    expect(escrow.phase()).toEqual(PHASE_DONE);

    val progress = escrow.distributionProgress();
    expect(progress.0).toEqual(DIST_IDLE); // fast-path never started dist
    expect(progress.2).toEqual(0);         // bounce swallowed silently, retryCount untouched
    // nft1 physically stayed with the escrow (the transfer did not go through).
    expect(readMockOwner(nft1)).toEqual(escrow.address);
    // nft2 (no reject) went to its new owner (o1) without issue.
    expect(readMockOwner(nft2)).toEqual(o1.address);

    // The supervisor rescues the stuck NFT — but the reject must be lifted
    // first (otherwise the rescue would bounce too: the mock does not
    // distinguish who sends the transfer).
    expect(setNftReject(o1.address, nft1, false)).toHaveAllSuccessfulTxs();
    val rescueRes = escrow.sendRescueNft(sup.address, nft1, { value: ton("0.1") });
    expect(rescueRes).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nft1)).toEqual(sup.address);
}

// ─────────────────────────────────────────────────────────────────────────
// kick + force_deliver
// ─────────────────────────────────────────────────────────────────────────

fun sendForceDeliver(
    sender: address,
    escrow: address,
    idx: int,
    fallback: bool,
    value: coins,
): SendResultList {
    val m = createMessage({
        bounce: true,
        value,
        dest: escrow,
        body: ForceDeliver {
            queryId: 0,
            assetIndex: idx as uint16,
            fallback,
        },
    });
    return net.send(sender, m);
}

struct MidFixture {
    escrow: EscrowFixture
    nfts1: map<uint16, address>
    nfts2: map<uint16, address>
    o1: Treasury
    o2: Treasury
    sup: Treasury
}

// Mid-state fixture constructor: an n1×n2 NFT deal deployed DIRECTLY into
// EXECUTING with the cursor at cursorAt (deployEscrowMidDistribution, see
// escrow_helpers) — reproduces a "broken chain" without running through
// deposits.
fun midSetup(tag: string, n1: int, n2: int, cursorAt: int, seedBase: int): MidFixture {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val sup = testing.treasury(tagged(tag, "-sup"));
    var nfts1: map<uint16, address> = [];
    var i = 0;
    while (i < n1) {
        nfts1.set(i as uint16, deployNft(o1, seedBase + i));
        i += 1;
    }
    var nfts2: map<uint16, address> = [];
    var j = 0;
    while (j < n2) {
        nfts2.set(j as uint16, deployNft(o2, seedBase + 500 + j));
        j += 1;
    }
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        supervisor: sup.address,
        nfts1,
        nfts1Count: n1,
        nfts2,
        nfts2Count: n2,
        gram1Amount: 0,
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrowMidDistribution(o1, cfg, cursorAt);
    return MidFixture { escrow, nfts1, nfts2, o1, o2, sup };
}

get fun `test broken chain resumed by kick to DONE`() {
    // 120 assets, the cursor is broken off at 70: kick (owner1) continues
    // from the current position — a kick with no redeliveries (drained==0)
    // and cursor<n sends continue, the chain finishes the remainder and
    // finalizes within the same cascade → DONE.
    val f = midSetup("kick1", 60, 60, 70, 20000);
    val res = f.escrow.sendText(f.o1.address, "kick", ton("5"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_DONE);
    val p = f.escrow.distributionProgress();
    expect(p.0).toEqual(DIST_IDLE);
    // Assets 70..119 (nfts2[10..59], side 2) are delivered to the opposite
    // side (o1); the fixture considers assets BEFORE the cursor already
    // sent — kick does NOT touch them (the cursor never rewinds, so
    // double-send is ruled out).
    expect(readMockOwner(f.nfts2.mustGet(10))).toEqual(f.o1.address);
    expect(readMockOwner(f.nfts2.mustGet(35))).toEqual(f.o1.address);
    expect(readMockOwner(f.nfts2.mustGet(59))).toEqual(f.o1.address);
    expect(readMockOwner(f.nfts2.mustGet(9))).toEqual(f.escrow.address); // idx 69 < cursor
}

get fun `test repeated kick causes no double delivery`() {
    // A tail of 10 assets (cursor 110 out of 120): kick #1 finishes to
    // DONE; a repeat kick → 410 (mode IDLE). The tail is delivered exactly
    // once, assets before the cursor are untouched.
    val f = midSetup("kick2", 60, 60, 110, 21000);
    expect(f.escrow.sendText(f.o1.address, "kick", ton("2"))).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_DONE);
    expect(f.escrow.sendText(f.o1.address, "kick", ton("0.1"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.AlreadyFinalized,
    });
    expect(readMockOwner(f.nfts2.mustGet(50))).toEqual(f.o1.address);     // idx 110
    expect(readMockOwner(f.nfts2.mustGet(59))).toEqual(f.o1.address);     // idx 119
    expect(readMockOwner(f.nfts2.mustGet(49))).toEqual(f.escrow.address); // idx 109 "already sent"
}

get fun `test kick from stranger rejected 403`() {
    val f = midSetup("kick3", 2, 2, 2, 22000);
    val mallory = testing.treasury("kick3-mal");
    expect(f.escrow.sendText(mallory.address, "kick", ton("1"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.NotOwners,
    });
    expect(f.escrow.phase()).toEqual(PHASE_EXECUTING); // nothing moved
}

get fun `test bounced asset redelivered after kick`() {
    // Continuation of the parkWithBadNft scenario: the recipient "gets
    // fixed" → kick #1 redelivers (drained==1) and PARKS (a repeat bounce
    // needs time to arrive before finalizing); kick #2 finalizes
    // (sends==0) → DONE.
    val f = parkWithBadNft("bnc4");
    expect(setNftReject(f.o1.address, f.badNft, false)).toHaveAllSuccessfulTxs();

    val res1 = f.escrow.sendText(f.o1.address, "kick", ton("1"));
    expect(res1).toHaveAllSuccessfulTxs();
    expect(readMockOwner(f.badNft)).toEqual(f.o2.address); // delivered, exactly once
    expect(f.escrow.phase()).toEqual(PHASE_EXECUTING);     // parked after redelivery
    var p = f.escrow.distributionProgress();
    expect(p.0).toEqual(DIST_EXECUTE);
    expect(
        p.2,
    ).toEqual(0);                                          // retry drained, no repeat bounce

    // The resend gate: redelivery RESETS bounces, so a resend of an
    // already-delivered asset must be rejected with 431 —
    // double-send is ruled out even for a supervisor fat-finger.
    expect(sendForceDeliver(f.sup.address, f.escrow.address, 5, false, ton("0.1"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.BadAssetIndex,
    });

    val res2 = f.escrow.sendText(f.o1.address, "kick", ton("0.5"));
    expect(res2).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_DONE);
    p = f.escrow.distributionProgress();
    expect(p.0).toEqual(DIST_IDLE);
}

get fun `test force_deliver fallback abandons and unblocks DONE`() {
    // An "eternally broken" recipient: reject is NEVER lifted. kick #1:
    // redelivery → bounces again → parks again (retryCount==1); each
    // attempt requires an EXPLICIT kick — there is no balance burn. The
    // supervisor unblocks it: fallback=true → abandoned + finalization
    // within the same tx.
    val f = parkWithBadNft("bnc5");
    val res1 = f.escrow.sendText(f.o1.address, "kick", ton("1"));
    expect(res1).toHaveBouncedTx({ to: f.escrow.address });
    expect(f.escrow.phase()).toEqual(PHASE_EXECUTING);
    var p = f.escrow.distributionProgress();
    expect(p.2).toEqual(1); // the bounce put the asset back in retry

    val res2 = sendForceDeliver(f.sup.address, f.escrow.address, 5, true, ton("0.1"));
    expect(res2).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_DONE); // finalization is not blocked
    p = f.escrow.distributionProgress();
    expect(p.0).toEqual(DIST_IDLE);
    expect(p.2).toEqual(0);

    // The broken NFT stays with the escrow (abandoned → excluded from what's
    // awaited); once the recipient is "fixed", the supervisor retrieves it
    // via rescue_nft — the documented exception to "every received asset is
    // delivered or returned".
    expect(readMockOwner(f.badNft)).toEqual(f.escrow.address);
    expect(setNftReject(f.o1.address, f.badNft, false)).toHaveAllSuccessfulTxs();
    expect(
        f.escrow.sendRescueNft(f.sup.address, f.badNft, { value: ton("0.1") }),
    ).toHaveAllSuccessfulTxs();
    expect(readMockOwner(f.badNft)).toEqual(f.sup.address);
}

get fun `test force_deliver by non-supervisor rejected 404`() {
    val f = midSetup("fd404", 2, 2, 4, 23000);
    expect(sendForceDeliver(f.o1.address, f.escrow.address, 0, true, ton("0.1"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.NotSupervisor,
    });
}

get fun `test force_deliver on undelivered-yet index rejected 431`() {
    // cursorAt = 2 out of 4: indices 2,3 have NOT been sent yet — there is
    // nothing to force (the ordinary batch/kick will deliver them); plus one
    // index outside the registry; plus the resend gate — a resend of an asset
    // that is NOT known to be undelivered (not in retry, bounces==0) is
    // rejected with the same code.
    val f = midSetup("fd431", 2, 2, 2, 24000);
    expect(sendForceDeliver(f.sup.address, f.escrow.address, 2, false, ton("0.1"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.BadAssetIndex,
    });
    expect(sendForceDeliver(f.sup.address, f.escrow.address, 7, false, ton("0.1"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.BadAssetIndex,
    });
    expect(sendForceDeliver(f.sup.address, f.escrow.address, 0, false, ton("0.1"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.BadAssetIndex,
    });
}

get fun `test force_deliver resend delivers stuck asset, kick finalizes`() {
    // A successful resend (fallback=false): the recipient "gets fixed", but
    // the supervisor delivers it directly via force_deliver instead of kick.
    // The resend gate lets it through (the asset is in retry), the asset is
    // delivered; the distribution stays PARKED (force_deliver does not
    // finalize on the resend branch) — an ordinary kick closes it out.
    val f = parkWithBadNft("bnc7");
    expect(setNftReject(f.o1.address, f.badNft, false)).toHaveAllSuccessfulTxs();

    val res = sendForceDeliver(f.sup.address, f.escrow.address, 5, false, ton("0.05"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(readMockOwner(f.badNft)).toEqual(f.o2.address); // delivered to the deal's recipient
    expect(f.escrow.phase()).toEqual(PHASE_EXECUTING);
    var p = f.escrow.distributionProgress();
    expect(p.2).toEqual(0);                                // removed from retry

    // The second path through the resend gate: resend resets bounces → a
    // REPEAT force_deliver on an already-delivered asset → 431.
    expect(
        sendForceDeliver(f.sup.address, f.escrow.address, 5, false, ton("0.05")),
    ).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.BadAssetIndex,
    });

    expect(f.escrow.sendText(f.o1.address, "kick", ton("0.5"))).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_DONE);
    p = f.escrow.distributionProgress();
    expect(p.0).toEqual(DIST_IDLE);
}

// ─────────────────────────────────────────────────────────────────────────
// Mutation-testing targets for force_deliver. They live HERE (rather than in
// coverage_gaps.test.tolk) because they use the local parkWithBadNft
// fixture — duplicating it would be worse.
// ─────────────────────────────────────────────────────────────────────────

// remove_assert on the resend cost gate in handleForceDeliver. The other
// tests call force_deliver resend with a SUFFICIENT value (0.1), so this one
// pins `assert (value >= need)` with an insufficient value. Without the gate,
// the supervisor could initiate a transfer without covering its cost: the
// action phase would fail (code 37) already AFTER the retry entry was
// consumed.
get fun `test force_deliver resend with insufficient value rejected 430`() {
    val f = parkWithBadNft("bncCost");
    // Asset 5 bounced and sits in retry → the resend gate (wasInRetry) will pass,
    // so the rejection must come SPECIFICALLY from the cost gate.
    var p = f.escrow.distributionProgress();
    expect(p.2).toEqual(1);
    // value 0.01 < NFT_TRANSFER_VALUE (0.03).
    expect(
        sendForceDeliver(f.sup.address, f.escrow.address, 5, false, ton("0.01")),
    ).toHaveFailedTx({ to: f.escrow.address, exitCode: Errors.InsufficientBalance });
    // The transaction rolled back entirely: the retry entry is NOT lost.
    p = f.escrow.distributionProgress();
    expect(p.2).toEqual(1);
    expect(f.escrow.phase()).toEqual(PHASE_EXECUTING);
}

// remove_assert on `idx < cursor` in handleForceDeliver.
// For the RESEND branch this assert is redundant (the resend gate would throw
// 431 anyway), but for the FALLBACK branch it carries real meaning: without
// it, the supervisor could mark `abandoned` an asset the cursor has NOT YET
// TOUCHED — that is, irrevocably refuse delivery to an asset that the
// ordinary batch would have delivered on its own. Checked against a fixture
// with the cursor MID-REGISTRY.
get fun `test force_deliver fallback on asset beyond cursor rejected 431`() {
    val o1 = testing.treasury("m22-o1");
    val o2 = testing.treasury("m22-o2");
    val fw = testing.treasury("m22-fw");
    val sup = testing.treasury("m22-sup");
    var nfts1: map<uint16, address> = [];
    var i = 0;
    while (i < 3) {
        nfts1.set(i as uint16, deployNft(o1, 94100 + i));
        i += 1;
    }
    var nfts2: map<uint16, address> = [];
    nfts2.set(0, deployNft(o2, 94200));
    var cfg = makeBasicConfig(o1, o2, fw, sup);
    cfg.nfts1 = nfts1;
    cfg.nfts1Count = 3;
    cfg.nfts2 = nfts2;
    cfg.nfts2Count = 1;
    // Cursor at 1 out of 4 assets → indices 1..3 have NOT yet been passed by
    // the cursor.
    val escrow = deployEscrowMidDistribution(o1, cfg, 1, DIST_EXECUTE);
    expect(escrow.phase()).toEqual(PHASE_EXECUTING);

    // A fallback on an asset past the cursor must be rejected — there is
    // nothing to force.
    expect(
        sendForceDeliver(sup.address, escrow.address, 3, true, ton("0.1")),
    ).toHaveFailedTx({ to: escrow.address, exitCode: Errors.BadAssetIndex });

    // Control: an asset UNDER the cursor (idx 0) is allowed for fallback —
    // the gate specifically cuts off "past the cursor," not everything
    // (falsifiability).
    expect(
        sendForceDeliver(sup.address, escrow.address, 0, true, ton("0.1")),
    ).toHaveAllSuccessfulTxs();
}
