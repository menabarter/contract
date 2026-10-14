// GENERATED from tests/nosup/claim.test.tolk by ts-tests/gen-v2-tests.ts — edit the source, then run npm run gen:v2.
// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Pull delivery of deal assets with claim_asset.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/messages"
import "@wrappers/SwapEscrowV2.gen"
import "@contracts/shared/messages"
import "@contracts/shared/types"
import "@contracts/v2/messages"
import "@contracts/v2/storage"
import "v2_helpers"

// TEP-74 transfer opcode (contracts/messages.tolk) — used to build a
// synthetic jetton bounce with injectBounce, the same technique
// bounce.test.tolk uses for NFT transfers.
const OP_JETTON_TRANSFER = 0x0f8a7ea5

fun bouncedDone(tag: string, seed: int): Deal1x1 {
    val f = setup1x1(tag, seed);
    setReject(f.o1.address, f.nft1, true);
    expect(f.escrow.sendText(f.o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveBouncedTx({
        to: f.escrow.address,
    });
    expect(f.escrow.phase()).toEqual(PHASE_DONE);
    return f;
}

get fun `test recipient claims a bounced NFT after DONE`() {
    val f = bouncedDone("cl-ok", 71001);
    setReject(f.o1.address, f.nft1, false);
    // After DONE the dust sweep emptied the escrow; claim needs no balance.
    expect(sendClaim(f.o2.address, f.escrow.address, 0, ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(readMockOwner(f.nft1)).toEqual(f.o2.address);
    expect(f.escrow.assetStatus(0)).toEqual((true, false, 1));
}

get fun `test depositor cannot claim after DONE`() {
    val f = bouncedDone("cl-dep", 71101);
    setReject(f.o1.address, f.nft1, false);
    expect(sendClaim(f.o1.address, f.escrow.address, 0, ton("0.1"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.NotRecipient,
    });
    expect(readMockOwner(f.nft1)).toEqual(f.escrow.address);
}

get fun `test stranger cannot claim`() {
    val f = bouncedDone("cl-str", 71201);
    val stranger = testing.treasury("cl-str-x");
    expect(sendClaim(stranger.address, f.escrow.address, 0, ton("0.1"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.NotRecipient,
    });
}

get fun `test claim re-marks when the NFT still rejects, then succeeds`() {
    val f = bouncedDone("cl-again", 71301);
    val res = sendClaim(f.o2.address, f.escrow.address, 0, ton("0.1"));
    expect(res).toHaveBouncedTx({ to: f.escrow.address });
    expect(f.escrow.assetStatus(0)).toEqual((true, true, 2));
    setReject(f.o1.address, f.nft1, false);
    expect(sendClaim(f.o2.address, f.escrow.address, 0, ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(readMockOwner(f.nft1)).toEqual(f.o2.address);
}

get fun `test claim of an already delivered NFT is harmless`() {
    val f = bouncedDone("cl-deliv", 71401);
    // Asset 1 (nft2) was delivered to o1 normally; o1 is its rightful recipient.
    val res = sendClaim(f.o1.address, f.escrow.address, 1, ton("0.1"));
    expect(res).toHaveBouncedTx({ to: f.escrow.address });
    expect(readMockOwner(f.nft2)).toEqual(f.o1.address);
    // a.claimable is false here (nft2 was delivered normally, never bounced):
    // the `if (a.claimable)` branch must be skipped entirely, so this
    // transaction does no extra assets.set()/save() write. Measured:
    // 7388 gas with the write skipped, 10059 gas if it always runs — the
    // ceiling sits with headroom above the real cost and below the forced
    // write's cost.
    val claimGas = res.getUsedGas({ to: f.escrow.address, bounced: false });
    expect(claimGas > 0).toEqual(true);
    expect(claimGas).toBeLess(9000);
}

get fun `test claim of an NFT not yet reached by the batch cursor is rejected`() {
    val o1 = testing.treasury("cl-cur-o1");
    val o2 = testing.treasury("cl-cur-o2");
    val fw = testing.treasury("cl-cur-fw");
    var nfts1: map<uint16, address> = [];
    var i = 0;
    while (i < 4) {
        nfts1.set(i as uint16, deployNft(o1, 72000 + i));
        i += 1;
    }
    var cfg = makeBasicConfig(o1, o2, fw);
    cfg.nfts1 = nfts1;
    cfg.nfts1Count = 4;
    val escrow = deployEscrowMidDistribution(o1, cfg, 2, DIST_EXECUTE);
    expect(sendClaim(o2.address, escrow.address, 3, ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: Errors.NotClaimable,
    });
    // Index 2 IS the cursor: `idx < cursor` is strict, so the index the
    // cursor is currently sitting on is not yet behind it either.
    expect(sendClaim(o2.address, escrow.address, 2, ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: Errors.NotClaimable,
    });
    // Index 1 is behind the cursor: the NFT is still owned by the escrow in
    // this fixture, so the claim delivers it.
    expect(sendClaim(o2.address, escrow.address, 1, ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nfts1.mustGet(1))).toEqual(o2.address);
}

get fun `test claim errors: index, value, phase`() {
    val f = bouncedDone("cl-err", 71501);
    expect(sendClaim(f.o2.address, f.escrow.address, 9, ton("0.1"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.BadAssetIndex,
    });
    expect(sendClaim(f.o2.address, f.escrow.address, 0, ton("0.01"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.InsufficientBalance,
    });

    val a = setup1x1("cl-err-active", 71601);
    expect(sendClaim(a.o2.address, a.escrow.address, 0, ton("0.1"))).toHaveFailedTx({
        to: a.escrow.address,
        exitCode: Errors.AlreadyFinalized,
    });
}

// In CANCELLED a never-received slot may be claimed by its side owner: the
// item refuses a transfer from an escrow that does not own it, so the claim
// moves nothing and the claimer loses only the attached value.
get fun `test claim of a never-received NFT slot after cancel moves nothing`() {
    val o1 = testing.treasury("cl-nr-o1");
    val o2 = testing.treasury("cl-nr-o2");
    val fw = testing.treasury("cl-nr-fw");
    val nft0 = deployNft(o1, 96201);
    val nft1 = deployNft(o1, 96202);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, nft0);
    n1.set(1, nft1);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 2;
    val escrow = deployEscrow(o1, cfg);
    // Only index 0 is ever deposited; cancelling leaves index 1 registered
    // but never received.
    expect(sendNftToEscrow(o1, nft0, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "cancel_swap", ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    // Index 1: in range, CANCELLED phase, sender is the rightful depositor —
    // but the escrow never owned nft1, so its transfer is refused (401) and
    // the claim only bounces.
    val res = sendClaim(o1.address, escrow.address, 1, ton("0.1"));
    expect(res).toHaveBouncedTx({ to: escrow.address });
    expect(readMockOwner(nft1)).toEqual(o1.address);
}

// An NFT sent to the deal with a forward too small to notify the escrow belongs
// to the escrow but was never recorded. After cancel its side owner can pull
// it back; the item itself refuses the transfer if the escrow does not own it.
get fun `test an unrecorded NFT is claimed back after cancel`() {
    val o1 = testing.treasury("cl-unrec-o1");
    val o2 = testing.treasury("cl-unrec-o2");
    val fw = testing.treasury("cl-unrec-fw");
    val x = deployNft(o1, 81001);
    val y = deployNft(o2, 81002);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, x);
    var b: map<uint16, address> = [];
    b.set(0, y);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = 1;
    val escrow = deployEscrow(o1, cfg);
    sendNftToEscrow(o1, x, escrow.address, 1, 0); // one nanoton: never recorded
    expect(escrow.receivedCounts()).toEqual((0, 0));
    expect(readMockOwner(x)).toEqual(escrow.address);
    val (_req, attach) = escrow.cancelCost();
    expect(escrow.sendText(o1.address, "cancel_swap", attach)).toHaveAllSuccessfulTxs();
    expect(sendClaim(o1.address, escrow.address, 0, ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(readMockOwner(x)).toEqual(o1.address);
}

// Outside cancel an unrecorded slot stays unclaimable: the recipient there is
// the counterparty, who never deposited it.
get fun `test an unrecorded NFT slot is not claimable while executing`() {
    val o1 = testing.treasury("cl-exec-o1");
    val o2 = testing.treasury("cl-exec-o2");
    val fw = testing.treasury("cl-exec-fw");
    val x = deployNft(o1, 81101);
    val y = deployNft(o2, 81102);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, x);
    var b: map<uint16, address> = [];
    b.set(0, y);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = 1;
    var st = buildInitialStorage(cfg);
    st.phase = PHASE_EXECUTING;
    st.dist = DistState {
        mode: DIST_EXECUTE,
        cursor: 0,
    }.toCell();
    var s1 = st.assets.mustGet(1);
    s1.received = true;
    st.assets.set(1, s1);
    st.received2Count = 1;
    val escrow = SwapEscrowV2.fromStorage(st);
    expect(
        net.send(
            o1.address,
            createMessage({
                bounce: BounceMode.NoBounce,
                value: ton("1"),
                dest: { stateInit: escrow.stateInit! },
                body: Excesses { queryId: 0 },
            }),
        ),
    ).toHaveSuccessfulDeploy({ to: escrow.address });
    expect(sendClaim(o2.address, escrow.address, 0, ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: Errors.NotClaimable,
    });
}

get fun `test cancelled deal: depositor claims own bounced NFT`() {
    val o1 = testing.treasury("cl-can-o1");
    val o2 = testing.treasury("cl-can-o2");
    val fw = testing.treasury("cl-can-fw");
    val nft = deployNft(o1, 73001);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, nft);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(sendNftToEscrow(o1, nft, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    setReject(o1.address, nft, true);
    expect(escrow.sendText(o1.address, "cancel_swap", ton("0.1"))).toHaveBouncedTx({
        to: escrow.address,
    });
    setReject(o1.address, nft, false);
    expect(sendClaim(o2.address, escrow.address, 0, ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: Errors.NotRecipient,
    });
    expect(sendClaim(o1.address, escrow.address, 0, ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nft)).toEqual(o1.address);
}

get fun `test unmarked jetton is not claimable`() {
    val f = jdSetup("cl-j0", 74);
    expect(
        f.escrow.sendText(f.o1.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(
        f.escrow.sendText(f.o2.address, "service_fee_owner2", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendJettonTransfer2(
            f.o1,
            f.minter,
            f.escrow.address,
            ton("100"),
            ton("0.2"),
            0,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendJettonTransfer2(
            f.o2,
            f.minter,
            f.escrow.address,
            ton("50"),
            ton("0.2"),
            1,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_DONE);
    // Delivered normally: no bounce, no mark — a claim must not send a second transfer.
    expect(sendClaim(f.o2.address, f.escrow.address, 0, ton("0.1"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.NotClaimable,
    });
    expect(readJettonBalance(f.minter, f.escrow.address)).toEqual(0);
}

// Jetton claim after an injected bounce.
//
// jetton_wallet_mock.tolk has no switch to reject an outgoing transfer: its
// only checks are TEP-74 owner/peer identity and balance, both of which pass
// under any organically-reachable state here (the escrow is always the
// genuine owner of its own wallet, and deposits always sum to exactly what
// distribution sends). A from-scratch Storage (the deployEscrowMidDistribution
// style) also cannot set a.jettonWallet to a wallet that genuinely accepts
// the escrow's transfer: the wallet's on-chain address bakes in its owner
// (unlike an NFT item's address, which is independent of its current owner),
// so the escrow's OWN address and its wallet's address would need to be
// mutually derived from each other — a real fixed point with no closed-form
// construction, and the wallet mock has no post-deploy owner-reassignment op
// (unlike SetNftOwner for NFTs) to break the cycle after the fact.
//
// So this test uses a real deal (jdSetup, genuine TEP-89 resolution: the
// jettonWallet address is correct with zero circularity because the escrow
// resolves it from its own contract.getAddress() at runtime) and delivers
// the completing service fee with testing.processSingleTraceStep instead of
// the normal recursive send. That runs the escrow's auto-execute
// transaction — phase flips to DONE and both outgoing jetton transfers are
// queued as actions of that ONE transaction — but leaves those two
// transfers undelivered, so the escrow's real, correctly-owned wallet keeps
// its full balance. injectBounce then delivers a SYNTHETIC bounce for asset
// 0's queryId (the same mechanism bounce.test.tolk already relies on for
// NFTs) — no real transfer to the wallet ever bounces here — marking the
// asset claimable without ever having actually sent it. The subsequent claim
// is a completely ordinary send through the real wallet, so it genuinely
// moves tokens and its success is not weakened in any way.
get fun `test jetton claim after an injected bounce`() {
    val f = jdSetup("cl-jbounce", 75001);
    expect(
        sendJettonTransfer2(
            f.o1,
            f.minter,
            f.escrow.address,
            ton("100"),
            ton("0.2"),
            0,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendJettonTransfer2(
            f.o2,
            f.minter,
            f.escrow.address,
            ton("50"),
            ton("0.2"),
            1,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(
        f.escrow.sendText(f.o1.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_ACTIVE);

    val feeMsg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        value: SERVICE_FEE,
        dest: f.escrow.address,
        body: textBody("service_fee_owner2"),
    });
    val feeRes = testing.processSingleTraceStep(f.o2.address, feeMsg);
    expect(feeRes.ranWithoutThrow()).toEqual(true);
    expect(f.escrow.phase()).toEqual(PHASE_DONE);
    expect(f.escrow.assetStatus(0)).toEqual((true, false, 0));
    // Untouched: the two outgoing transfers queued by executeSwapSingleTx
    // above were never actually delivered.
    expect(readJettonBalance(f.minter, f.escrow.address)).toEqual(ton("150"));

    // Same-minter tokens are already sitting on the escrow's wallet at this
    // point, but asset 0 is not marked claimable yet — the wallet holding
    // enough tokens is not by itself sufficient to claim.
    expect(sendClaim(f.o2.address, f.escrow.address, 0, ton("0.2"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.NotClaimable,
    });

    // The bounce is injected from an unrelated treasury address, not from the
    // jetton wallet itself: onBouncedMessage only reads op/queryId from the
    // bounced body. On-chain no contract can produce such a message — the
    // action phase forces `bounced` to false and rewrites `src` — so this
    // shortcut exists only in the emulator, which builds the message directly.
    val src = testing.treasury("cl-jbounce-src");
    val bounced = injectBounce(src.address, f.escrow.address, OP_JETTON_TRANSFER, 0);
    expect(bounced.ranWithoutThrow()).toEqual(true);
    expect(f.escrow.assetStatus(0)).toEqual((true, true, 1));

    expect(sendClaim(f.o2.address, f.escrow.address, 0, ton("0.2"))).toHaveAllSuccessfulTxs();
    // o2 started with 500, deposited its own 50 (asset 1), then claimed
    // asset 0's 100: 500 - 50 + 100 = 550.
    expect(readJettonBalance(f.minter, f.o2.address)).toEqual(ton("550"));
    expect(f.escrow.assetStatus(0)).toEqual((true, false, 1));

    expect(sendClaim(f.o2.address, f.escrow.address, 0, ton("0.2"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.NotClaimable,
    });
}

// Cross-side duplicate NFT address: the registry does not forbid listing the
// same item on both sides. Case 1 — the escrow is holding the item because
// side 1's recorded return bounced; side 2 also lists the same address, never
// deposited there. Without the cross-side check, side 2's owner could claim
// that unrecorded slot and take the item meant for side 1.
get fun `test cross-side duplicate blocks an unrecorded claim: recorded on one side, unrecorded on the other`() {
    val o1 = testing.treasury("cl-dup1-o1");
    val o2 = testing.treasury("cl-dup1-o2");
    val fw = testing.treasury("cl-dup1-fw");
    val x = deployNft(o1, 82001);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, x);
    var n2: map<uint16, address> = [];
    n2.set(0, x); // same address again, on side 2 — never deposited there
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    cfg.nfts2 = n2;
    cfg.nfts2Count = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(sendNftToEscrow(o1, x, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    setReject(o1.address, x, true);
    expect(escrow.sendText(o1.address, "cancel_swap", ton("0.1"))).toHaveBouncedTx({
        to: escrow.address,
    });
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    // The item stops rejecting (the escrow is still its owner — the earlier
    // return never actually delivered).
    setReject(o1.address, x, false);
    // Slot 1 (side 2) lists the same address but was never deposited there —
    // the escrow is holding x for side 1's bounced return, not for side 2.
    expect(sendClaim(o2.address, escrow.address, 1, ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: Errors.NotClaimable,
    });
    expect(readMockOwner(x)).toEqual(escrow.address);
    // Side 1's own (recorded) slot is unaffected by the check and still delivers.
    expect(sendClaim(o1.address, escrow.address, 0, ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(readMockOwner(x)).toEqual(o1.address);
}

// Case 2 — same duplicate, but inside a batch-cancel mid-state: the cursor
// sits exactly on the recorded slot (not yet behind it, so that slot is
// correctly NotClaimable on its own), while the unrecorded duplicate on the
// other side must also be refused rather than slipping through.
get fun `test cross-side duplicate blocks an unrecorded claim: batch-cancel cursor on the recorded slot`() {
    val o1 = testing.treasury("cl-dup2-o1");
    val o2 = testing.treasury("cl-dup2-o2");
    val fw = testing.treasury("cl-dup2-fw");
    val x = deployNft(o1, 82101);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, x);
    var n2: map<uint16, address> = [];
    n2.set(0, x);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    cfg.nfts2 = n2;
    cfg.nfts2Count = 1;
    var st = buildInitialStorage(cfg);
    st.phase = PHASE_CANCELLED;
    st.dist = DistState {
        mode: DIST_CANCEL,
        cursor: 0,
    }.toCell();
    var s0 = st.assets.mustGet(0);
    s0.received = true;
    st.assets.set(0, s0);
    st.received1Count = 1;
    val escrow = SwapEscrowV2.fromStorage(st);
    // Ownership of the mock NFT moves to the escrow (SetNftOwner is test-only).
    expect(
        net.send(
            o1.address,
            createMessage({
                bounce: BounceMode.NoBounce,
                value: ton("0.05"),
                dest: x,
                body: SetNftOwner {
                    queryId: 0,
                    newOwner: escrow.address,
                },
            }),
        ),
    ).toHaveAllSuccessfulTxs();
    expect(
        net.send(
            o1.address,
            createMessage({
                bounce: BounceMode.NoBounce,
                value: ton("1"),
                dest: { stateInit: escrow.stateInit! },
                body: Excesses { queryId: 0 },
            }),
        ),
    ).toHaveSuccessfulDeploy({ to: escrow.address });
    // Slot 0 sits exactly at the cursor — `idx < cursor` is strict, so it is
    // correctly not yet claimable on its own terms.
    expect(sendClaim(o1.address, escrow.address, 0, ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: Errors.NotClaimable,
    });
    // Slot 1 (side 2, unrecorded) must not hand out the same item either.
    expect(sendClaim(o2.address, escrow.address, 1, ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: Errors.NotClaimable,
    });
    expect(readMockOwner(x)).toEqual(escrow.address);
}

// Case 3 — both duplicate slots are unrecorded (the item was sent with a
// forward too small to be recorded at all). Neither side can prove the item
// was meant for it, so both are refused rather than letting whichever side
// claims first win.
get fun `test cross-side duplicate blocks an unrecorded claim: both sides unrecorded`() {
    val o1 = testing.treasury("cl-dup3-o1");
    val o2 = testing.treasury("cl-dup3-o2");
    val fw = testing.treasury("cl-dup3-fw");
    val x = deployNft(o1, 82201);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, x);
    var n2: map<uint16, address> = [];
    n2.set(0, x);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    cfg.nfts2 = n2;
    cfg.nfts2Count = 1;
    val escrow = deployEscrow(o1, cfg);
    sendNftToEscrow(o1, x, escrow.address, 1, 0); // one nanoton: never recorded
    val (_req, attach) = escrow.cancelCost();
    expect(escrow.sendText(o1.address, "cancel_swap", attach)).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(sendClaim(o2.address, escrow.address, 1, ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: Errors.NotClaimable,
    });
    expect(readMockOwner(x)).toEqual(escrow.address);
    expect(sendClaim(o1.address, escrow.address, 0, ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: Errors.NotClaimable,
    });
    expect(readMockOwner(x)).toEqual(escrow.address);
}

// Guard: a duplicate address on the SAME side is not a cross-side duplicate
// and must not block a legitimate unrecorded claim — the escrow holding the
// item can only mean it belongs to that one shared owner either way.
get fun `test a same-side duplicate NFT address does not block a legitimate unrecorded claim`() {
    val o1 = testing.treasury("cl-dupsame-o1");
    val o2 = testing.treasury("cl-dupsame-o2");
    val fw = testing.treasury("cl-dupsame-fw");
    val x = deployNft(o1, 82301);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, x);
    n1.set(1, x); // same address twice, both on side 1 — harmless duplicate
    cfg.nfts1 = n1;
    cfg.nfts1Count = 2;
    val escrow = deployEscrow(o1, cfg);
    expect(sendNftToEscrow(o1, x, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    setReject(o1.address, x, true);
    expect(escrow.sendText(o1.address, "cancel_swap", ton("0.1"))).toHaveBouncedTx({
        to: escrow.address,
    });
    setReject(o1.address, x, false);
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    // Slot 1 lists the same address, never deposited there, but both slots
    // belong to side 1 — not a cross-side duplicate, so the claim proceeds
    // and genuinely delivers the item the escrow is still holding.
    expect(sendClaim(o1.address, escrow.address, 1, ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(readMockOwner(x)).toEqual(o1.address);
}

// Guard: outside cancel, an unrecorded slot stays unclaimable regardless of
// phase — DONE included, not just EXECUTING (already covered above).
get fun `test an unrecorded NFT slot is not claimable after DONE`() {
    val o1 = testing.treasury("cl-done-unrec-o1");
    val o2 = testing.treasury("cl-done-unrec-o2");
    val fw = testing.treasury("cl-done-unrec-fw");
    val x = deployNft(o1, 82401);
    val y = deployNft(o2, 82402);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, x);
    var b: map<uint16, address> = [];
    b.set(0, y);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = 1;
    var st = buildInitialStorage(cfg);
    st.phase = PHASE_DONE;
    st.dist = DistState {
        mode: DIST_IDLE,
        cursor: 0,
    }.toCell();
    var s1 = st.assets.mustGet(1);
    s1.received = true;
    st.assets.set(1, s1);
    st.received2Count = 1;
    val escrow = SwapEscrowV2.fromStorage(st);
    expect(
        net.send(
            o1.address,
            createMessage({
                bounce: BounceMode.NoBounce,
                value: ton("1"),
                dest: { stateInit: escrow.stateInit! },
                body: Excesses { queryId: 0 },
            }),
        ),
    ).toHaveSuccessfulDeploy({ to: escrow.address });
    expect(sendClaim(o2.address, escrow.address, 0, ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: Errors.NotClaimable,
    });
}
