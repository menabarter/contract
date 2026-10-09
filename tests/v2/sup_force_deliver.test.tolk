// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// ForceDeliver: the supervisor delivers a recorded asset whose push delivery
// did not land, with claim_asset's admission; fallback = true sends it to the
// supervisor instead of the recipient.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/messages"
import "@wrappers/SwapEscrowV2.gen"
import "@contracts/shared/messages"
import "@contracts/shared/types"
import "@contracts/v2/storage"
import "sup_helpers"
import "v2_helpers"

const OP_JETTON_TRANSFER = 0x0f8a7ea5

fun forceDeliver(
    from: address,
    escrow: address,
    idx: int,
    fallback: bool,
    value: coins,
): SendResultList {
    return net.send(
        from,
        createMessage({
            bounce: BounceMode.Only256BitsOfBody,
            value,
            dest: escrow,
            body: ForceDeliver {
                queryId: 0,
                assetIndex: idx as uint16,
                fallback,
            },
        }),
    );
}

// A DONE 1x1 deal whose delivery of nft1 to o2 bounced: nft1 is claimable.
fun bouncedDone(tag: string, seed: int): Deal1x1 {
    val f = setup1x1(tag, seed);
    setReject(f.o1.address, f.nft1, true);
    expect(f.escrow.sendText(f.o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveBouncedTx({
        to: f.escrow.address,
    });
    expect(f.escrow.phase()).toEqual(PHASE_DONE);
    expect(f.escrow.assetStatus(0)).toEqual((true, true, 1));
    return f;
}

get fun `test force_deliver(false) delivers a bounced NFT to its recipient`() {
    val f = bouncedDone("fd-1", 79401);
    setReject(f.o1.address, f.nft1, false);
    expect(
        forceDeliver(supAddr(), f.escrow.address, 0, false, ton("0.1")),
    ).toHaveAllSuccessfulTxs();
    expect(readMockOwner(f.nft1)).toEqual(f.o2.address);
    expect(f.escrow.assetStatus(0)).toEqual((true, false, 1));
}

get fun `test force_deliver(true) takes a bounced NFT to the supervisor`() {
    val f = bouncedDone("fd-2", 79411);
    setReject(f.o1.address, f.nft1, false);
    expect(forceDeliver(supAddr(), f.escrow.address, 0, true, ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(readMockOwner(f.nft1)).toEqual(supAddr());
    expect(f.escrow.assetStatus(0)).toEqual((true, false, 1));
}

// After cancel the recipient is the depositor.
get fun `test force_deliver(false) in CANCELLED delivers to the depositor`() {
    val o1 = testing.treasury("fd-3-o1");
    val o2 = testing.treasury("fd-3-o2");
    val fw = testing.treasury("fd-3-fw");
    val nft = deployNft(o1, 79421);
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
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    setReject(o1.address, nft, false);
    expect(forceDeliver(supAddr(), escrow.address, 0, false, ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nft)).toEqual(o1.address);
}

// An NFT delivered by force_deliver cannot be delivered again by claim_asset:
// the item refuses a transfer from an escrow that no longer owns it.
get fun `test force_deliver then claim_asset delivers an NFT once`() {
    val f = bouncedDone("fd-4n", 79431);
    setReject(f.o1.address, f.nft1, false);
    expect(forceDeliver(supAddr(), f.escrow.address, 0, true, ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(readMockOwner(f.nft1)).toEqual(supAddr());
    val res = sendClaim(f.o2.address, f.escrow.address, 0, ton("0.1"));
    expect(res).toHaveBouncedTx({ to: f.escrow.address });
    expect(readMockOwner(f.nft1)).toEqual(supAddr());
}

// A jetton is claimable only while marked; the first delivery clears the mark,
// so the other path gets 432.
get fun `test claim_asset then force_deliver delivers a jetton once`() {
    val f = jdSetup("fd-4j", 79441);
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
    // The completing fee executes, but its two jetton transfers are left
    // undelivered; a synthetic bounce then marks asset 0 claimable (the same
    // technique as claim.test.tolk's `jetton claim after an injected bounce`).
    val feeMsg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        value: SERVICE_FEE,
        dest: f.escrow.address,
        body: textBody("service_fee_owner2"),
    });
    expect(testing.processSingleTraceStep(f.o2.address, feeMsg).ranWithoutThrow()).toEqual(true);
    expect(f.escrow.phase()).toEqual(PHASE_DONE);
    val src = testing.treasury("fd-4j-src");
    expect(
        injectBounce(src.address, f.escrow.address, OP_JETTON_TRANSFER, 0).ranWithoutThrow(),
    ).toEqual(true);
    expect(f.escrow.assetStatus(0)).toEqual((true, true, 1));
    expect(sendClaim(f.o2.address, f.escrow.address, 0, ton("0.2"))).toHaveAllSuccessfulTxs();
    expect(f.escrow.assetStatus(0)).toEqual((true, false, 1));
    expect(forceDeliver(supAddr(), f.escrow.address, 0, true, ton("0.2"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.NotClaimable,
    });
}

// An NFT that was delivered normally: the item refuses the transfer and the
// attachment comes back with the bounce.
get fun `test force_deliver on a delivered NFT moves nothing`() {
    val f = bouncedDone("fd-5", 79451);
    // Asset 1 (nft2) went to o1 without a bounce.
    expect(readMockOwner(f.nft2)).toEqual(f.o1.address);
    val res = forceDeliver(supAddr(), f.escrow.address, 1, true, ton("0.1"));
    expect(res).toHaveBouncedTx({ to: f.escrow.address });
    expect(readMockOwner(f.nft2)).toEqual(f.o1.address);
}

get fun `test force_deliver gates`() {
    val active = setup1x1("fd-6a", 79461);
    expect(forceDeliver(supAddr(), active.escrow.address, 0, false, ton("0.1"))).toHaveFailedTx({
        to: active.escrow.address,
        exitCode: Errors.AlreadyFinalized,
    });
    val f = bouncedDone("fd-6", 79471);
    expect(forceDeliver(supAddr(), f.escrow.address, 9, false, ton("0.1"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.BadAssetIndex,
    });
    expect(forceDeliver(supAddr(), f.escrow.address, 0, false, ton("0.01"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.InsufficientBalance,
    });
    expect(forceDeliver(f.o2.address, f.escrow.address, 0, false, ton("0.1"))).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.NotSupervisor,
    });
    // An unmarked jetton (delivered normally) is not deliverable.
    val j = jdSetup("fd-6j", 79481);
    expect(
        j.escrow.sendText(j.o1.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(
        j.escrow.sendText(j.o2.address, "service_fee_owner2", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendJettonTransfer2(
            j.o1,
            j.minter,
            j.escrow.address,
            ton("100"),
            ton("0.2"),
            0,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendJettonTransfer2(
            j.o2,
            j.minter,
            j.escrow.address,
            ton("50"),
            ton("0.2"),
            1,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(j.escrow.phase()).toEqual(PHASE_DONE);
    expect(forceDeliver(supAddr(), j.escrow.address, 0, true, ton("0.2"))).toHaveFailedTx({
        to: j.escrow.address,
        exitCode: Errors.NotClaimable,
    });
}

// An NFT the batch has not reached yet is not deliverable.
get fun `test force_deliver on an NFT ahead of the cursor fails with 432`() {
    val o1 = testing.treasury("fd-7-o1");
    val o2 = testing.treasury("fd-7-o2");
    val fw = testing.treasury("fd-7-fw");
    var nfts1: map<uint16, address> = [];
    var i = 0;
    while (i < 4) {
        nfts1.set(i as uint16, deployNft(o1, 79491 + i));
        i += 1;
    }
    var cfg = makeBasicConfig(o1, o2, fw);
    cfg.nfts1 = nfts1;
    cfg.nfts1Count = 4;
    val escrow = deployEscrowMidDistribution(o1, cfg, 2, DIST_EXECUTE);
    expect(forceDeliver(supAddr(), escrow.address, 2, false, ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: Errors.NotClaimable,
    });
    expect(forceDeliver(supAddr(), escrow.address, 1, false, ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nfts1.mustGet(1))).toEqual(o2.address);
}

// After emergency_collect the phase is CANCELLED, so an asset whose delivery
// to the supervisor bounced is pulled by whoever comes first: the depositor
// with claim_asset or the supervisor with force_deliver(true).
get fun `test after emergency_collect a bounced NFT goes to whoever pulls first`() {
    val f = setup1x1("fd-8", 79501);
    setReject(f.o1.address, f.nft1, true);
    expect(f.escrow.sendText(supAddr(), "emergency_collect_assets", ton("0.3"))).toHaveBouncedTx({
        to: f.escrow.address,
    });
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(f.escrow.assetStatus(0)).toEqual((true, true, 1));
    expect(readMockOwner(f.nft2)).toEqual(supAddr());
    setReject(f.o1.address, f.nft1, false);
    expect(sendClaim(f.o1.address, f.escrow.address, 0, ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(readMockOwner(f.nft1)).toEqual(f.o1.address);
    expect(forceDeliver(supAddr(), f.escrow.address, 0, true, ton("0.1"))).toHaveBouncedTx({
        to: f.escrow.address,
    });
    expect(readMockOwner(f.nft1)).toEqual(f.o1.address);
}
