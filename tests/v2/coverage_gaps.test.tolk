// GENERATED from tests/nosup/coverage_gaps.test.tolk by ts-tests/gen-v2-tests.ts — edit the source, then run npm run gen:v2.
// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Tests targeted by NATIVE mutation testing (`acton test --mutate
// --mutate-contract SwapEscrowV2 --mutation-levels critical`).
//
// Each test below kills a SPECIFIC mutant — removing the check it names from
// the contract must make a test fail. That is exactly the point: tests must
// actually catch broken logic, not just produce a green run.
//
// Each section names the check and the mutation rule it guards against.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowV2.gen"
import "@contracts/shared/types"
import "@contracts/v2/storage"
import "v2_helpers"

// ── service_fee AUTHORIZATION (handleServiceFee owner asserts: remove_assert) ──
// Without these asserts, ANY outsider could "pay" a side's fee by crediting
// their own TON into serviceFee1/2.

get fun `test service_fee_owner1 from stranger rejected 401`() {
    val o1 = testing.treasury("cg1-o1");
    val o2 = testing.treasury("cg1-o2");
    val fw = testing.treasury("cg1-fw");
    val stranger = testing.treasury("cg1-stranger");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw));
    expect(
        escrow.sendText(stranger.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveFailedTx({ to: escrow.address, exitCode: Errors.NotOwner1 });
}

get fun `test service_fee_owner2 from stranger rejected 402`() {
    val o1 = testing.treasury("cg2-o1");
    val o2 = testing.treasury("cg2-o2");
    val fw = testing.treasury("cg2-fw");
    val stranger = testing.treasury("cg2-stranger");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw));
    expect(
        escrow.sendText(stranger.address, "service_fee_owner2", SERVICE_FEE),
    ).toHaveFailedTx({ to: escrow.address, exitCode: Errors.NotOwner2 });
}

// owner2 paying for side 1 is also an outsider to that side (strengthens the
// pair above: it checks SPECIFICALLY the side binding, not just "any stranger").
get fun `test service_fee_owner1 paid by owner2 rejected 401`() {
    val o1 = testing.treasury("cg3-o1");
    val o2 = testing.treasury("cg3-o2");
    val fw = testing.treasury("cg3-fw");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw));
    expect(
        escrow.sendText(o2.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveFailedTx({ to: escrow.address, exitCode: Errors.NotOwner1 });
}

// ── PHASE GATES AFTER THE TERMINAL STATE ──

// remove_assert on the handleDeployFee phase gate: deploy_fee after finalization.
get fun `test deploy_fee after cancel rejected 410`() {
    val o1 = testing.treasury("cg4-o1");
    val o2 = testing.treasury("cg4-o2");
    val fw = testing.treasury("cg4-fw");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw));
    expect(escrow.sendText(o1.address, "cancel_swap", ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(
        escrow.sendText(o1.address, "deploy_fee", ton("0.05")),
    ).toHaveFailedTx({ to: escrow.address, exitCode: Errors.AlreadyFinalized });
}

// ── NFT acceptance via hint: the `!a.received` gate ──
// remove_logical_not in handleNftReceived: without `!a.received`, a hint
// pointing at an ALREADY-ACCEPTED slot would be accepted again. Checks that
// a second NFT hinting at an occupied slot is NOT counted into that slot
// (and does not corrupt the bookkeeping): side 1's received counter stays
// at 1, and the "extra" NFT is auto-returned to its depositor (it is not
// registered as a deal asset at that index).
get fun `test hint pointing at already-received slot is not double-counted`() {
    val o1 = testing.treasury("cg8-o1");
    val o2 = testing.treasury("cg8-o2");
    val fw = testing.treasury("cg8-fw");
    val nftA = deployNft(o1, 95201);
    val nftB = deployNft(o1, 95202);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, nftA);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    val escrow = deployEscrow(o1, cfg);

    // An ordinary deposit into slot 0.
    expect(
        sendNftToEscrow(o1, nftA, escrow.address, ton("0.2"), 0),
    ).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nftA)).toEqual(escrow.address);

    // A second NFT, FOREIGN to the deal, with a hint at the same (already
    // accepted) slot 0. The `!a.received` gate + the `a.addr == nft` check
    // must reject it → auto-return to the depositor, the slot is not
    // overwritten.
    expect(
        sendNftToEscrow(o1, nftB, escrow.address, ton("0.2"), 0),
    ).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nftB)).toEqual(o1.address); // returned, did not stay at the escrow
    // Slot 0 is still occupied SPECIFICALLY by nftA (no substitution occurred).
    expect(readMockOwner(nftA)).toEqual(escrow.address);
}

// ── Unknown binary opcode ──
// remove_throw in the message router: the routing test in deploy.test.tolk
// covers an unknown TEXT command (130). An unknown BINARY opcode goes into
// `else => throw Errors.UnknownOp`, pinned here.
get fun `test unknown binary opcode rejected 0xFFFF`() {
    val o1 = testing.treasury("cg9-o1");
    val o2 = testing.treasury("cg9-o2");
    val fw = testing.treasury("cg9-fw");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw));
    // An arbitrary opcode not part of the union of incoming messages.
    val body = beginCell().storeUint(0x7ac0ffee, 32).storeUint(0, 64).endCell();
    val m = createMessage({
        bounce: true,
        value: ton("0.05"),
        dest: escrow.address,
        body,
    });
    expect(net.send(o1.address, m)).toHaveFailedTx({
        to: escrow.address,
        exitCode: Errors.UnknownOp,
    });
}

// ── MANUAL execute_swap: precondition gates ──
// handleExecuteSwap is the only path where owner1 forces execution manually.
// These tests pin the rejection when side 2's preconditions are NOT met.

// remove_assert: gram2Received >= gram2Amount → 421.
get fun `test manual execute_swap without side2 GRAM rejected 421`() {
    val o1 = testing.treasury("cgB-o1");
    val o2 = testing.treasury("cgB-o2");
    val fw = testing.treasury("cgB-fw");
    var cfg = makeBasicConfig(o1, o2, fw);
    cfg.gram2Amount = ton("0.3"); // side 2 is required to deposit GRAM, but doesn't
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(
        escrow.sendText(o1.address, "execute_swap", ton("0.1")),
    ).toHaveFailedTx({ to: escrow.address, exitCode: Errors.NotEnoughTon2 });
}

// remove_assert: received2Count >= required2Count → 424.
get fun `test manual execute_swap without side2 NFT rejected 424`() {
    val o1 = testing.treasury("cgC-o1");
    val o2 = testing.treasury("cgC-o2");
    val fw = testing.treasury("cgC-fw");
    val nft1 = deployNft(o1, 95401);
    val nft2 = deployNft(o2, 95402);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, nft1);
    var n2: map<uint16, address> = [];
    n2.set(0, nft2);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    cfg.nfts2 = n2;
    cfg.nfts2Count = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    // ONLY side 1 has deposited; side 2 has not deposited its NFT.
    expect(sendNftToEscrow(o1, nft1, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    expect(
        escrow.sendText(o1.address, "execute_swap", ton("0.1")),
    ).toHaveFailedTx({ to: escrow.address, exitCode: Errors.NftsNotReceived });
}

// remove_assert: the phase gate for manual execute_swap → 410.
get fun `test manual execute_swap after cancel rejected 410`() {
    val o1 = testing.treasury("cgD-o1");
    val o2 = testing.treasury("cgD-o2");
    val fw = testing.treasury("cgD-fw");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw));
    expect(escrow.sendText(o1.address, "cancel_swap", ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(
        escrow.sendText(o1.address, "execute_swap", ton("0.1")),
    ).toHaveFailedTx({ to: escrow.address, exitCode: Errors.AlreadyFinalized });
}

// ── DUPLICATE DEPOSIT into an already-received slot, without rescue ──
// Replaces the beta suite's rescue-based duplicate test: there is no
// supervisor/rescue path in the nosup contract, so the guard against
// double-crediting a slot is exercised directly. The pre-received state is
// built straight into Storage (buildInitialStorage + a manual `received`
// flip), deployed via SwapEscrowV2.fromStorage — the same technique
// nosup_helpers uses for deployEscrowMidDistribution/deploySparseCancelMidState.
// The NFT mock itself is still owned by the depositor (the pre-received flag
// is synthetic bookkeeping, not an actual prior transfer), so sending it a
// second time exercises exactly the `asset.received` duplicate guard in
// handleNftReceived (contracts/escrow_nosup_beta_v1.tolk): the fallback linear
// scan finds the slot by address regardless of the hint, and the
// `if (asset.received)` check returns it to the sender rather than
// double-crediting receivedCounts.
get fun `test duplicate deposit into an already-received slot is returned, receivedCounts unchanged`() {
    val o1 = testing.treasury("cgE-o1");
    val o2 = testing.treasury("cgE-o2");
    val fw = testing.treasury("cgE-fw");
    val nft1 = deployNft(o1, 96001);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, nft1);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;

    var st = buildInitialStorage(cfg);
    var a = st.assets.mustGet(0);
    a.received = true;
    st.assets.set(0, a);
    st.received1Count = 1;
    val escrow = SwapEscrowV2.fromStorage(st);
    val deployMessage = createMessage({
        bounce: BounceMode.NoBounce,
        value: ton("0.1"),
        dest: { stateInit: escrow.stateInit! },
        body: textBody("deploy_fee"),
    });
    expect(net.send(o1.address, deployMessage)).toHaveSuccessfulDeploy({ to: escrow.address });
    expect(escrow.receivedCounts()).toEqual((1, 0));

    // Slot 0 is already marked received, but nft1 is still physically with o1
    // (never actually transferred) — sending it again, with a hint pointing
    // straight at that slot, must be rejected and returned, not accepted as a
    // second copy.
    expect(
        sendNftToEscrow(o1, nft1, escrow.address, ton("0.2"), 0),
    ).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nft1)).toEqual(o1.address);
    expect(escrow.receivedCounts()).toEqual((1, 0));
}

// ── kick — sender must be one of the two owners ──
// handleKick's sender check: without it, an outsider could invoke kick, a
// resume operation that must stay restricted to the deal's own owners.
// Isolated from the dist-mode gate below it by using an EXECUTING deal with
// an active batch (dist.mode != DIST_IDLE), so removing only the sender
// check would let the stranger's kick actually run a batch.
get fun `test kick from stranger rejected 403`() {
    val o1 = testing.treasury("cgF-o1");
    val o2 = testing.treasury("cgF-o2");
    val fw = testing.treasury("cgF-fw");
    val nft1 = deployNft(o1, 96101);
    val nft2 = deployNft(o2, 96102);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, nft1);
    var n2: map<uint16, address> = [];
    n2.set(0, nft2);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    cfg.nfts2 = n2;
    cfg.nfts2Count = 1;
    val escrow = deployEscrowMidDistribution(o1, cfg, 0, DIST_EXECUTE);
    val stranger = testing.treasury("cgF-stranger");
    val before = escrow.distributionProgress();
    expect(
        escrow.sendText(stranger.address, "kick", ton("1")),
    ).toHaveFailedTx({ to: escrow.address, exitCode: Errors.NotOwners });
    val after = escrow.distributionProgress();
    expect(after.0).toEqual(before.0);
    expect(after.1).toEqual(before.1);
}
