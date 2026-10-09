// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Testnet smoke: a one-signature batch signed with too little balance.
// owner2's v5 wallet holds enough for AcceptDeal and the NFT transfer but not
// for the two jetton transfers after them. With mode 3 (ignore errors) the
// wallet drops what it cannot pay and sends the rest in order.
//
// Checked on the live network:
//   • the messages that fail are the LAST ones: AcceptDeal goes out, the
//     escrow is deployed, discovery runs, the NFT is recorded;
//   • the dropped jetton transfers leave owner2's jettons where they were;
//   • the deal stays ACTIVE and owner2 can cancel it: the NFT comes back.
//
// Run: acton script scripts/smoke_nosup_onesig_underfunded_testnet.tolk [--net testnet]
// Wallets: wallet1 (funder, owner1), nosup-smoke (owner2, v5r1).
// Budget: ~0.7 TON net.
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "@contracts/shared/types"
import "onesig_common"
import "wallet_batch"

// owner2's balance before the batch: AcceptDeal + NFT transfer + this slack,
// which pays the forwarding fees but is below one jetton transfer.
const UNDERFUND_SLACK: coins = ton("0.06")

fun main() {
    println("=== SwapEscrowNosup testnet smoke: underfunded one-signature batch ===");
    println("Broadcasting to real network: {}", net.isBroadcasting());
    val wallet1 = scripts.wallet("wallet1");
    val owner2 = scripts.wallet("nosup-smoke");
    println("owner1 = {}", wallet1.address);
    println("owner2 = {}", owner2.address);

    val d = osSetup(wallet1.address, wallet1.address, owner2.address);

    // Bring owner2's balance to the target: enough for the first two messages
    // of the batch, not for the jetton transfers.
    val target = osAcceptValue() + OS_FORWARD + OS_NFT_GAS + UNDERFUND_SLACK;
    val balance = scripts.fetchAccountBalance(owner2.address);
    if (balance > target + ton("0.02")) {
        osWaitFirst(
            net.send(
                owner2.address,
                createMessage({ bounce: false, value: balance - target, dest: wallet1.address }),
            ),
            "owner2 returns its surplus",
        );
    } else if (balance < target) {
        osWaitFirst(
            net.send(
                wallet1.address,
                createMessage({ bounce: false, value: target - balance, dest: owner2.address }),
            ),
            "top up owner2",
        );
    }
    val before = scripts.fetchAccountBalance(owner2.address);
    println("owner2 balance before the batch = {} (batch needs {})", before, osBatchValue());

    osWaitBatch(sendBatchV5(owner2, osBatch(d)), "owner2 batch with too little balance");
    println("");
    println("after owner2's batch:");
    osPrintState(d);
    val phase = d.escrow.phase();
    val (_, r2) = d.escrow.receivedCounts();
    val nft2Held = osOwnerOf(d.nft2) == d.escrow.address;
    val left1 = osJettonBalance(d.m1, owner2.address);
    val left2 = osJettonBalance(d.m2, owner2.address);
    println("owner2 jettons left: m1 {}, m2 {} (expected 100 each)", left1, left2);
    println("owner2 balance after the batch = {}", scripts.fetchAccountBalance(owner2.address));

    // Clean up: owner2 cancels; the NFT goes back.
    val (_, attach) = d.escrow.cancelCost();
    println("cancelCost attach = {}", attach);
    if (scripts.fetchAccountBalance(owner2.address) < attach + ton("0.02")) {
        osWaitFirst(
            net.send(
                wallet1.address,
                createMessage({ bounce: false, value: attach + ton("0.03"), dest: owner2.address }),
            ),
            "top up owner2 for the cancel",
        );
    }
    osWaitBatch(
        sendBatchV5(
            owner2,
            [
                createMessage({
                    bounce: BounceMode.Only256BitsOfBody,
                    value: attach,
                    dest: d.escrow.address,
                    body: osText("cancel_swap"),
                }),
            ],
        ),
        "cancel_swap (owner2)",
    );
    val phaseAfter = d.escrow.phase();
    val nft2Back = osOwnerOf(d.nft2) == owner2.address;

    println("");
    println("=== RESULT ===");
    println("phase after batch = {} (expected 1 = ACTIVE: deployed, discovery done)", phase);
    println("side 2 received = {} (expected 1: only the NFT)", r2);
    println("nft2 held by the escrow = {}", nft2Held);
    println("phase after cancel = {} (expected 4 = CANCELLED)", phaseAfter);
    println("nft2 back with owner2 = {}", nft2Back);
    val ok = phase == PHASE_ACTIVE && r2 == 1 && nft2Held && left1 == OS_MINT && left2 == OS_MINT &&
        phaseAfter == PHASE_CANCELLED &&
        nft2Back;
    if (!net.isBroadcasting()) {
        println("DRY RUN: the local wallet is not short of balance; checks apply on testnet.");
    } else if (ok) {
        println("SMOKE PASSED: only the last messages dropped; cancel returned the NFT.");
    } else {
        println("SMOKE FAILED: see above.");
    }
    println("");
    println("escrow: https://testnet.tonviewer.com/{}", d.escrow.address);
    println("owner2: https://testnet.tonviewer.com/{}", owner2.address);
}
