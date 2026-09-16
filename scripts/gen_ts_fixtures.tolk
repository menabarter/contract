// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Reference-hash generator for validating the TS wrapper.
//
// Prints the hash of every key body cell built ONLY with Tolk (i.e. the same
// code that actually goes over the network and has been proven by live
// runs). The TS test builds the same bodies via wrappers-ts/SwapEscrow.gen.ts
// and compares hashes. A hash match means the cells are bit-for-bit
// identical (hash is a cryptographic binding to content and references), so
// this check is stronger than a round-trip.
//
// Run: acton script scripts/gen_ts_fixtures.tolk > /tmp/ts_fixtures.txt
import "@acton/io"
import "@contracts/messages"

// Fixed addresses so the TS side can build EXACTLY the same thing (raw form 0:<hex>).
const A1_RAW = "0:1111111111111111111111111111111111111111111111111111111111111111"
const A2_RAW = "0:2222222222222222222222222222222222222222222222222222222222222222"
const A3_RAW = "0:3333333333333333333333333333333333333333333333333333333333333333"

fun textBody(text: string): cell {
    return beginCell().storeUint(0, 32).storeSlice(text.beginParse()).endCell();
}

// Deposit hint: either-0 + uint16 asset_index (the same format for both
// NFT and jetton transfers).
fun hintPayload(idx: int): slice {
    return beginCell().storeUint(0, 1).storeUint(idx, 16).endCell().beginParse();
}

fun main() {
    val a1 = address(A1_RAW);
    val a2 = address(A2_RAW);
    val a3 = address(A3_RAW);

    println("# Reference cell hashes (Tolk). Format: <name> <hash-hex>");
    println("addr1 {}", A1_RAW);
    println("addr2 {}", A2_RAW);
    println("addr3 {}", A3_RAW);

    // 1. Deposit NftTransfer WITH A HINT — the most important check (the
    //    wire changed from forwardPayloadTag: bool to forwardPayload).
    val nftDeposit = NftTransfer {
        queryId: 7,
        newOwner: a2,
        responseDestination: a1,
        customPayload: null,
        forwardAmount: ton("0.05"),
        forwardPayload: hintPayload(42),
    }.toCell();
    println("NftTransfer_hint42 {:x}", nftDeposit.hash());

    // 2. NftTransfer with an EMPTY payload — this is how the escrow itself
    //    sends it on payout (zeroBitSlice() = a single 0 bit).
    val nftOut = NftTransfer {
        queryId: 0,
        newOwner: a2,
        responseDestination: a1,
        customPayload: null,
        forwardAmount: ton("0.03"),
        forwardPayload: zeroBitSlice(),
    }.toCell();
    println("NftTransfer_zeroPayload {:x}", nftOut.hash());

    // 3. JettonTransfer with a hint.
    val jettonDeposit = JettonTransfer {
        queryId: 7,
        amount: ton("1"),
        destination: a2,
        responseDestination: a1,
        customPayload: null,
        forwardTonAmount: ton("0.2"),
        forwardPayload: hintPayload(3),
    }.toCell();
    println("JettonTransfer_hint3 {:x}", jettonDeposit.hash());

    // 4. Opcodes.
    println(
        "ContinueDistribution_q5 {:x}",
        ContinueDistribution { queryId: 5 }.toCell().hash(),
    );
    println(
        "ForceDeliver_idx9_resend {:x}",
        ForceDeliver {
            queryId: 0,
            assetIndex: 9,
            fallback: false,
        }.toCell()
            .hash(),
    );
    println(
        "ForceDeliver_idx9_fallback {:x}",
        ForceDeliver {
            queryId: 0,
            assetIndex: 9,
            fallback: true,
        }.toCell()
            .hash(),
    );

    // 5. Supervisor operations.
    println(
        "RescueNft {:x}",
        RescueNft { nftAddr: a3 }.toCell().hash(),
    );

    // 6. Text commands (wire: 32 zero bits + ASCII).
    println("text_kick {:x}", textBody("kick").hash());
    println("text_service_fee_owner1 {:x}", textBody("service_fee_owner1").hash());
    println("text_cancel_swap {:x}", textBody("cancel_swap").hash());
    println("text_deploy_fee {:x}", textBody("deploy_fee").hash());
    println(
        "hint_payload_42_cell {:x}",
        beginCell().storeUint(0, 1).storeUint(42, 16).endCell().hash(),
    );
}
