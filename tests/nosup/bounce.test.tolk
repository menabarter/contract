// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// A bounced delivery marks the asset claimable and never stalls distribution.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "nosup_helpers"

// Opcodes onBouncedMessage dispatches on, kept in sync with the structs
// they name: NftTransfer/JettonTransfer (contracts/messages.tolk) are the
// two it acts on; ContinueDistribution (contracts/nosup/messages.tolk) is
// used below as an example of an opcode it must ignore.
const OP_NFT_TRANSFER = 0x5fcc3d14
const OP_CONTINUE_DISTRIBUTION = 0x6d5f0004

get fun `test fast-path bounce marks asset claimable and deal is DONE`() {
    val f = setup1x1("bn-fast", 61001);
    setReject(f.o1.address, f.nft1, true);
    val res = f.escrow.sendText(f.o2.address, "service_fee_owner2", SERVICE_FEE);
    expect(res).toHaveBouncedTx({ to: f.escrow.address });
    expect(f.escrow.phase()).toEqual(PHASE_DONE);
    expect(readMockOwner(f.nft1)).toEqual(f.escrow.address);
    expect(readMockOwner(f.nft2)).toEqual(f.o1.address);
    expect(f.escrow.assetStatus(0)).toEqual((true, true, 1));
    expect(f.escrow.assetStatus(1)).toEqual((true, false, 0));
    val claimable = f.escrow.claimableAssets();
    expect(claimable.exists(0)).toEqual(true);
    expect(claimable.exists(1)).toEqual(false);
}

get fun `test batched bounce does not stall distribution`() {
    val o1 = testing.treasury("bn-batch-o1");
    val o2 = testing.treasury("bn-batch-o2");
    val fw = testing.treasury("bn-batch-fw");
    var nfts1: map<uint16, address> = [];
    var i = 0;
    while (i < 60) {
        nfts1.set(i as uint16, deployNft(o1, 62000 + i));
        i += 1;
    }
    var nfts2: map<uint16, address> = [];
    var j = 0;
    while (j < 60) {
        nfts2.set(j as uint16, deployNft(o2, 63000 + j));
        j += 1;
    }
    var cfg = makeBasicConfig(o1, o2, fw);
    cfg.nfts1 = nfts1;
    cfg.nfts1Count = 60;
    cfg.nfts2 = nfts2;
    cfg.nfts2Count = 60;
    val escrow = deployEscrowMidDistribution(o1, cfg, 0, DIST_EXECUTE);
    setReject(o1.address, nfts1.mustGet(5), true);
    val res = escrow.sendText(o1.address, "kick", ton("5"));
    // The rejected NFT's own transfer fails and bounces (exit 999); the
    // escrow's own transaction in this chain must still succeed.
    expect(res).toHaveBouncedTx({ to: escrow.address });
    expect(res).toNotHaveTx({ to: escrow.address, success: false });
    expect(escrow.phase()).toEqual(PHASE_DONE);
    expect(escrow.distributionProgress()).toEqual((DIST_IDLE, 120));
    expect(escrow.assetStatus(5)).toEqual((true, true, 1));
    expect(readMockOwner(nfts1.mustGet(5))).toEqual(escrow.address);
    expect(readMockOwner(nfts1.mustGet(6))).toEqual(o2.address);
}

get fun `test cancel bounce marks asset claimable`() {
    val o1 = testing.treasury("bn-can-o1");
    val o2 = testing.treasury("bn-can-o2");
    val fw = testing.treasury("bn-can-fw");
    val nft = deployNft(o1, 64001);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, nft);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(sendNftToEscrow(o1, nft, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    setReject(o1.address, nft, true);
    val res = escrow.sendText(o1.address, "cancel_swap", ton("0.1"));
    expect(res).toHaveBouncedTx({ to: escrow.address });
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(escrow.assetStatus(0)).toEqual((true, true, 1));
}

get fun `test bounce with out-of-range queryId is ignored`() {
    // Reuses the completed-deal setup from the opcode-guard test below:
    // op/sentinel/phase/received would all let a bounce through here — only
    // the range check can be what stops queryId == assetsCount (one past
    // the registry's last valid index).
    val f = setup1x1("bn-oor", 70001);
    expect(
        f.escrow.sendText(f.o2.address, "service_fee_owner2", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_DONE);
    val from = testing.treasury("bn-oor-src");
    val res = injectBounce(from.address, f.escrow.address, OP_NFT_TRANSFER, 2); // assetsCount == 2
    expect(res.ranWithoutThrow()).toEqual(true);
    expect(f.escrow.assetStatus(0)).toEqual((true, false, 0));
    expect(f.escrow.assetStatus(1)).toEqual((true, false, 0));
    expect(f.escrow.claimableAssets().isEmpty()).toEqual(true);
}

get fun `test bounce with the reserved sentinel queryId is ignored`() {
    // Same setup as the out-of-range test above, so op/phase/received would
    // all let a bounce through. NOT an isolation of the sentinel guard from
    // the range guard: 0xFFFE is always >= this (or any real) assetsCount,
    // so the range check also rejects this input. This test only pins that
    // a sentinel queryId never marks an asset claimable, not which specific
    // guard is responsible.
    val f = setup1x1("bn-sent", 70101);
    expect(
        f.escrow.sendText(f.o2.address, "service_fee_owner2", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_DONE);
    val from = testing.treasury("bn-sent-src");
    val res = injectBounce(from.address, f.escrow.address, OP_NFT_TRANSFER, QUERY_ID_NON_ASSET);
    expect(res.ranWithoutThrow()).toEqual(true);
    expect(f.escrow.assetStatus(0)).toEqual((true, false, 0));
    expect(f.escrow.assetStatus(1)).toEqual((true, false, 0));
    expect(f.escrow.claimableAssets().isEmpty()).toEqual(true);
}

get fun `test bounce of a non-transfer opcode is ignored even for an otherwise-valid index`() {
    // A deal that completes normally (no reject at all): index 0 ends up
    // received, phase DONE — every guard except the opcode check would let
    // this bounce through, so only that check can be what stops it.
    val f = setup1x1("bn-op", 69001);
    expect(
        f.escrow.sendText(f.o2.address, "service_fee_owner2", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_DONE);
    val from = testing.treasury("bn-op-src");
    val res = injectBounce(from.address, f.escrow.address, OP_CONTINUE_DISTRIBUTION, 0);
    expect(res.ranWithoutThrow()).toEqual(true);
    expect(f.escrow.assetStatus(0)).toEqual((true, false, 0));
    expect(f.escrow.claimableAssets().isEmpty()).toEqual(true);
}

get fun `test bounce of a received asset outside EXECUTING DONE or CANCELLED is ignored`() {
    val o1 = testing.treasury("bn-actv-o1");
    val o2 = testing.treasury("bn-actv-o2");
    val fw = testing.treasury("bn-actv-fw");
    val nft1 = deployNft(o1, 67001);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, nft1);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    val escrow = deployEscrow(o1, cfg);
    // Side 1's NFT is received, but neither side has paid its service fee —
    // canAutoExecute stays false, so the deal is still ACTIVE, not one of
    // the phases asset transfers leave it in.
    expect(sendNftToEscrow(o1, nft1, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    val from = testing.treasury("bn-actv-src");
    val res = injectBounce(from.address, escrow.address, OP_NFT_TRANSFER, 0);
    expect(res.ranWithoutThrow()).toEqual(true);
    expect(escrow.assetStatus(0)).toEqual((true, false, 0));
    expect(escrow.claimableAssets().isEmpty()).toEqual(true);
}

get fun `test bounce of an unreceived index is ignored, a received index in the same phase becomes claimable`() {
    val o1 = testing.treasury("bn-canc-o1");
    val o2 = testing.treasury("bn-canc-o2");
    val fw = testing.treasury("bn-canc-fw");
    val nft0 = deployNft(o1, 68001);
    val nft1 = deployNft(o1, 68002);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, nft0);
    n1.set(1, nft1);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 2;
    val escrow = deployEscrow(o1, cfg);
    // Only index 0 is ever deposited; cancelling leaves index 1 registered
    // but never received — a real CANCELLED state with an in-range,
    // unreceived index, not a synthetic one.
    expect(sendNftToEscrow(o1, nft0, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "cancel_swap", ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);

    val from = testing.treasury("bn-canc-src");

    // Index 1: in range, CANCELLED phase, but never received -> ignored.
    val ignored = injectBounce(from.address, escrow.address, OP_NFT_TRANSFER, 1);
    expect(ignored.ranWithoutThrow()).toEqual(true);
    expect(escrow.assetStatus(1)).toEqual((false, false, 0));
    expect(escrow.claimableAssets().isEmpty()).toEqual(true);

    // Positive control: index 0, same phase, but received -> proves the
    // injection mechanism itself reaches onBouncedMessage and its normal path.
    val applied = injectBounce(from.address, escrow.address, OP_NFT_TRANSFER, 0);
    expect(applied.ranWithoutThrow()).toEqual(true);
    expect(escrow.assetStatus(0)).toEqual((true, true, 1));
    expect(escrow.claimableAssets().exists(0)).toEqual(true);
}

// The `a.bounces < 15` cap on the diagnostic bounce counter: without it,
// the 16th bounce of the SAME asset would try to store 16 into a uint4
// field and abort the transaction instead of leaving the counter pinned at
// its maximum. Delivers repeated synthetic bounces for one registry index
// well past the cap and checks every one of them completes without
// throwing, with the counter never moving past 15.
get fun `test bounce counter saturates at 15 and never overflows`() {
    val o1 = testing.treasury("bn-sat-o1");
    val o2 = testing.treasury("bn-sat-o2");
    val fw = testing.treasury("bn-sat-fw");
    val nft1 = deployNft(o1, 96301);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, nft1);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(sendNftToEscrow(o1, nft1, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "cancel_swap", ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);

    val from = testing.treasury("bn-sat-src");
    var i = 0;
    while (i < 20) {
        val res = injectBounce(from.address, escrow.address, OP_NFT_TRANSFER, 0);
        expect(res.ranWithoutThrow()).toEqual(true);
        i += 1;
    }
    expect(escrow.assetStatus(0)).toEqual((true, true, 15));
}

// The `remainingBitsCount() < 96` length gate: without it, a bounced body
// shorter than op(32)+queryId(64) would be read past its end and abort the
// transaction, instead of being silently ignored like any other bounce
// this handler does not recognize.
get fun `test bounce with a body shorter than op plus queryId is ignored`() {
    val f = setup1x1("bn-short", 71701);
    expect(
        f.escrow.sendText(f.o2.address, "service_fee_owner2", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_DONE);

    val from = testing.treasury("bn-short-src");
    // Bounce prefix + a 32-bit op only, no queryId at all: 32 bits remain
    // after skipBouncedPrefix, well under the 96 the handler requires.
    val body = beginCell().storeUint(0xFFFFFFFF, 32).storeUint(OP_NFT_TRANSFER, 32).endCell();
    val msg = createMessage({
        bounce: BounceMode.NoBounce,
        value: ton("0.05"),
        dest: f.escrow.address,
        body,
    }).bounced();
    val res = testing.processSingleTraceStep(from.address, msg);
    expect(res.ranWithoutThrow()).toEqual(true);
    expect(f.escrow.assetStatus(0)).toEqual((true, false, 0));
    expect(f.escrow.claimableAssets().isEmpty()).toEqual(true);
}

get fun `test bounce handler gas stays small`() {
    val f = setup1x1("bn-gas", 66001);
    setReject(f.o1.address, f.nft1, true);
    val res = f.escrow.sendText(f.o2.address, "service_fee_owner2", SERVICE_FEE);
    // Gas of the escrow's bounce transaction (the rejected nft1 delivery).
    val bounceGas = res.getUsedGas({ to: f.escrow.address, bounced: true });
    expect(bounceGas > 0).toEqual(true);
    expect(bounceGas).toBeLess(30000);
}
