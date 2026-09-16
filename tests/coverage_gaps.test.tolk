// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Tests targeted by NATIVE mutation testing (`acton test --mutate
// --mutate-contract SwapEscrow --mutation-levels critical`).
//
// Each test below kills a SPECIFIC mutant — removing the check it names from
// the contract must make a test fail. That is exactly the point: tests must
// actually catch broken logic, not just produce a green run.
//
// Each section names the check and the mutation rule it guards against.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/SwapEscrow.gen"
import "escrow_helpers"

fun sendForceDeliverCg(
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

// ── service_fee AUTHORIZATION (handleServiceFee owner asserts: remove_assert) ──
// Without these asserts, ANY outsider could "pay" a side's fee by crediting
// their own TON into serviceFee1/2.

get fun `test service_fee_owner1 from stranger rejected 401`() {
    val o1 = testing.treasury("cg1-o1");
    val o2 = testing.treasury("cg1-o2");
    val fw = testing.treasury("cg1-fw");
    val sup = testing.treasury("cg1-sup");
    val stranger = testing.treasury("cg1-stranger");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));
    expect(
        escrow.sendText(stranger.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveFailedTx({ to: escrow.address, exitCode: Errors.NotOwner1 });
}

get fun `test service_fee_owner2 from stranger rejected 402`() {
    val o1 = testing.treasury("cg2-o1");
    val o2 = testing.treasury("cg2-o2");
    val fw = testing.treasury("cg2-fw");
    val sup = testing.treasury("cg2-sup");
    val stranger = testing.treasury("cg2-stranger");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));
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
    val sup = testing.treasury("cg3-sup");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));
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
    val sup = testing.treasury("cg4-sup");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));
    expect(escrow.sendText(o1.address, "cancel_swap", ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(
        escrow.sendText(o1.address, "deploy_fee", ton("0.05")),
    ).toHaveFailedTx({ to: escrow.address, exitCode: Errors.AlreadyFinalized });
}

// remove_assert on the handleEmergencyCollect phase gate: emergency_collect_assets after the terminal state.
get fun `test emergency_collect after cancel rejected 410`() {
    val o1 = testing.treasury("cg5-o1");
    val o2 = testing.treasury("cg5-o2");
    val fw = testing.treasury("cg5-fw");
    val sup = testing.treasury("cg5-sup");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));
    expect(escrow.sendText(o1.address, "cancel_swap", ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(
        escrow.sendText(sup.address, "emergency_collect_assets", ton("0.3")),
    ).toHaveFailedTx({ to: escrow.address, exitCode: Errors.AlreadyFinalized });
}

// remove_assert on the handleEmergencyReturn phase gate: emergency_return_assets after the terminal state.
get fun `test emergency_return after cancel rejected 410`() {
    val o1 = testing.treasury("cg6-o1");
    val o2 = testing.treasury("cg6-o2");
    val fw = testing.treasury("cg6-fw");
    val sup = testing.treasury("cg6-sup");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));
    expect(escrow.sendText(o1.address, "cancel_swap", ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(
        escrow.sendText(sup.address, "emergency_return_assets", ton("0.3")),
    ).toHaveFailedTx({ to: escrow.address, exitCode: Errors.AlreadyFinalized });
}

// ── force_deliver ──

// remove_assert on the handleForceDeliver IDLE gate: force_deliver while dist.mode == IDLE.
// Without this gate, the supervisor could "force delivery" on a deal where no distribution is running.
get fun `test force_deliver when distribution idle rejected 410`() {
    val o1 = testing.treasury("cg7-o1");
    val o2 = testing.treasury("cg7-o2");
    val fw = testing.treasury("cg7-fw");
    val sup = testing.treasury("cg7-sup");
    val nft = deployNft(o1, 95101);
    var cfg = makeBasicConfig(o1, o2, fw, sup);
    var n1: map<uint16, address> = [];
    n1.set(0, nft);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    val escrow = deployEscrow(o1, cfg);
    // The deal is ACTIVE, distribution has not started → dist.mode == DIST_IDLE.
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(
        sendForceDeliverCg(sup.address, escrow.address, 0, false, ton("0.1")),
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
    val sup = testing.treasury("cg8-sup");
    val nftA = deployNft(o1, 95201);
    val nftB = deployNft(o1, 95202);
    var cfg = makeBasicConfig(o1, o2, fw, sup);
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
    val sup = testing.treasury("cg9-sup");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));
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

// ── DUPLICATE NFT DEPOSIT ──
// Modeling a duplicate (asset.received already true) cannot go through
// cancel: after cancel the phase is CANCELLED and acceptance is rejected by
// the PHASE gate (`phase != ACTIVE && != SETUP` → returnForeignNft), never
// reaching the duplicate check.
//
// The working path: supervisor `rescue_nft` (no phase gate, handleRescueNft)
// moves an already-ACCEPTED asset to the supervisor while the deal stays
// ACTIVE and `asset.received` in storage stays true. Sending the same NFT to
// the escrow again lands exactly in the duplicate branch
// (`if (asset.received)` → returnForeignNft).
get fun `test duplicate: same NFT sent back to escrow is returned, not double-counted`() {
    val o1 = testing.treasury("cgA-o1");
    val o2 = testing.treasury("cgA-o2");
    val fw = testing.treasury("cgA-fw");
    val sup = testing.treasury("cgA-sup");
    val nftA = deployNft(o1, 95301);
    var cfg = makeBasicConfig(o1, o2, fw, sup);
    var n1: map<uint16, address> = [];
    n1.set(0, nftA);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    val escrow = deployEscrow(o1, cfg);

    // 1) An ordinary deposit: slot 0 is accepted.
    expect(sendNftToEscrow(o1, nftA, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nftA)).toEqual(escrow.address);
    val (r1, _) = escrow.receivedCounts();
    expect(r1).toEqual(1);

    // 2) The supervisor moves the asset out (rescue, no phase gate) — the deal stays ACTIVE.
    expect(
        escrow.sendRescueNft(sup.address, nftA, { value: ton("0.1") }),
    ).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nftA)).toEqual(sup.address);
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);

    // 3) DUPLICATE: the same NFT is sent to the escrow again (phase is
    //    still ACTIVE, the slot is marked received) → the duplicate branch
    //    must RETURN it to its sender.
    expect(sendNftToEscrow(sup, nftA, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nftA)).toEqual(sup.address); // returned, did not stay at the escrow

    // 4) THE MAIN POINT: no double-counting — side 1's counter is still 1.
    val (r1After, _) = escrow.receivedCounts();
    expect(r1After).toEqual(1);
}

// ── MANUAL execute_swap: precondition gates ──
// handleExecuteSwap is the only path where owner1 forces execution manually.
// These tests pin the rejection when side 2's preconditions are NOT met.

// remove_assert: gram2Received >= gram2Amount → 421.
get fun `test manual execute_swap without side2 GRAM rejected 421`() {
    val o1 = testing.treasury("cgB-o1");
    val o2 = testing.treasury("cgB-o2");
    val fw = testing.treasury("cgB-fw");
    val sup = testing.treasury("cgB-sup");
    var cfg = makeBasicConfig(o1, o2, fw, sup);
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
    val sup = testing.treasury("cgC-sup");
    val nft1 = deployNft(o1, 95401);
    val nft2 = deployNft(o2, 95402);
    var cfg = makeBasicConfig(o1, o2, fw, sup);
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
    val sup = testing.treasury("cgD-sup");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));
    expect(escrow.sendText(o1.address, "cancel_swap", ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(
        escrow.sendText(o1.address, "execute_swap", ton("0.1")),
    ).toHaveFailedTx({ to: escrow.address, exitCode: Errors.AlreadyFinalized });
}
