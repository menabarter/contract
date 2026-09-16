// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Calibrating BATCH_MAX_SENDS against the WORST BATCH TYPE.
//
// CRITERION (NOT "≥3× against 1M"):
//   a full batch of BATCH_MAX_SENDS sends of the worst asset type must stay
//   BELOW BATCH_GAS_SOFT_CAP.
// Why this way: the soft cap is checked in the while condition BEFORE EVERY
// send (Storage.runDistributionBatch — the retry loop and the cursor loop), i.e.
// the batch self-limits. If a full K-batch crosses the soft cap, the actual
// batch size is SMALLER than K ⇒ the chain needs MORE transactions than
// ceil(n/K), which is what gasReserveForSwap/batchExtraReserve reserve gas
// for ⇒ the reserve is underestimated ⇒ the deal can get parked in
// EXECUTING (the guarantee that a funded deal completes is violated).
//
// METHOD: 101-asset deals (>FAST_PATH_MAX_ASSETS=100) via the real path —
// deposits with hints, auto-execution on the last deposit. The last
// deposit's trace contains the ENTIRE distribution cascade (batch 1 inside
// the deposit transaction, then ContinueDistribution transactions). We
// measure the maximum gasUsed across the cascade and the transaction count.
//
// A NOTE on the comparison against the isolated measurement: 292,912 there
// is an isolated measurement of a PURE batch of 50 NFT sends (the
// mid-distribution fixture, no deposits). Here batch 1 runs INSIDE the
// deposit transaction (intake + 50 sends), so the numbers here are ≥ the
// isolated ones. This is conservative in the right direction: the soft cap
// sees the transaction's total spend.
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/types/big_array"
import "@acton/types/transaction"
import "@contracts/storage"
import "@wrappers/SwapEscrow.gen"
import "escrow_helpers"

// Maximum gasUsed across the trace + transaction count.
fun traceMaxGas(res: SendResultList): (int, int) {
    var maxGas = 0;
    var idx = 0;
    while (idx < res.size()) {
        val g = res.at(idx).gasUsed;
        if (g > maxGas) {
            maxGas = g;
        }
        idx += 1;
    }
    return (maxGas, res.size());
}

// DIRECT proof of ceil(n/K)'s soundness: count transactions SPECIFICALLY at
// the escrow within the cascade (and the max gas among them). If the soft
// cap were cutting batches below K, the number of escrow transactions would
// become GREATER than ceil(n/K)+1 — i.e. a gas reserve computed from
// ceil(n/K) would fall short. Counted by the transaction's accountAddr,
// not by the total number of descendants (for jettons, one send produces
// 3-4 child transactions in the wallets).
fun escrowTxStats(res: SendResultList, escrowAddr: address): (int, int) {
    var count = 0;
    var maxGas = 0;
    var idx = 0;
    while (idx < res.size()) {
        val r = res.at(idx);
        val tx = r.tx.load();
        if (tx.getAccountAddress() == escrowAddr) {
            count += 1;
            if (r.gasUsed > maxGas) {
                maxGas = r.gasUsed;
            }
        }
        idx += 1;
    }
    return (count, maxGas);
}

// An ALL-JETTON deal of k1+k2 assets; returns (maxGas, txCount) of the last
// deposit's cascade. One minter on both sides → discovery in a single
// transaction (the handleTakeWalletAddress ceiling of ~154 is not touched
// at 101).
fun measureJettonBatch(k1: int, k2: int, tag: string): (int, int) {
    val o1 = testing.treasury("gs-j-o1");
    val o2 = testing.treasury("gs-j-o2");
    val fw = testing.treasury("gs-j-fw");
    val sup = testing.treasury("gs-j-sup");
    val minter = deployJettonMinter(o1, 8801);
    mintJettons(minter, o1, ton("100000"));
    mintJettons(minter, o2, ton("100000"));
    var cfg = makeBasicConfig(o1, o2, fw, sup);
    var js: map<uint16, JettonCfg> = [];
    var i = 0;
    while (i < k1) {
        js.set(
            i as uint16,
            JettonCfg {
                minter,
                ownerSide: 1,
                amount: ton("1"),
            },
        );
        i += 1;
    }
    var j = 0;
    while (j < k2) {
        js.set(
            (k1 + j) as uint16,
            JettonCfg {
                minter,
                ownerSide: 2,
                amount: ton("1"),
            },
        );
        j += 1;
    }
    cfg.jettons = js;
    cfg.jettonsCount = k1 + k2;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    // All deposits, EXCEPT the last.
    i = 0;
    while (i < k1) {
        expect(
            sendJettonTransfer2(
                o1,
                minter,
                escrow.address,
                ton("1"),
                ton("0.2"),
                i,
            ),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    j = 0;
    while (j < k2 - 1) {
        expect(
            sendJettonTransfer2(
                o2,
                minter,
                escrow.address,
                ton("1"),
                ton("0.2"),
                k1 + j,
            ),
        ).toHaveAllSuccessfulTxs();
        j += 1;
    }
    // The LAST deposit — the trigger for the batched cascade.
    val trigger = sendJettonTransfer2(
        o2,
        minter,
        escrow.address,
        ton("1"),
        ton("0.2"),
        k1 + k2 - 1,
    );
    expect(trigger).toHaveAllSuccessfulTxs();
    val (maxGas, txCount) = traceMaxGas(trigger);
    println(
        "[{}] ALL-JETTON {} assets: txCount={} maxSingleTxGas={}",
        tag,
        k1 + k2,
        txCount,
        maxGas,
    );
    expect(escrow.phase()).toEqual(PHASE_DONE);
    return (maxGas, txCount);
}

// An ALL-NFT deal of the same size — a reference for comparison.
fun measureNftBatch(n1: int, n2: int, tag: string): (int, int) {
    val o1 = testing.treasury("gs-n-o1");
    val o2 = testing.treasury("gs-n-o2");
    val fw = testing.treasury("gs-n-fw");
    val sup = testing.treasury("gs-n-sup");
    var nfts1: map<uint16, address> = [];
    var i = 0;
    while (i < n1) {
        nfts1.set(i as uint16, deployNft(o1, 88100 + i));
        i += 1;
    }
    var nfts2: map<uint16, address> = [];
    var j = 0;
    while (j < n2) {
        nfts2.set(j as uint16, deployNft(o2, 88400 + j));
        j += 1;
    }
    var cfg = makeBasicConfig(o1, o2, fw, sup);
    cfg.nfts1 = nfts1;
    cfg.nfts1Count = n1;
    cfg.nfts2 = nfts2;
    cfg.nfts2Count = n2;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    i = 0;
    while (i < n1) {
        expect(
            sendNftToEscrow(o1, nfts1.mustGet(i as uint16), escrow.address, ton("0.2"), i),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    j = 0;
    while (j < n2 - 1) {
        expect(
            sendNftToEscrow(o2, nfts2.mustGet(j as uint16), escrow.address, ton("0.2"), n1 + j),
        ).toHaveAllSuccessfulTxs();
        j += 1;
    }
    val trigger = sendNftToEscrow(
        o2,
        nfts2.mustGet((n2 - 1) as uint16),
        escrow.address,
        ton("0.2"),
        n1 + n2 - 1,
    );
    expect(trigger).toHaveAllSuccessfulTxs();
    val (maxGas, txCount) = traceMaxGas(trigger);
    println(
        "[{}] ALL-NFT {} assets: txCount={} maxSingleTxGas={}",
        tag,
        n1 + n2,
        txCount,
        maxGas,
    );
    expect(escrow.phase()).toEqual(PHASE_DONE);
    return (maxGas, txCount);
}

// ── Measurements ──

get fun `test gas measure: all-NFT 101-asset batched cascade (reference)`() {
    val (maxGas, _) = measureNftBatch(51, 50, "ref-nft");
    // Reference: the NFT batch comfortably fits (isolated measurement: 292912).
    expect(maxGas < 1000000).toBeTrue();
}

get fun `test gas measure: all-jetton 101-asset batched cascade (WORST TYPE)`() {
    val (maxGas, _) = measureJettonBatch(51, 50, "worst-jetton");
    // The hard boundary: every cascade transaction must stay under the limit.
    expect(maxGas < 1000000).toBeTrue();
}

// CALIBRATION CRITERION: a full K-batch of the worst type <
// the soft cap. If this test fails, BATCH_MAX_SENDS must be lowered,
// otherwise ceil(n/K) underestimates the chain's transaction count and the
// gas reserve is unsound.
get fun `test gas criterion: full jetton batch stays below BATCH_GAS_SOFT_CAP`() {
    val (maxGas, _) = measureJettonBatch(51, 50, "criterion");
    println(
        "CRITERION: worst-type full-batch gas={} vs soft-cap={} → {}",
        maxGas,
        BATCH_GAS_SOFT_CAP,
        maxGas < BATCH_GAS_SOFT_CAP ? "PASS (K sound)" : "FAIL (K must be lowered)",
    );
    expect(maxGas < BATCH_GAS_SOFT_CAP).toBeTrue();
}

// A DIRECT check of WHAT EXACTLY the criterion guards: the chain's number of
// escrow transactions does not exceed ceil(n/K) + 1 (batches + a separate
// final transaction). gasReserveForSwap reserves gas for exactly
// this number. The test is falsifiable: the soft cap cutting batches below
// K would immediately raise the count.
get fun `test gas criterion: jetton chain fits ceil(n/K) batches + finalize`() {
    val o1 = testing.treasury("gs-cnt-o1");
    val o2 = testing.treasury("gs-cnt-o2");
    val fw = testing.treasury("gs-cnt-fw");
    val sup = testing.treasury("gs-cnt-sup");
    val minter = deployJettonMinter(o1, 8899);
    mintJettons(minter, o1, ton("100000"));
    mintJettons(minter, o2, ton("100000"));
    var cfg = makeBasicConfig(o1, o2, fw, sup);
    val k1 = 51;
    val k2 = 50;
    var js: map<uint16, JettonCfg> = [];
    var i = 0;
    while (i < k1) {
        js.set(
            i as uint16,
            JettonCfg {
                minter,
                ownerSide: 1,
                amount: ton("1"),
            },
        );
        i += 1;
    }
    var j = 0;
    while (j < k2) {
        js.set(
            (k1 + j) as uint16,
            JettonCfg {
                minter,
                ownerSide: 2,
                amount: ton("1"),
            },
        );
        j += 1;
    }
    cfg.jettons = js;
    cfg.jettonsCount = k1 + k2;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    i = 0;
    while (i < k1) {
        expect(
            sendJettonTransfer2(
                o1,
                minter,
                escrow.address,
                ton("1"),
                ton("0.2"),
                i,
            ),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    j = 0;
    while (j < k2 - 1) {
        expect(
            sendJettonTransfer2(
                o2,
                minter,
                escrow.address,
                ton("1"),
                ton("0.2"),
                k1 + j,
            ),
        ).toHaveAllSuccessfulTxs();
        j += 1;
    }
    val trigger = sendJettonTransfer2(
        o2,
        minter,
        escrow.address,
        ton("1"),
        ton("0.2"),
        k1 + k2 - 1,
    );
    expect(trigger).toHaveAllSuccessfulTxs();
    val n = k1 + k2;
    val expectedBatches = (n + BATCH_MAX_SENDS - 1) / BATCH_MAX_SENDS;
    val (escrowTxs, escrowMaxGas) = escrowTxStats(trigger, escrow.address);
    println(
        "CHAIN: n={} escrowTxs={} expected<=ceil(n/K)+1={} escrowMaxGas={}",
        n,
        escrowTxs,
        expectedBatches + 1,
        escrowMaxGas,
    );
    expect(escrow.phase()).toEqual(PHASE_DONE);
    // Exactly what the formula reserves gas for: batches + a separate final tx.
    expect(escrowTxs <= expectedBatches + 1).toBeTrue();
}
