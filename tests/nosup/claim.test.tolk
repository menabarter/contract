// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Pull delivery of deal assets with claim_asset.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/messages"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/messages"
import "@contracts/nosup/storage"
import "nosup_helpers"

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

// The `a.received` check in handleClaimAsset's NFT branch: without it,
// claim_asset could be called on a registry slot whose asset was never
// deposited at all. Built with a real CANCELLED deal (not a synthetic
// state) where one registered NFT slot is never deposited, so the slot is
// in-range, in a valid claim phase, and claimed by its rightful depositor —
// every other guard would let this claim through.
get fun `test claim of a never-received NFT slot rejected NotClaimable`() {
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
    // Index 1: in range, CANCELLED phase (a valid claim phase), sender is the
    // rightful depositor — but the asset was never received.
    expect(
        sendClaim(o1.address, escrow.address, 1, ton("0.1")),
    ).toHaveFailedTx({ to: escrow.address, exitCode: Errors.NotClaimable });
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
