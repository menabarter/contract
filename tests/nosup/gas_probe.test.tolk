// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Alias "@stdlib/..." (NOT "@acton/tolk-stdlib/...") — the same alias under
// which this physical file is already imported inside "@acton/testing/assert"
// (transitively via "@acton/testing/expect" above). The compiler merges
// top-level symbols by the RESOLVED alias path within a single test binary;
// a different alias for the same file gives "redefinition of a symbol from
// stdlib".
import "@stdlib/gas-payments"
import "@acton/io"
// Gas boundaries of the contract.
//
// METHODOLOGY: all NFT probes below forward ton("0.20") per NFT deposit
// (forwardPerNft, the 5th optional argument of runFullSwap), so the
// auto-execution trigger always has enough attached value and the measured
// ceiling is a compute ceiling, not an economic one.
//
// Distribution loops are read-only: they never write per-asset flags back
// into the registry on the hot path (every assets.set rebuilds O(log N)
// dictionary cells, ~9000 gas each). A batch restores its state with a single
// write. The cost of the triggering transaction is ~4230 gas/NFT, so the
// limiting factor is the compute gasLimit (1,000,000 units per transaction),
// not the action-phase economics.
//
// SINGLE-TRANSACTION CAPACITY (Acton default = the real TON network config):
// measured on its own, the single-transaction distribution fits 231 NFTs
// total (n1+n2), regardless of the side split:
//   sym  115×115 (230 total) → gas=991569;  116×116 (232) → out of gas
//   asym 230×1   (231 total) → gas=995740;  231×1   (232) → out of gas
// Cost model of the triggering transaction: gas ≈ 18,445 + 4,231 × total.
// The contract uses that path only up to FAST_PATH_MAX_ASSETS (100), well
// inside the capacity. Larger deals are distributed by self-triggered
// batching in chunks across a chain of transactions, so all of the
// configurations above reach DONE.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/types/big_array"
import "@contracts/messages"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "@contracts/shared/types"
import "nosup_helpers"

// ─────────────────────────────────────────────────────────────────────────
// Gas reserves are expressed in gas units and priced with calculateGasFee
// (GETGASFEE) against the current network config. This test pins down that,
// under the current config, units 45000/9000 come to 0.003/0.0006 TON
// (accurate up to the GETGASFEE flat component, no more than +20% above), and
// that the per-send increment stays strictly linear (no second flat
// component).
// ─────────────────────────────────────────────────────────────────────────

get fun `test dynamic gas reserve matches approved TON values (0.003/0.0006, ±flat)`() {
    val base = calculateGasFee(0, 45000);
    expect(base >= ton("0.003")).toEqual(true);
    expect(base <= ton("0.0036")).toEqual(true);
    val withOneSend = calculateGasFee(0, 45000 + 9000);
    val perSend = withOneSend - base;
    expect(perSend >= ton("0.0006")).toEqual(true);
    expect(perSend <= ton("0.00072")).toEqual(true);
}

// ─────────────────────────────────────────────────────────────────────────
// Around the single-transaction ceiling: 230/231 total and 232 total, both
// splits. All of these are above FAST_PATH_MAX_ASSETS, so they go through
// the batched path and reach DONE.
// ─────────────────────────────────────────────────────────────────────────

get fun `test gas boundary: sym 115x115 (230 total) passes`() {
    runFullSwap(115, 115, 0, 0, ton("0.20"));
}

// 232 total (116×116) is past the single-transaction ceiling. The batched
// path (>100 assets → EXECUTING → batches of 50 + a separate final
// transaction) does not have that ceiling: the deal reaches DONE via the
// continue chain.
get fun `test batched: sym 116x116 (232 total) reaches DONE via continue chain`() {
    val o1 = testing.treasury("gb116-o1");
    val o2 = testing.treasury("gb116-o2");
    val fw = testing.treasury("gb116-fw");
    var nfts1: map<uint16, address> = [];
    var i = 0;
    while (i < 116) {
        nfts1.set(i as uint16, deployNft(o1, 1000 + i));
        i += 1;
    }
    var nfts2: map<uint16, address> = [];
    var j = 0;
    while (j < 116) {
        nfts2.set(j as uint16, deployNft(o2, 2000 + j));
        j += 1;
    }
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: 116,
        nfts2,
        nfts2Count: 116,
        gram1Amount: 0,
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);
    escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE);
    var r1 = nfts1.findFirst();
    while (r1.isFound) {
        sendNftToEscrow(o1, r1.loadValue(), escrow.address, ton("0.20"));
        r1 = nfts1.iterateNext(r1);
    }
    escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE);
    var r2 = nfts2.findFirst();
    while (r2.isFound && r2.getKey() < 115) {
        sendNftToEscrow(o2, r2.loadValue(), escrow.address, ton("0.20"));
        r2 = nfts2.iterateNext(r2);
    }
    // The last (116th) NFT on side 2 triggers the auto-cascade: >100 assets →
    // the batched path (EXECUTING, batches of 50, continue chain, a
    // separate final transaction) — the cascade is applied atomically within
    // a single net.send (see distribution.test.tolk STEP 0) and reaches DONE.
    val lastNft = nfts2.mustGet(115);
    sendNftToEscrow(o2, lastNft, escrow.address, ton("0.20"));
    expect(escrow.phase()).toEqual(PHASE_DONE); // batched path, no single-tx ceiling
    // Owners are swapped cross-wise — delivery actually went through.
    expect(readMockOwner(nfts1.mustGet(0))).toEqual(o2.address);
    expect(readMockOwner(nfts2.mustGet(0))).toEqual(o1.address);
}

get fun `test gas boundary: asym 230x1 (231 total) passes`() {
    runFullSwap(230, 1, 0, 0, ton("0.20"));
}

// The asymmetric mirror of 116×116 above — 232 total (231×1) would not fit a
// single transaction; the batched path takes it through to DONE.
get fun `test batched: asym 231x1 (232 total) reaches DONE via continue chain`() {
    val o1 = testing.treasury("gb231-o1");
    val o2 = testing.treasury("gb231-o2");
    val fw = testing.treasury("gb231-fw");
    var nfts1: map<uint16, address> = [];
    var i = 0;
    while (i < 231) {
        nfts1.set(i as uint16, deployNft(o1, 1000 + i));
        i += 1;
    }
    val nft2 = deployNft(o2, 2000);
    var nfts2: map<uint16, address> = [];
    nfts2.set(0, nft2);
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: 231,
        nfts2,
        nfts2Count: 1,
        gram1Amount: 0,
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);
    escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE);
    var r1 = nfts1.findFirst();
    while (r1.isFound) {
        sendNftToEscrow(o1, r1.loadValue(), escrow.address, ton("0.20"));
        r1 = nfts1.iterateNext(r1);
    }
    escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE);
    // The single side-2 NFT triggers the auto-cascade last; >100 assets →
    // the batched path, the cascade reaches DONE (see STEP 0).
    sendNftToEscrow(o2, nft2, escrow.address, ton("0.20"));
    expect(escrow.phase()).toEqual(PHASE_DONE);
    // The single side-2 NFT went to owner1; the first side-1 NFT, checked as a sample, went to owner2.
    expect(readMockOwner(nft2)).toEqual(o1.address);
    expect(readMockOwner(nfts1.mustGet(0))).toEqual(o2.address);
}

// ─────────────────────────────────────────────────────────────────────────
// Probes BELOW the single-transaction boundary (231 total) — real full runs
// (runFullSwap asserts DONE + NFT owners + feeWallet).
// Gas of the triggering transaction on the single-transaction path:
//   37×37  (74 total)  → 327,693     50×50  (100 total)  → 437,339
// (larger deals take the batched path; see the batch probes below)
// ─────────────────────────────────────────────────────────────────────────

get fun `test gas probe: sym 37x37`() {
    runFullSwap(37, 37, 0, 0, ton("0.20"));
}

get fun `test gas probe: sym 50x50`() {
    runFullSwap(50, 50, 0, 0, ton("0.20"));
}

get fun `test gas probe: sym 75x75`() {
    runFullSwap(75, 75, 0, 0, ton("0.20"));
}

get fun `test gas probe: sym 100x100`() {
    runFullSwap(100, 100, 0, 0, ton("0.20"));
}

get fun `test gas probe: asym 77x1`() {
    runFullSwap(77, 1, 0, 0, ton("0.20"));
}

get fun `test gas probe: asym 100x1`() {
    runFullSwap(100, 1, 0, 0, ton("0.20"));
}

get fun `test gas probe: asym 150x1`() {
    runFullSwap(150, 1, 0, 0, ton("0.20"));
}

get fun `test gas probe: asym 200x1`() {
    runFullSwap(200, 1, 0, 0, ton("0.20"));
}

// ─────────────────────────────────────────────────────────────────────────
// Probes ABOVE the 231-total single-transaction ceiling — these go through
// the batched path and complete (see also 116×116 / 231×1 above). They run
// fast and serve as live evidence for the shipped deal-size limit.
// ─────────────────────────────────────────────────────────────────────────

get fun `test gas probe: sym 125x125`() {
    runFullSwap(125, 125, 0, 0, ton("0.20"));
}

get fun `test gas probe: sym 150x150`() {
    runFullSwap(150, 150, 0, 0, ton("0.20"));
}

@test.skip("passes via the batched path; skipped for wall-time")
get fun `test gas probe: asym 256x1`() {
    runFullSwap(256, 1, 0, 0, ton("0.20"));
}

// ─────────────────────────────────────────────────────────────────────────
// Jetton gas probes (K jettons from one minter per side, forwardPerJetton=0.2
// — the same methodology as the NFT probes above).
//
// Deploy cost scales with the registry: handleDeployFee dedups minters with a
// map of seen minters (O(n·log n)), and deployValue accounts for the total
// assetsCount via gas units (DEPLOY_GAS_UNITS_PER_ASSET, storage.tolk).
// handleTakeWalletAddress (the minter's response to ProvideWalletAddress)
// scans all n assets and does a `.set()` on each match to record
// jettonWallet, so the value of each ProvideWalletAddress carries
// PROVIDE_WALLET_VALUE +
// calculateGasFee(BASECHAIN, TAKE_SCAN_BASE_UNITS + TAKE_SCAN_UNITS_PER_ENTRY ×
// assetsCount + TAKE_SET_UNITS × the minter's slots) (see storage.tolk).
//
// BOUNDARY — a genuine compute ceiling in handleTakeWalletAddress (1,000,000
// gas per ordinary transaction, GasPricesExtended.gasLimit), not a value
// economics issue (attaching even 5 TON to TakeWalletAddress does not help
// past the boundary). As with the NFT boundary (230/231 total, different for
// sym/asym), the jetton boundary also differs by split:
//   sym  75×75  (150 total) → PASS;  76×76  (152 total) → FAIL
//   asym 152×0  (152 total) → PASS;  153×0  (153 total) → FAIL
// (the asymmetric boundary is 2 higher than the symmetric one: the cost of
// `.set()` in the TVM dictionary is sensitive to the order/shape of the
// tree, not just the total count).
// ─────────────────────────────────────────────────────────────────────────

// Local helper: a jetton deal k1×k2 from one minter, a full cycle through to DONE.
fun runJettonSwap(k1: int, k2: int): bool {
    val o1 = testing.treasury("jg-o1");
    val o2 = testing.treasury("jg-o2");
    val fw = testing.treasury("jg-fw");
    val minter = deployJettonMinter(o1, 61);
    mintJettons(minter, o1, ton("100000"));
    mintJettons(minter, o2, ton("100000"));
    var cfg = makeBasicConfig(o1, o2, fw);
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
    // A side with no assets pays its half of the shared costs as TON.
    if (k2 == 0) {
        val (_s1, s2) = escrow.executionShortfall();
        expect(escrow.sendText(o2.address, "deposit_ton2", s2)).toHaveAllSuccessfulTxs();
    }
    // IMPORTANT (single-minter, multi-entry deal): under fallback matching, all
    // of a side's entries are equivalent — the hint pins down the specific index
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
    while (j < k2) {
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
    return escrow.phase() == PHASE_DONE;
}

get fun `test gas probe: jetton sym 5x5`() {
    expect(runJettonSwap(5, 5)).toEqual(true);
}

get fun `test gas probe: jetton sym 10x10`() {
    expect(runJettonSwap(10, 10)).toEqual(true);
}

get fun `test gas probe: jetton sym 15x15`() {
    expect(runJettonSwap(15, 15)).toEqual(true);
}

// ─────────────────────────────────────────────────────────────────────────
// Mid-range jetton deals — deep inside the boundary (150/152 total).
// ─────────────────────────────────────────────────────────────────────────

get fun `test gas boundary: jetton sym 19x19 (38 total) passes`() {
    expect(runJettonSwap(19, 19)).toEqual(true);
}

get fun `test gas boundary: jetton asym 38x0 (38 total) passes`() {
    expect(runJettonSwap(38, 0)).toEqual(true);
}

// ─────────────────────────────────────────────────────────────────────────
// JETTON BOUNDARY BISECTION — the ceiling is compute in
// handleTakeWalletAddress (1,000,000 gas, the ordinary transaction limit) —
// the same failure class as the NFT boundary (compute out-of-gas,
// exit_code=-14), NOT action_result_code=37 (the ProvideWalletAddress value
// scales with the registry, see the section header above). The failure does
// NOT occur in the deploy transaction
// itself (it succeeds — handleDeployFee sends ProvideWalletAddress and
// completes), but in the CHILD transaction — the minter's TakeWalletAddress
// response, which the TVM atomically rolls back in full (the bounce goes
// back to the minter, the escrow stays in PHASE_SETUP with
// pendingWallets=1). Hence the shape of the asserts below: deployEscrow()
// (the top-level deploy) stays SUCCESSFUL, and the failure signature is
// getting stuck in SETUP/pendingWalletsLeft=1 AFTER the deploy.
// ─────────────────────────────────────────────────────────────────────────

get fun `test gas boundary: jetton sym 75x75 (150 total) passes`() {
    expect(runJettonSwap(75, 75)).toEqual(true);
}

get fun `test gas boundary: jetton sym 76x76 (152 total) fails at TakeWalletAddress — compute out-of-gas exit_code=-14`() {
    val o1 = testing.treasury("jb7676-o1");
    val o2 = testing.treasury("jb7676-o2");
    val fw = testing.treasury("jb7676-fw");
    val minter = deployJettonMinter(o1, 61);
    var cfg = makeBasicConfig(o1, o2, fw);
    var js: map<uint16, JettonCfg> = [];
    var i = 0;
    while (i < 76) {
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
    while (j < 76) {
        js.set(
            (76 + j) as uint16,
            JettonCfg {
                minter,
                ownerSide: 2,
                amount: ton("1"),
            },
        );
        j += 1;
    }
    cfg.jettons = js;
    cfg.jettonsCount = 152;
    // The (top-level) deploy SUCCEEDS — handleDeployFee only sends
    // ProvideWalletAddress and completes; the failure is in the child
    // transaction (the minter's TakeWalletAddress response), which the TVM
    // atomically rolls back.
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.phase()).toEqual(PHASE_SETUP);
    expect(escrow.pendingWalletsLeft()).toEqual(1);
}

get fun `test gas boundary: jetton asym 152x0 (152 total) passes`() {
    expect(runJettonSwap(152, 0)).toEqual(true);
}

get fun `test gas boundary: jetton asym 153x0 (153 total) fails at TakeWalletAddress — compute out-of-gas exit_code=-14`() {
    val o1 = testing.treasury("jb1530-o1");
    val o2 = testing.treasury("jb1530-o2");
    val fw = testing.treasury("jb1530-fw");
    val minter = deployJettonMinter(o1, 61);
    var cfg = makeBasicConfig(o1, o2, fw);
    var js: map<uint16, JettonCfg> = [];
    var i = 0;
    while (i < 153) {
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
    cfg.jettons = js;
    cfg.jettonsCount = 153;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.phase()).toEqual(PHASE_SETUP);
    expect(escrow.pendingWalletsLeft()).toEqual(1);
}

// ─────────────────────────────────────────────────────────────────────────
// 50×50 jettons from one minter (100 total) sits inside the boundary
// (150/152 total), with a margin of ~50 total.
// ─────────────────────────────────────────────────────────────────────────

get fun `test gas probe: jetton sym 50x50`() {
    expect(runJettonSwap(50, 50)).toEqual(true);
}

// ─────────────────────────────────────────────────────────────────────────
// Scaling probes: 100×100 / 1000×1 / 500×500 / mixed 80nft+20jetton per
// side, full cycles WITH DEPOSITS through the batching engine.
//
// NFT intake cost: every deposit in these probes carries the asset_index hint
// in forward_payload (runFullSwap passes each NFT's global index,
// sendNftToEscrow puts it there), so handleNftReceived finds the slot in
// O(1). A deposit WITHOUT a hint falls back to a linear registry scan, which
// runs out of compute at a scan depth of roughly 875 — so for very large
// deals the hint is what keeps deposits within gas.
// ─────────────────────────────────────────────────────────────────────────

get fun `test probe 100x100 nft batched swap completes`() {
    runFullSwap(100, 100, 0, 0, ton("0.20"));
}

get fun `test probe mixed 80nft+20jetton per side batched`() {
    runMixedSwap(
        80,
        20,
        80,
        20,
        ton("1"),
        ton("1"),
    );
}

get fun `test gas probe: 850x1 (851 total) full cycle completes`() {
    runFullSwap(
        850,
        1,
        0,
        0,
        ton("0.20"),
        true,
    );
}

// Full cycles (deploy + deposits + auto-execution) at 1000 assets — reach DONE
// via the batching engine.
get fun `test probe 1000x1 nft batched swap completes`() {
    val escrow = runFullSwap(
        1000,
        1,
        0,
        0,
        ton("0.20"),
        true,
    );
    val progress = escrow.distributionProgress();
    expect(progress.0).toEqual(DIST_IDLE);
    expect(progress.1).toEqual(1001);
}

get fun `test probe 500x500 nft batched swap completes`() {
    val escrow = runFullSwap(500, 500, 0, 0, ton("0.20"));
    val progress = escrow.distributionProgress();
    expect(progress.0).toEqual(DIST_IDLE);
    expect(progress.1).toEqual(1000);
}

// ─────────────────────────────────────────────────────────────────────────
// ISOLATING the distribution engine from deposit intake:
// deployEscrowMidDistribution builds the EXECUTING state DIRECTLY
// (received=true is already set in Storage, with NO deposits), then kick
// starts the batching engine's continue chain with cursor=0. This proves the
// batching engine on its own (batches of BATCH_MAX_SENDS=50, self-trigger, a
// separate final transaction) takes 1000/1001 assets through to DONE, and
// gives a real gasUsed measurement of a full batch.
// ─────────────────────────────────────────────────────────────────────────

get fun `test distribution engine batches 1000 assets via kick (isolated from deposit intake scan, sym 500x500)`() {
    val o1 = testing.treasury("mde5-o1");
    val o2 = testing.treasury("mde5-o2");
    val fw = testing.treasury("mde5-fw");
    var nfts1: map<uint16, address> = [];
    var i = 0;
    while (i < 500) {
        nfts1.set(i as uint16, deployNft(o1, 70000 + i));
        i += 1;
    }
    var nfts2: map<uint16, address> = [];
    var j = 0;
    while (j < 500) {
        nfts2.set(j as uint16, deployNft(o2, 71000 + j));
        j += 1;
    }
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: 500,
        nfts2,
        nfts2Count: 500,
        gram1Amount: 0,
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrowMidDistribution(o1, cfg, 0, DIST_EXECUTE);
    expect(escrow.phase()).toEqual(PHASE_EXECUTING);
    // 1000 outgoing NFT transfers × 0.03 TON (NFT_TRANSFER_VALUE) ≈ 30 TON —
    // deployEscrowMidDistribution only gives the escrow ton("10") at deploy
    // time (enough for the small mid-state fixtures in other tests, but not
    // for an isolated probe of 1000 assets with no real deposits, which
    // normally fill the balance via the forward reserve). Kick adds the
    // margin.
    val res = escrow.sendText(o1.address, "kick", ton("35"));
    expect(res).toHaveAllSuccessfulTxs();
    // A measurement of the actual gas of a full batch: the maximum gasUsed
    // across all cascade transactions — printed to stdout (`acton test
    // --verbose`) for manual comparison against the ≈230k model estimate
    // from storage.tolk. Observed: txCount=1023,
    // maxSingleTxGasUsed=292912 (a full batch of 50 sends) — below the
    // threshold for reconsidering BATCH_MAX_SENDS (>300k), with a margin of
    // ≈2.05× to the soft cap of 600k and ≈3.4× to the hard limit of
    // 1,000,000.
    var maxGas = 0;
    var idx = 0;
    while (idx < res.size()) {
        val g = res.at(idx).gasUsed;
        if (g > maxGas) {
            maxGas = g;
        }
        idx += 1;
    }
    println(
        "1000-asset isolated batch cascade — txCount={} maxSingleTxGasUsed={}",
        res.size(),
        maxGas,
    );
    expect(
        maxGas,
    ).toBeLess(600000); // an explicit assert against the soft cap (not just an observation)
    expect(escrow.phase()).toEqual(PHASE_DONE);
    val progress = escrow.distributionProgress();
    expect(progress.0).toEqual(DIST_IDLE);
    expect(progress.1).toEqual(1000);
    expect(readMockOwner(nfts1.mustGet(0))).toEqual(o2.address);
    expect(readMockOwner(nfts2.mustGet(499))).toEqual(o1.address);
}

get fun `test distribution engine batches 1001 assets via kick (isolated from deposit intake scan, asym 1000x1)`() {
    val o1 = testing.treasury("mde1k-o1");
    val o2 = testing.treasury("mde1k-o2");
    val fw = testing.treasury("mde1k-fw");
    var nfts1: map<uint16, address> = [];
    var i = 0;
    while (i < 1000) {
        nfts1.set(i as uint16, deployNft(o1, 72000 + i));
        i += 1;
    }
    val nft2 = deployNft(o2, 73000);
    var nfts2: map<uint16, address> = [];
    nfts2.set(0, nft2);
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: 1000,
        nfts2,
        nfts2Count: 1,
        gram1Amount: 0,
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrowMidDistribution(o1, cfg, 0, DIST_EXECUTE);
    expect(escrow.phase()).toEqual(PHASE_EXECUTING);
    val res = escrow.sendText(o1.address, "kick", ton("35"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_DONE);
    val progress = escrow.distributionProgress();
    expect(progress.0).toEqual(DIST_IDLE);
    expect(progress.1).toEqual(1001);
    expect(readMockOwner(nfts1.mustGet(0))).toEqual(o2.address);
    expect(readMockOwner(nft2)).toEqual(o1.address);
}

// ─────────────────────────────────────────────────────────────────────────
// A synthetic check of the GASCONSUMED safeguard (BATCH_GAS_SOFT_CAP=600000).
// The cancel cursor walks the ENTIRE registry (not just received assets),
// skipping unreceived assets (received=false) WITHOUT sending — but every
// skip still costs gas (assets.mustGet — a dict lookup). A long tail of
// unreceived entries exhausts the soft cap ON ITS OWN, before the cursor
// even reaches the actually received (received=true) assets in the tail of
// the registry — the batch must stop (preserving the cursor, NOT failing on
// gas) and finish on the next continue. Construction: 700 "empty" entries
// (a dummy address — received=false, sendAsset is never called, so the
// address does not need to be a real NFT contract — no actual deploy of 700
// NFTs is required) + 50 real NFTs in the tail (received=true, actually
// delivered to the depositor on cancel). Only 50 real sends ≤
// BATCH_MAX_SENDS — if the cascade still fit in ONE transaction, that would
// prove the soft cap did NOT trigger; the appearance of ContinueDistribution
// in the trace is direct proof that the stop happened specifically because
// of GASCONSUMED, not because of the send-count limit.
// ─────────────────────────────────────────────────────────────────────────

get fun `test GASCONSUMED soft-cap forces multi-batch cancel over long unreceived skip zone`() {
    // 2000 unreceived entries are skipped (skip-only, ~a few hundred gas each
    // — a dict lookup WITHOUT sending) + 50 real sends in the tail. WITHOUT
    // the GASCONSUMED safeguard, a single transaction trying to walk all
    // 2000 skips + 50 sends would need gas well ABOVE the hard limit
    // (1,000,000) — compute out-of-gas (exit_code=-14). The explicit maxGas < soft-cap assert below is direct
    // proof that the safeguard actually limits EVERY transaction in the
    // cascade, not just that it "somehow got there".
    val f = deploySparseCancelMidState("sparsecc", 2000, 50);
    val res = f.escrow.sendText(f.o1.address, "kick", ton("1"));
    expect(res).toHaveAllSuccessfulTxs();
    // Proof that "the stop is NOT due to BATCH_MAX_SENDS" (only 50 real
    // sends ≤ 50 — without the soft cap the cascade would fit in a single
    // kick transaction, with no ContinueDistribution at all).
    expect(res).toHaveTx<ContinueDistribution>({ to: f.escrow.address });
    var maxGas = 0;
    var idx = 0;
    while (idx < res.size()) {
        val g = res.at(idx).gasUsed;
        if (g > maxGas) {
            maxGas = g;
        }
        idx += 1;
    }
    println(
        "sparse cancel (2000 skip + 50 tail) — txCount={} maxSingleTxGasUsed={}",
        res.size(),
        maxGas,
    );
    // The key safeguard assert: NO cascade transaction came close to the
    // hard limit (1,000,000) — the soft cap actually stopped the skip loop
    // well before that, leaving a margin (see BATCH_GAS_SOFT_CAP in storage.tolk).
    expect(maxGas).toBeLess(700000);
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
    val progress = f.escrow.distributionProgress();
    expect(progress.0).toEqual(DIST_IDLE); // delivery COMPLETED despite the interruption(s)
    // The tail NFTs (side 2) actually made it back to depositor o2 — delivery
    // didn't just "not fail", it carried the real cargo through after a
    // gas-driven interruption.
    expect(readMockOwner(f.tailNfts.mustGet(0))).toEqual(f.o2.address);
    expect(readMockOwner(f.tailNfts.mustGet(49))).toEqual(f.o2.address);
    // The final sweep (DIST_CANCEL) leaves exactly the storage floor.
    expect(testing.getAccountBalance(f.escrow.address)).toEqual(f.escrow.storageFloor());
}

// ─────────────────────────────────────────────────────────────────────────
// Deal-size probes for choosing the off-chain per-side limit. With batching,
// NFT distribution has no single-transaction ceiling; these record how far
// the contract itself reaches.
// ─────────────────────────────────────────────────────────────────────────

get fun `test limit probe: sym 200x200 (400 total)`() {
    runFullSwap(200, 200, 0, 0, ton("0.20"));
}

get fun `test limit probe: sym 250x250 (500 total)`() {
    runFullSwap(250, 250, 0, 0, ton("0.20"));
}

// ─────────────────────────────────────────────────────────────────────────
// PRODUCTION LIMITS — anchors for the caps the off-chain layer enforces.
//
// Two independent ceilings constrain a deal, and both are consumed from the
// same 1,000,000-gas compute limit, which no attached value can raise:
//
//   A. How many DISTINCT jetton minters a deal names. Every unique minter
//      gets its own ProvideWalletAddress from handleDeployFee, all built in
//      the deploy transaction. Too many and the DEPLOY ITSELF aborts — the
//      contract is never created, so nothing is at risk.
//
//   B. How many registry positions belong to ONE minter. Every response
//      re-scans the whole registry and does an assets.set per matching
//      position (~9000 gas each), so this is the harsher of the two. Here the
//      deploy SUCCEEDS and the minter's reply rolls back: the deal sticks in
//      PHASE_SETUP for good. It stays cancellable, so funds are not trapped,
//      but it can never activate — which is why the off-chain layer must
//      reject such a deal BEFORE deploying it.
//
// Note the dictionary's shape matters, not just the total: the boundary is
// pinned in both the symmetric (75x75 / 76x76) and the asymmetric
// (152x0 / 153x0) form: 76x76 fails where 152x0 of the same total passes.
//
// Amounts are irrelevant to all of this — a position carries a single
// `coins` field, so a million-token position costs exactly what a one-token
// position costs.
// ─────────────────────────────────────────────────────────────────────────

// The shipped cap, exercised end to end (deploy → TEP-89 discovery →
// deposits → auto-execution). Keep this passing, or the documented limit in
// README.md is no longer true.
get fun `test production limit: 150 NFT + 15 jettons per side completes`() {
    val e = runMixedSwap(
        150,
        15,
        150,
        15,
        ton("1"),
        ton("1"),
    );
    expect(e.phase()).toEqual(PHASE_DONE);
}

// The same cap in a deal with no NFTs at all. A jetton-only deal has far more
// headroom — the registry the minter replies scan is short — but the shipped
// limit is deliberately FLAT, so this pins it in that configuration too
// rather than leaving the tokens-only case to inference.
get fun `test production limit: 15 jettons per side, no NFTs, completes`() {
    val e = runMixedSwap(
        0,
        15,
        0,
        15,
        ton("1"),
        ton("1"),
    );
    expect(e.phase()).toEqual(PHASE_DONE);
}

// Boundary pair for ceiling B at 150 NFT per side, same style as the
// 75x75/76x76 pair above: 25 per side is the last full cycle that
// completes, 30 already exhausts compute.
get fun `test gas boundary: 150 NFT + 25 jettons per side still completes`() {
    val e = runMixedSwap(
        150,
        25,
        150,
        25,
        ton("1"),
        ton("1"),
    );
    expect(e.phase()).toEqual(PHASE_DONE);
}

// The failure MODE of ceiling B, which is the safety-relevant part: the
// deploy transaction succeeds and the contract is created, but the minter's
// TakeWalletAddress reply runs out of compute and is rolled back, so
// discovery never finishes. The deal is stuck in PHASE_SETUP permanently —
// and must still be cancellable, or the deposits would be trapped.
// runMixedSwap cannot express this: it asserts success internally, so the
// registry is built directly here.
get fun `test gas boundary: 150 NFT + 50 jettons per side deploys but sticks in SETUP`() {
    val o1 = testing.treasury("pb50-o1");
    val o2 = testing.treasury("pb50-o2");
    val fw = testing.treasury("pb50-fw");
    var cfg = makeBasicConfig(o1, o2, fw);

    var nfts1: map<uint16, address> = [];
    var nfts2: map<uint16, address> = [];
    var i = 0;
    while (i < 150) {
        nfts1.set(i as uint16, address.fromWorkchainAndHash(0, 0xB10000 + i));
        nfts2.set(i as uint16, address.fromWorkchainAndHash(0, 0xB20000 + i));
        i += 1;
    }
    cfg.nfts1 = nfts1;
    cfg.nfts1Count = 150;
    cfg.nfts2 = nfts2;
    cfg.nfts2Count = 150;

    val minter = deployJettonMinter(o1, 0xB3);
    var js: map<uint16, JettonCfg> = [];
    var k = 0;
    while (k < 50) {
        js.set(
            k as uint16,
            JettonCfg {
                minter,
                ownerSide: 1,
                amount: ton("1"),
            },
        );
        js.set(
            (50 + k) as uint16,
            JettonCfg {
                minter,
                ownerSide: 2,
                amount: ton("1"),
            },
        );
        k += 1;
    }
    cfg.jettons = js;
    cfg.jettonsCount = 100;

    // Deploy itself goes through — the rollback happens one transaction later.
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.phase()).toEqual(PHASE_SETUP);
    expect(escrow.pendingWalletsLeft()).toEqual(1);

    // Funds are not trapped: cancel still works from SETUP.
    expect(escrow.sendText(o1.address, "cancel_swap", ton("2"))).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
}
