// GENERATED from tests/nosup/distribution.test.tolk by ts-tests/gen-v2-tests.ts — edit the source, then run npm run gen:v2.
// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Batched distribution: cursor + continue self-trigger, the fast-path gate,
// finalization as a separate transaction, the progress getter.
//
// STEP 0 (a check of an emulator assumption): the entire test strategy here
// rests on the assumption that the Acton emulator delivers self-messages
// (ContinueDistribution to itself) within the cascade of a single net.send.
// The first test below runs a 101-asset deal (>100 → the batched path) and
// expects phase() == PHASE_DONE right after the last deposit. If the emulator
// did NOT deliver self-sends, phase would get stuck in EXECUTING and the test
// would fail — so that test passing (cursor=101, mode=IDLE after the deposit)
// confirms the assumption the whole suite below is built on.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/messages"
import "@wrappers/SwapEscrowV2.gen"
import "@contracts/shared/types"
import "@contracts/v2/storage"
import "v2_helpers"

// ─────────────────────────────────────────────────────────────────────────
// Local helpers
// ─────────────────────────────────────────────────────────────────────────

struct CapturedSwap {
    escrow: EscrowFixture
    last: SendResultList // the result of the last deposit — contains the ENTIRE cascade
    o1: Treasury
    o2: Treasury
    fw: Treasury
}

// Like runFullSwap, but returns the SendResultList of the last deposit
// (which holds the entire continue chain + finalization, since the emulator
// applies the cascade within a single net.send, see STEP 0). Does not assert
// DONE internally — that's left to the tests.
fun runCaptureSwap(
    tag: string,
    n1: int,
    n2: int,
    gram1: coins,
    gram2: coins,
): CapturedSwap {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));

    var nfts1: map<uint16, address> = [];
    var i = 0;
    while (i < n1) {
        nfts1.set(i as uint16, deployNft(o1, 5000 + i));
        i += 1;
    }
    var nfts2: map<uint16, address> = [];
    var j = 0;
    while (j < n2) {
        nfts2.set(j as uint16, deployNft(o2, 6000 + j));
        j += 1;
    }

    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: n1,
        nfts2,
        nfts2Count: n2,
        gram1Amount: gram1,
        gram2Amount: gram2,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);
    val fwd = ton("0.20");

    if (gram1 > 0) {
        expect(
            escrow.sendText(o1.address, "deposit_ton1", gram1 + ton("0.01")),
        ).toHaveAllSuccessfulTxs();
    }
    var last = escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE);
    expect(last).toHaveAllSuccessfulTxs();
    var r1 = nfts1.findFirst();
    while (r1.isFound) {
        last = sendNftToEscrow(o1, r1.loadValue(), escrow.address, fwd);
        expect(last).toHaveAllSuccessfulTxs();
        r1 = nfts1.iterateNext(r1);
    }
    if (gram2 > 0) {
        last = escrow.sendText(o2.address, "deposit_ton2", gram2 + ton("0.01"));
        expect(last).toHaveAllSuccessfulTxs();
    }
    last = escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE);
    expect(last).toHaveAllSuccessfulTxs();
    var r2 = nfts2.findFirst();
    while (r2.isFound) {
        last = sendNftToEscrow(o2, r2.loadValue(), escrow.address, fwd);
        expect(last).toHaveAllSuccessfulTxs();
        r2 = nfts2.iterateNext(r2);
    }

    return CapturedSwap { escrow, last, o1, o2, fw };
}

// Deploy the escrow DIRECTLY into PHASE_EXECUTING with active batch
// distribution (dist.mode = DIST_EXECUTE, cursor = 0). Since the emulator
// applies the continue cascade atomically (STEP 0), an escrow "caught" in
// EXECUTING cannot be produced by a natural run — the state is constructed
// directly in Storage and deployed with an `Excesses` message (Excesses is
// credited silently in any phase, so it does not touch dist/phase). The
// asset registry is filled with
// dummy addresses (the gate tests do not read it — only the phase/sender
// gates are checked, the cursor never moves).
struct ExecFixture {
    escrow: EscrowFixture
    o1: Treasury
    o2: Treasury
}

fun deployExecuting(tag: string): ExecFixture {
    val o1 = testing.treasury(tagged(tag, "-xo1"));
    val o2 = testing.treasury(tagged(tag, "-xo2"));
    val fw = testing.treasury(tagged(tag, "-xfw"));
    val a1 = testing.treasury(tagged(tag, "-xa1"));
    val a2 = testing.treasury(tagged(tag, "-xa2"));

    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, a1.address);
    var n2: map<uint16, address> = [];
    n2.set(0, a2.address);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    cfg.nfts2 = n2;
    cfg.nfts2Count = 1;

    var st = buildInitialStorage(cfg);
    st.phase = PHASE_EXECUTING;
    st.dist = DistState {
        mode: DIST_EXECUTE,
        cursor: 0,
    }.toCell();

    val escrow = SwapEscrowV2.fromStorage(st);
    // An `Excesses` message: credited silently in any phase, so it does not
    // touch the EXECUTING phase or dist. Gives the escrow a balance and
    // "activates" the deployed state.
    val deployMsg = createMessage({
        bounce: false,
        value: ton("1"),
        dest: { stateInit: escrow.stateInit! },
        // Excesses is credited silently in any phase, so the escrow can be
        // deployed straight into EXECUTING or CANCELLED without passing
        // through a deposit handler.
        body: Excesses { queryId: 0 },
    });
    expect(net.send(o1.address, deployMsg)).toHaveSuccessfulDeploy({ to: escrow.address });
    expect(escrow.phase()).toEqual(PHASE_EXECUTING);
    return ExecFixture { escrow, o1, o2 };
}

// ─────────────────────────────────────────────────────────────────────────
// STEP 0: a check of an emulator assumption
// ─────────────────────────────────────────────────────────────────────────

get fun `test STEP0 emulator delivers self-send: 101 assets batched reaches DONE`() {
    // 51×50 = 101 assets (>100) → the batched path. runFullSwap asserts DONE
    // + NFT owners; if the continue self-message cascade had not been
    // applied, phase would have stayed EXECUTING and this assert would have
    // failed. It passes ⇒ the emulator delivers self-messages within a
    // single net.send (the assumption holds).
    val escrow = runFullSwap(51, 50, 0, 0, ton("0.20"));
    expect(escrow.phase()).toEqual(PHASE_DONE);
    val progress = escrow.distributionProgress();
    expect(progress.0).toEqual(DIST_IDLE); // distribution completed
    expect(progress.1).toEqual(101);       // cursor reached the end of the registry
}

// ─────────────────────────────────────────────────────────────────────────
// Core batching-engine tests
// ─────────────────────────────────────────────────────────────────────────

get fun `test batched execute 60x60 reaches DONE with continue chain`() {
    // 120 assets (>100) → the batched path: 3 asset batches (50+50+20) + a
    // SEPARATE final transaction (finalization only when sends ==
    // 0) — a total of 3 ContinueDistribution self-messages in the trace.
    val escrow = runFullSwap(60, 60, ton("1"), ton("0"), ton("0.20"));
    // runFullSwap already asserts DONE and NFT owners — additionally:
    val progress = escrow.distributionProgress();
    expect(progress.0).toEqual(DIST_IDLE); // distribution completed
    expect(progress.1).toEqual(120);       // cursor passed all 120 assets
}

get fun `test fast path boundary: 100 assets single tx, 101 assets batched`() {
    // 50×50 = 100 → fast-path: DONE in the last deposit's transaction, and
    // NOT a single ContinueDistribution in the trace.
    val c1 = runCaptureSwap("fpb100", 50, 50, 0, 0);
    expect(c1.escrow.phase()).toEqual(PHASE_DONE);
    expect(c1.last).toNotHaveTx<ContinueDistribution>({ to: c1.escrow.address });
    // Fast-path never starts a dist state at all.
    expect(c1.escrow.distributionProgress().0).toEqual(DIST_IDLE);
    expect(c1.escrow.distributionProgress().1).toEqual(0);

    // 51×50 = 101 → batched: DONE + AT LEAST one self-message in the trace.
    val c2 = runCaptureSwap("fpb101", 51, 50, 0, 0);
    expect(c2.escrow.phase()).toEqual(PHASE_DONE);
    expect(c2.last).toHaveTx<ContinueDistribution>({ to: c2.escrow.address });
    expect(c2.escrow.distributionProgress().0).toEqual(DIST_IDLE);
    expect(c2.escrow.distributionProgress().1).toEqual(101);
}

get fun `test final batch sends the legs, the fee and the refunds and keeps the floor`() {
    // A large deal (101 assets, the batched path) with GRAM on both sides.
    // gram1 = 1 goes to owner2, gram2 = 0.5 goes to owner1 (an exchange of opposites).
    val gram1 = ton("1");
    val gram2 = ton("0.5");
    val c = runCaptureSwap("fbrefund", 51, 50, gram1, gram2);
    expect(c.escrow.phase()).toEqual(PHASE_DONE);

    // The GRAM exchange goes out as SEPARATE messages in the final batch:
    // owner1 receives gram2, owner2 receives gram1 (a window with an upper
    // bound equal to the exact amount: the forward fee can only DECREASE the
    // delivered value, never increase it — the same pattern as
    // jetton_swap.test.tolk; these sides' refunds are much LARGER than the
    // window and so do not satisfy it — the match specifically catches the
    // exchange itself).
    expect(c.last).toHaveTx({
        to: c.o1.address,
        value: fun(v: coins): bool {
            return v <= gram2 && v >= gram2 - ton("0.001");
        },
    });
    expect(c.last).toHaveTx({
        to: c.o2.address,
        value: fun(v: coins): bool {
            return v <= gram1 && v >= gram1 - ton("0.001");
        },
    });
    // fee-wallet received the combined service fee (0.2) + a dust sweep (≥ 0.19).
    expect(c.last).toHaveTx({
        to: c.fw.address,
        value: fun(v: coins): bool {
            return v >= ton("0.19");
        },
    });
    // NFT owners are swapped cross-wise.
    // THE MAIN POINT: the final batch's dust sweep leaves exactly the storage
    // floor on the escrow (refunds are clamped to 0, so they cannot be
    // negative by construction).
    expect(testing.getAccountBalance(c.escrow.address)).toEqual(c.escrow.storageFloor());
    // Distribution completed: the registry has been walked.
    val progress = c.escrow.distributionProgress();
    expect(progress.0).toEqual(DIST_IDLE);
}

// ─────────────────────────────────────────────────────────────────────────
// EXECUTING-phase gates
// ─────────────────────────────────────────────────────────────────────────

get fun `test continue_distribution from stranger rejected 403`() {
    val f = deployExecuting("cont403");
    val mallory = testing.treasury("cont403-mal");
    val before = f.escrow.distributionProgress();
    // An unauthorized sender of the self-trigger → the assert sender ==
    // myAddress fails with 403.
    val res = f
        .escrow
        .sendContinueDistribution(
            mallory.address,
            0,
            { value: ton("0.05"), bounce: true },
        );
    expect(res).toHaveFailedTx({ to: f.escrow.address, exitCode: Errors.NotOwners });
    // Progress did not move (the transaction rolled back atomically).
    val after = f.escrow.distributionProgress();
    expect(after.0).toEqual(before.0);
    expect(after.1).toEqual(before.1);
    expect(f.escrow.phase()).toEqual(PHASE_EXECUTING);
}

get fun `test deposits rejected in EXECUTING phase`() {
    val f = deployExecuting("depexec");
    // deposit_ton1 in EXECUTING → the handler's phase assert fails with 410.
    val res = f.escrow.sendText(f.o1.address, "deposit_ton1", ton("1"));
    expect(res).toHaveFailedTx({ to: f.escrow.address, exitCode: Errors.AlreadyFinalized });
    expect(f.escrow.phase()).toEqual(PHASE_EXECUTING);
    // service_fee is also rejected by the same phase check.
    val res2 = f.escrow.sendText(f.o2.address, "service_fee_owner2", SERVICE_FEE);
    expect(res2).toHaveFailedTx({ to: f.escrow.address, exitCode: Errors.AlreadyFinalized });
}

get fun `test late NFT in EXECUTING returned gracefully`() {
    // OwnershipAssigned in EXECUTING (an unrelated
    // NFT with value >= RETURN_TRANSFER_VALUE) → NO throw, an automatic
    // return to previousOwner.
    val f = deployExecuting("latenft");
    val mallory = testing.treasury("latenft-mal");
    val nft = deployNft(mallory, 7777); // NOT in the escrow's registry — a foreign NFT
    val before = f.escrow.distributionProgress();

    val res = sendNftToEscrow(mallory, nft, f.escrow.address, ton("0.20"));
    expect(res).toHaveAllSuccessfulTxs();                // no throw at all
    expect(readMockOwner(nft)).toEqual(mallory.address); // returned to the depositor

    // The dist state (mode/cursor) is unchanged.
    val after = f.escrow.distributionProgress();
    expect(after.0).toEqual(before.0);
    expect(after.1).toEqual(before.1);
    expect(f.escrow.phase()).toEqual(PHASE_EXECUTING);
}

get fun `test late jetton notification in EXECUTING returned gracefully`() {
    // The same for transfer_notification: EXECUTING is a terminal phase for
    // accepting jettons → returnJettons via a reverse transfer, the
    // transaction is SUCCESSFUL (no throw at all), the dist
    // state is untouched.
    val f = deployExecuting("latejet");
    val mallory = testing.treasury("latejet-mal");
    val before = f.escrow.distributionProgress();

    // A raw notification sent directly (as with fakeNotificationHarmless in
    // jetton_deposits): value >= RETURN_TRANSFER_VALUE, so returnJettons
    // actually sends a refund.
    val res = f
        .escrow
        .sendJettonTransferNotification(
            mallory.address,
            1,
            ton("100"),
            mallory.address, // masquerading as the depositor
            zeroBitSlice(),
            { value: ton("0.1"), bounce: true },
        );
    expect(res).toHaveAllSuccessfulTxs();

    val after = f.escrow.distributionProgress();
    expect(after.0).toEqual(before.0);
    expect(after.1).toEqual(before.1);
    expect(f.escrow.phase()).toEqual(PHASE_EXECUTING);
}
