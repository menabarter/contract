// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Batched cancel. Large deals (received1 + received2 > FAST_PATH_MAX_ASSETS)
// are finalized not in a single transaction, but through a self-triggering
// chain of batches (runDistributionBatch with DIST_CANCEL). GRAM refunds go
// out immediately in the initiating transaction; assets go out in batches;
// the sweep happens in the final batch. The fast path (≤100) is unchanged
// byte-for-byte: it's covered by the existing cancel tests, and here it is
// pinned down by the explicit absence of ContinueDistribution in the trace.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/messages"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "nosup_helpers"

// Constructor for a large NFT deal in the ACTIVE state (auto did NOT fire —
// service_fee_owner2 is deliberately omitted, canAutoExecute requires
// serviceFee2 >= SERVICE_FEE, see Storage.canAutoExecute). Fully
// deposited by both sides: n1 + n2 > 100 received → any finalization goes
// down the batched path.
struct BigDealFixture {
    escrow: EscrowFixture
    nfts1: map<uint16, address>
    nfts2: map<uint16, address>
    o1: Treasury
    o2: Treasury
    fw: Treasury
}

// fwd1/fwd2 — the forward value of EACH side's NFT deposit (under
// SEND_MODE_PAY_FEES_SEPARATELY it reaches the escrow without the fwd fee
// deducted, and accumulates in gramNDepositReserve: handleNftReceived does
// `g.gramNDepositReserve += value`). payFee1/gram1 — whether to pay
// service_fee_owner1 and whether to deposit side-1 GRAM. service_fee_owner2
// is NEVER paid (the gate against auto-execute).
fun setupBigDeal(
    tag: string,
    seedBase: int,
    n1: int,
    n2: int,
    fwd1: coins,
    fwd2: coins,
    gram1: coins,
    payFee1: bool,
): BigDealFixture {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));

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
        nfts1,
        nfts1Count: n1,
        nfts2,
        nfts2Count: n2,
        gram1Amount: gram1,
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    if (gram1 > 0) {
        expect(
            escrow.sendText(o1.address, "deposit_ton1", gram1 + ton("0.01")),
        ).toHaveAllSuccessfulTxs();
    }
    if (payFee1) {
        expect(
            escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE),
        ).toHaveAllSuccessfulTxs();
    }

    var r1 = nfts1.findFirst();
    while (r1.isFound) {
        expect(sendNftToEscrow(o1, r1.loadValue(), escrow.address, fwd1)).toHaveAllSuccessfulTxs();
        r1 = nfts1.iterateNext(r1);
    }
    var r2 = nfts2.findFirst();
    while (r2.isFound) {
        expect(sendNftToEscrow(o2, r2.loadValue(), escrow.address, fwd2)).toHaveAllSuccessfulTxs();
        r2 = nfts2.iterateNext(r2);
    }

    expect(escrow.receivedCounts()).toEqual((n1, n2));
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    return BigDealFixture { escrow, nfts1, nfts2, o1, o2, fw };
}

// ─────────────────────────────────────────────────────────────────────────

get fun `test batched cancel returns 120 assets in batches with final sweep`() {
    // 60 + 60 = 120 received > 100 → batched cancel. Asymmetric config:
    //   side 1: gram1=1 (deposit 1.01), service_fee1=0.1, fwd1=0.05/NFT;
    //   side 2: no gram, no fee, fwd2=0.10/NFT.
    // Each side's net contribution (paid minus the return of its own assets,
    // NFT_TRANSFER_VALUE=0.03):
    //   N1 = 1.01 + 0.1 + 60*0.05 - 60*0.03 = 2.31
    //   N2 = 60*0.10 - 60*0.03 = 4.2
    // refund_i = N_i - S/2 + U/2, where S is everything shared: the gas of
    // the 120 deposits (unhinted, so each walks the registry; credited gross
    // to the counters but paid from the balance) and the cancel's own gas
    // reserve and the storage floor (0.0286 for 120 entries); U is the deploy
    // remainder. The sides differ by exactly N2 - N1 = 1.89. Every deposit's
    // own gas includes committing its record (a save plus COMMIT) before its
    // auto-execute check, so S accrues on all 120 deposits, not only a
    // completing one.
    // Measured (Tolk 1.5.0): refund1 = 1.86264975, refund2 = 3.75264975,
    // i.e. N_i - refund_i = 0.44735025 on both sides (S and U split evenly,
    // so this is side-independent): the shared costs net of U come to about
    // 0.8947 total, 0.4474 per side. S is dominated by the unhinted deposits'
    // registry walk, so the windows move with the compiler: on Tolk 1.4.2 the
    // same deal measured refund1 = 1.548106878 (an unhinted deposit into the
    // last of 120 entries took 332,827 gas there, 181,907 on Tolk 1.5.0).
    // The windows do not overlap (1.850..1.875 vs 3.740..3.765): a side
    // transposition (refunds going to the wrong depositor) would guarantee
    // this test fails.
    val f = setupBigDeal(
        "bc",
        40000,
        60,
        60,
        ton("0.05"),
        ton("0.10"),
        ton("1"),
        true,
    );

    // Cancel from owner2 (either side may cancel). Neither side has a
    // shortfall, so the whole 3 TON attachment is surplus and comes back to
    // owner2 (less the forwarding fee of its message).
    val res = f.escrow.sendText(f.o2.address, "cancel_swap", ton("3"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(res).toHaveTx({
        from: f.escrow.address,
        to: f.o2.address,
        value: fun(v: coins): bool {
            return v > ton("2.99") && v <= ton("3");
        },
    });

    // CANCELLED immediately (in the initiating transaction).
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
    // The batch chain ran to completion: distribution finished.
    val p = f.escrow.distributionProgress();
    expect(p.0).toEqual(DIST_IDLE);

    // Batching actually happened (not a single transaction) — a
    // self-trigger appears in the trace.
    expect(res).toHaveTx<ContinueDistribution>({ to: f.escrow.address });

    // All NFTs returned to THEIR OWN depositors (in batches): sampled at the
    // edges of each side's batch.
    expect(readMockOwner(f.nfts1.mustGet(0))).toEqual(f.o1.address);
    expect(readMockOwner(f.nfts1.mustGet(59))).toEqual(f.o1.address);
    expect(readMockOwner(f.nfts2.mustGet(0))).toEqual(f.o2.address);
    expect(readMockOwner(f.nfts2.mustGet(59))).toEqual(f.o2.address);

    // Per-side refund windows (pinned, non-overlapping).
    expect(res).toHaveTx({
        from: f.escrow.address,
        to: f.o1.address,
        value: fun(v: coins): bool {
            return v >= ton("1.850") && v <= ton("1.875");
        },
    });
    expect(res).toHaveTx({
        from: f.escrow.address,
        to: f.o2.address,
        value: fun(v: coins): bool {
            return v >= ton("3.740") && v <= ton("3.765");
        },
    });

    // The remainder is swept to feeWallet in the final batch (DIST_CANCEL
    // finalizeDistribution, mode 128): the escrow keeps exactly the storage
    // floor.
    expect(res).toHaveTx({ from: f.escrow.address, to: f.fw.address });
    expect(testing.getAccountBalance(f.escrow.address)).toEqual(f.escrow.storageFloor());
}

// ─────────────────────────────────────────────────────────────────────────

// A local mid-state constructor in DIST_CANCEL mode
// (deployEscrowMidDistribution with mode=DIST_CANCEL): cheap (no deposits
// need to run), phase=CANCELLED, cursor broken off mid-registry.
struct MidCancelFixture {
    escrow: EscrowFixture
    nfts1: map<uint16, address>
    nfts2: map<uint16, address>
    o1: Treasury
    o2: Treasury
    fw: Treasury
}

fun midCancelSetup(tag: string, n1: int, n2: int, cursorAt: int, seedBase: int): MidCancelFixture {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
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
        nfts1,
        nfts1Count: n1,
        nfts2,
        nfts2Count: n2,
        gram1Amount: 0,
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrowMidDistribution(o1, cfg, cursorAt, DIST_CANCEL);
    return MidCancelFixture { escrow, nfts1, nfts2, o1, o2, fw };
}

get fun `test kick in CANCELLED completes stalled returns`() {
    // mid-state: 2×2, mode=DIST_CANCEL, the cursor is broken off at 2 (the
    // fixture treats idx 0,1 as already returned; idx 2,3 = nfts2, side 2 —
    // still waiting). kick (owner1) finishes the returns to the depositor
    // (o2) and finalizes → sweep.
    val f = midCancelSetup("kc", 2, 2, 2, 30000);
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);

    val res = f.escrow.sendText(f.o1.address, "kick", ton("2"));
    expect(res).toHaveAllSuccessfulTxs();

    // Distribution completed, mode returned to IDLE.
    val p = f.escrow.distributionProgress();
    expect(p.0).toEqual(DIST_IDLE);

    // The remaining assets (idx 2,3 = side 2) returned to depositor o2.
    expect(readMockOwner(f.nfts2.mustGet(0))).toEqual(f.o2.address); // idx 2
    expect(readMockOwner(f.nfts2.mustGet(1))).toEqual(f.o2.address); // idx 3

    // The sweep went to feeWallet (DIST_CANCEL finalization); the escrow keeps
    // exactly the storage floor.
    expect(res).toHaveTx({ from: f.escrow.address, to: f.fw.address });
    expect(testing.getAccountBalance(f.escrow.address)).toEqual(f.escrow.storageFloor());
}

// ─────────────────────────────────────────────────────────────────────────

get fun `test cancel fast path unchanged for small deals`() {
    // ≤100 received: the same single-transaction path as before. An
    // explicit "one transaction" assert — the absence of ContinueDistribution
    // in the trace.
    val o1 = testing.treasury("cfp-o1");
    val o2 = testing.treasury("cfp-o2");
    val fw = testing.treasury("cfp-fw");

    val nft = deployNft(o1, 31000);
    var nfts1: map<uint16, address> = [];
    nfts1.set(0, nft);
    val empty2: map<uint16, address> = [];
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: 1,
        nfts2: empty2,
        nfts2Count: 0,
        gram1Amount: 0,
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);
    expect(sendNftToEscrow(o1, nft, escrow.address, ton("0.05"))).toHaveAllSuccessfulTxs();
    expect(escrow.receivedCounts()).toEqual((1, 0));

    val res = escrow.sendText(o1.address, "cancel_swap", ton("0.2"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(readMockOwner(nft)).toEqual(o1.address);

    // Fast-path: NOT a single self-trigger in the trace (everything in one transaction).
    expect(res).toNotHaveTx<ContinueDistribution>({ to: escrow.address });
    // dist stayed IDLE (the batched path was never initiated).
    expect(escrow.distributionProgress().0).toEqual(DIST_IDLE);
}

// ─────────────────────────────────────────────────────────────────────────
// The fast-path gate keys off the REGISTRY SIZE, not the number of received
// assets.
//
// The tests above all describe deals that are FULLY deposited, where
// receivedTotal and assetsCount coincide. A deal with a large registry and few
// deposits must still take the batched path: the unwind loop walks the whole
// registry regardless of what was received, and past roughly a thousand
// entries a single transaction would exhaust the 1,000,000-gas compute
// ceiling (exit_code -14), so cancel could never complete. That is the state
// a deal is in BEFORE deposits arrive — precisely when a party is most likely
// to cancel.

// A registry of `n` side-1 entries with NO deposits. The first `realCount`
// entries are deployed mock NFTs (so they can actually be deposited and
// returned); the rest are synthetic addresses, which is enough to give the
// registry its size.
struct SparseFixture {
    escrow: EscrowFixture
    real: map<uint16, address>
    o1: Treasury
    o2: Treasury
}

fun setupSparseDeal(tag: string, n: int, realCount: int, seedBase: int): SparseFixture {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));

    var nfts1: map<uint16, address> = [];
    var real: map<uint16, address> = [];
    var i = 0;
    while (i < n) {
        if (i < realCount) {
            val nft = deployNft(o1, seedBase + i);
            real.set(i as uint16, nft);
            nfts1.set(i as uint16, nft);
        } else {
            nfts1.set(i as uint16, address.fromWorkchainAndHash(0, seedBase + i));
        }
        i += 1;
    }

    var cfg = makeBasicConfig(o1, o2, fw);
    cfg.nfts1 = nfts1;
    cfg.nfts1Count = n;
    return SparseFixture {
        escrow: deployEscrow(o1, cfg),
        real,
        o1,
        o2,
    };
}

get fun `test cancel of a large registry with no deposits uses the batch chain`() {
    val f = setupSparseDeal("sp-cancel", 1200, 0, 0x510000);
    expect(f.escrow.receivedCounts()).toEqual((0, 0));

    val res = f.escrow.sendText(f.o1.address, "cancel_swap", ton("1"));
    expect(res).toHaveAllSuccessfulTxs();

    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(f.escrow.distributionProgress().0).toEqual(DIST_IDLE);
    // Routed through the engine rather than a single transaction.
    expect(res).toHaveTx<ContinueDistribution>({ to: f.escrow.address });
}

get fun `test cancel of a large registry returns the few deposited assets`() {
    val f = setupSparseDeal("sp-partial", 1200, 2, 0x520000);
    val nftA = f.real.mustGet(0);
    val nftB = f.real.mustGet(1);
    expect(sendNftToEscrow(f.o1, nftA, f.escrow.address, ton("0.05"))).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(f.o1, nftB, f.escrow.address, ton("0.05"))).toHaveAllSuccessfulTxs();
    expect(f.escrow.receivedCounts()).toEqual((2, 0));

    val res = f.escrow.sendText(f.o1.address, "cancel_swap", ton("1"));
    expect(res).toHaveAllSuccessfulTxs();

    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
    // Both deposited NFTs came back to their depositor — nothing is stranded.
    expect(readMockOwner(nftA)).toEqual(f.o1.address);
    expect(readMockOwner(nftB)).toEqual(f.o1.address);
}
