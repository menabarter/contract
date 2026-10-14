// GENERATED from scripts/smoke_nosup_onesig_testnet.tolk by ts-tests/gen-v2-tests.ts — edit the source, then run npm run gen:v2.
// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Testnet smoke: a jetton deal taken in ONE signature from a v5 wallet.
// owner2 (v5r1) signs one external message: AcceptDeal first, then its NFT and
// the transfers of two TEP-89 test minters' jettons (see onesig_common.tolk
// for the deal). owner1 then pays its fee and deposits its NFT.
//
// Checked on the live network:
//   • the batch deploys the escrow before any deposit reaches it (no deposit
//     is lost or returned);
//   • the claimed wallets are confirmed by both minters (verified = true);
//   • owner2 sends nothing more: its executionShortfall share is 0;
//   • the deal reaches DONE and each side gets the other side's assets.
//
// Run: acton script scripts/smoke_nosup_onesig_testnet.tolk [--net testnet]
// Wallets: wallet1 (funder, owner1), wallet2 (owner2, v5r1).
// Budget: ~1 TON net.
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/SwapEscrowV2.gen"
import "@contracts/shared/types"
import "@contracts/v2/storage"
import "onesig_common_v2"
import "wallet_batch"

fun main() {
    println("=== SwapEscrowV2 testnet smoke: one signature (v5) ===");
    println("Broadcasting to real network: {}", net.isBroadcasting());
    val wallet1 = scripts.wallet("wallet1");
    val wallet2 = scripts.wallet("wallet2");
    println("owner1 = {}", wallet1.address);
    println("owner2 = {}", wallet2.address);

    val d = osSetup(wallet1.address, wallet1.address, wallet2.address);
    println("batch value = {} (AcceptDeal {})", osBatchValue(), osAcceptValue());

    osWaitBatch(sendBatchV5(wallet2, osBatch(d)), "owner2 batch: AcceptDeal + nft2 + 2 jettons");
    println("");
    println("after owner2's batch:");
    osPrintState(d);
    val (_, s2) = d.escrow.executionShortfall();

    osOwner1Deposits(d);
    var (s1After, _) = d.escrow.executionShortfall();
    if (d.escrow.phase() != PHASE_DONE && s1After > 0) {
        osWaitTrace(
            d
                .escrow
                .sendAny(
                    wallet1.address,
                    osText("deposit_ton1"),
                    { value: s1After + ton("0.001"), bounce: true },
                ),
            "deposit_ton1 (owner1's shortfall)",
        );
    }

    val phase = d.escrow.phase();
    val nft1Owner = osOwnerOf(d.nft1);
    val nft2Owner = osOwnerOf(d.nft2);
    val j1 = osJettonBalance(d.m1, wallet1.address);
    val j2 = osJettonBalance(d.m2, wallet1.address);
    val e1 = osJettonBalance(d.m1, d.escrow.address);
    val e2 = osJettonBalance(d.m2, d.escrow.address);
    println("");
    println("=== RESULT ===");
    osPrintState(d);
    println("owner2's shortfall after its batch = {} (expected 0)", s2);
    println("phase = {} (expected 3 = DONE)", phase);
    println("nft1 -> owner2: {}", nft1Owner == wallet2.address);
    println("nft2 -> owner1: {}", nft2Owner == wallet1.address);
    println("owner1 jettons: m1 {} (expected 10), m2 {} (expected 20)", j1, j2);
    println("escrow jettons: m1 {}, m2 {} (expected 0)", e1, e2);
    val ok = s2 == 0 && phase == PHASE_DONE && nft1Owner == wallet2.address &&
        nft2Owner == wallet1.address &&
        j1 == OS_JETTON1 &&
        j2 == OS_JETTON2 &&
        e1 == 0 &&
        e2 == 0;
    if (ok) {
        println("SMOKE PASSED: one v5 signature took the jetton deal to DONE.");
    } else {
        println("SMOKE FAILED: see above.");
    }
    println("");
    println("escrow: https://testnet.tonviewer.com/{}", d.escrow.address);
    println("owner2: https://testnet.tonviewer.com/{}", wallet2.address);
}
