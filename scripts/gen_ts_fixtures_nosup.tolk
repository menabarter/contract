// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Reference-hash generator for validating the TS wrapper of SwapEscrowNosup.
//
// Prints the hash of every key body/state cell built ONLY with Tolk (i.e. the
// same code that actually goes over the network and has been proven by live
// runs). The TS test builds the same cells via wrappers-ts/SwapEscrowNosup.gen.ts
// and compares hashes. A hash match means the cells are bit-for-bit
// identical (hash is a cryptographic binding to content and references), so
// this check is stronger than a round-trip.
//
// Run: acton script scripts/gen_ts_fixtures_nosup.tolk > ts-tests/fixtures-nosup.txt
import "@acton/build"
import "@acton/io"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/messages"
import "@contracts/nosup/storage"

// Fixed addresses so the TS side can build EXACTLY the same thing (raw form 0:<hex>).
const OWNER1 = "0:1111111111111111111111111111111111111111111111111111111111111111"
const OWNER2 = "0:2222222222222222222222222222222222222222222222222222222222222222"
const FEE_WALLET = "0:3333333333333333333333333333333333333333333333333333333333333333"
const NFT_A = "0:00000000000000000000000000000000000000000000000000000000000000aa"
const NFT_B = "0:00000000000000000000000000000000000000000000000000000000000000bb"
const NFT_C = "0:00000000000000000000000000000000000000000000000000000000000000cc"

const SWAP_ID = 424242
const TON1: coins = ton("1.5")
const TON2: coins = ton("0")

fun mkNft(side: int, addr: address): Asset {
    return Asset {
        kind: 0,
        ownerSide: side as uint2,
        addr,
        jettonWallet: null,
        amount: 0,
        received: false,
        sent: false,
        bounces: 0,
        claimable: false,
    };
}

fun main() {
    println("# Reference cell hashes (Tolk, nosup). Format: <name> <hash-hex>");

    // 1. ClaimAsset — pull delivery of a deal asset whose push delivery did
    //    not arrive.
    println(
        "ClaimAsset_idx7 {:x}",
        ClaimAsset {
            queryId: 0,
            assetIndex: 7,
        }
        .toCell()
        .hash(),
    );

    // 2. DistState — batch distribution state, idle.
    println(
        "DistState_idle {:x}",
        DistState {
            mode: DIST_IDLE,
            cursor: 0,
        }
        .toCell()
        .hash(),
    );

    // 3. Asset — an NFT asset that bounced back and is now pull-claimable.
    val claimableAsset = Asset {
        kind: 0,
        ownerSide: 1,
        addr: address(NFT_A),
        jettonWallet: null,
        amount: 0,
        received: true,
        sent: false,
        bounces: 1,
        claimable: true,
    };
    println("Asset_nft_claimable {:x}", claimableAsset.toCell().hash());

    // 4. Storage — the same fixed 2x1 deal as gen_init_fixture.tolk, without
    //    the `sup` cell (this contract has no supervisor).
    var assets: map<uint16, Asset> = [];
    assets.set(0, mkNft(1, address(NFT_A)));
    assets.set(1, mkNft(1, address(NFT_B)));
    assets.set(2, mkNft(2, address(NFT_C)));

    val storage = Storage {
        swapId: SWAP_ID,
        phase: PHASE_ACTIVE,
        owner1: address(OWNER1),
        owner2: address(OWNER2),
        feeWallet: address(FEE_WALLET),
        assetsCount: 3,
        required1Count: 2,
        required2Count: 1,
        received1Count: 0,
        received2Count: 0,
        pendingWallets: 0,
        jettonsCount: 0,
        receivedJettons1: 0,
        receivedJettons2: 0,
        assets,
        grams: GramState {
            gram1Amount: TON1,
            gram2Amount: TON2,
            gram1Received: 0,
            gram2Received: 0,
            gram1DepositReserve: 0,
            gram2DepositReserve: 0,
            serviceFee1: 0,
            serviceFee2: 0,
        }.toCell(),
        dist: DistState {
            mode: DIST_IDLE,
            cursor: 0,
        }.toCell(),
    };

    val escrow = SwapEscrowNosup.fromStorage(storage);
    println("Storage_2x1 {:x}", storage.toCell().hash());
    println("address_2x1 {}", escrow.address);

    // 5. Code hash — the wrapper embeds a COPY of the compiled contract; this
    //    check is what catches a wrapper going stale after a contract change.
    println("code_hash {:x}", build("SwapEscrowNosup").hash());
}
