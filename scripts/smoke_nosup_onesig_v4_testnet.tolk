// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Testnet smoke: the one-signature deal from a v4r2 wallet. A v4 wallet sends
// at most four messages per signature, so AcceptDeal plus three assets is its
// limit — exactly this deal (nft2 and two jettons, see onesig_common.tolk).
//
// Run: acton script scripts/smoke_nosup_onesig_v4_testnet.tolk [--net testnet]
// Wallets: wallet1 (funder, owner1), wallet2 (tops up owner2), wallet-v4
// (owner2, v4r2; `acton wallet new --name wallet-v4 --version v4r2`).
// Budget: ~1.1 TON net.
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "@contracts/shared/types"
import "onesig_common"
import "wallet_batch"

const V4_TOP_UP: coins = ton("0.7")

fun main() {
    println("=== SwapEscrowNosup testnet smoke: one signature (v4r2) ===");
    println("Broadcasting to real network: {}", net.isBroadcasting());
    val wallet1 = scripts.wallet("wallet1");
    val wallet2 = scripts.wallet("wallet2");
    val v4 = scripts.wallet("wallet-v4");
    println("owner1 = {}", wallet1.address);
    println("owner2 (v4r2) = {}", v4.address);

    // Top up owner2 and make sure its wallet contract is deployed: the batch
    // below is a plain signed request without a StateInit.
    if (scripts.fetchAccountBalance(v4.address) < V4_TOP_UP) {
        osWaitFirst(
            net.send(
                wallet2.address,
                createMessage({ bounce: false, value: V4_TOP_UP, dest: v4.address }),
            ),
            "top up owner2 (v4)",
        );
    }
    if (!scripts.isContractDeployed(v4.address)) {
        osWaitFirst(
            net.send(
                v4.address,
                createMessage({ bounce: false, value: ton("0.001"), dest: wallet2.address }),
            ),
            "deploy owner2's v4 wallet",
        );
    }

    val d = osSetup(wallet1.address, wallet1.address, v4.address);
    val msgs = osBatch(d);
    println("batch: {} messages, value {}", msgs.size(), osBatchValue());

    osWaitBatch(sendBatchV4(v4, msgs), "owner2 v4 batch: AcceptDeal + nft2 + 2 jettons");
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
    println("");
    println("=== RESULT ===");
    osPrintState(d);
    println("owner2's shortfall after its batch = {} (expected 0)", s2);
    println("phase = {} (expected 3 = DONE)", phase);
    println("nft1 -> owner2: {}", nft1Owner == v4.address);
    println("nft2 -> owner1: {}", nft2Owner == wallet1.address);
    println("owner1 jettons: m1 {} (expected 10), m2 {} (expected 20)", j1, j2);
    val ok = s2 == 0 && phase == PHASE_DONE && nft1Owner == v4.address &&
        nft2Owner == wallet1.address &&
        j1 == OS_JETTON1 &&
        j2 == OS_JETTON2;
    if (ok) {
        println("SMOKE PASSED: one v4 signature (AcceptDeal + 3 assets) took the deal to DONE.");
    } else {
        println("SMOKE FAILED: see above.");
    }
    println("");
    println("escrow: https://testnet.tonviewer.com/{}", d.escrow.address);
    println("owner2: https://testnet.tonviewer.com/{}", v4.address);
}
