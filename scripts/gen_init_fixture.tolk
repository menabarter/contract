// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Reference fixture for the deal's deterministic address/StateInit.
//
// WHY: the contract is deployed with the FULL asset registry inside
// stateInit (there is no separate init message), so the escrow address is a
// function of the Storage contents. If an off-chain client assembles Storage
// even a single bit differently, it will compute a DIFFERENT address:
// deposits would go to a contract that doesn't exist. A round-trip within TS
// alone won't catch this — a reference from the Tolk side is needed.
//
// Prints the address and the data-cell hash for a fixed 2x1 deal, for
// cross-checking an off-chain client's own Storage assembly against it.
//
// Run: acton script scripts/gen_init_fixture.tolk
import "@acton/io"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/SwapEscrow.gen"

const OWNER1 = "0:1111111111111111111111111111111111111111111111111111111111111111"
const OWNER2 = "0:2222222222222222222222222222222222222222222222222222222222222222"
const FEE_WALLET = "0:3333333333333333333333333333333333333333333333333333333333333333"
const SUPERVISOR = "0:4444444444444444444444444444444444444444444444444444444444444444"
const NFT_A = "0:00000000000000000000000000000000000000000000000000000000000000aa"
const NFT_B = "0:00000000000000000000000000000000000000000000000000000000000000bb"
const NFT_C = "0:00000000000000000000000000000000000000000000000000000000000000cc"
const MINT_A = "0:000000000000000000000000000000000000000000000000000000000000aa01"
const MINT_B = "0:000000000000000000000000000000000000000000000000000000000000bb02"

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
        abandoned: false,
    };
}

fun main() {
    // Registry order is part of the protocol: side 1's assets first, then side 2's.
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
        sup: SupervisorState {
            supervisor: address(SUPERVISOR),
            rescueAssets: [],
            rescueCount: 0,
        }.toCell(),
        dist: DistState {
            mode: DIST_IDLE,
            cursor: 0,
            retryCount: 0,
            retry: [],
        }.toCell(),
    };

    val escrow = SwapEscrow.fromStorage(storage);
    println("# Reference StateInit for the deal (Tolk). Checked against in the application.");
    println("escrow_address {}", escrow.address);
    println("storage_data_hash {:x}", storage.toCell().hash());
    println("code_hash {:x}", escrow.stateInit!.code.hash());

    // Deposit body in EXACTLY the form the application sends it: queryId = 0,
    // forwardAmount = 0.05 TON, index-5 hint. Both the backend and the
    // frontend check against this same reference — they build this body
    // independently of each other (the frontend is a separate package and
    // cannot import backend code).
    val appDeposit = NftTransfer {
        queryId: 0,
        newOwner: address(OWNER2),
        responseDestination: address(OWNER1),
        customPayload: null,
        forwardAmount: ton("0.05"),
        forwardPayload: beginCell().storeUint(0, 1).storeUint(5, 16).endCell().beginParse(),
    }.toCell();
    println("app_nft_deposit_hint5 {:x}", appDeposit.hash());

    // ── Jetton deal ──
    // Differences from the NFT case that the application must reproduce
    // bit-for-bit: SETUP phase (a jetton deposit cannot be accepted before
    // wallets resolve), pendingWallets = the number of UNIQUE minters (minter
    // MINT_A appears on both sides — it is polled once), jettonsCount, and
    // the amount on the jetton asset. Registry order: side 1 (NFT, then
    // jettons), then side 2 in the same order.
    var jAssets: map<uint16, Asset> = [];
    jAssets.set(0, mkNft(1, address(NFT_A)));
    jAssets.set(
        1,
        Asset {
            kind: 1,
            ownerSide: 1,
            addr: address(MINT_A),
            jettonWallet: null,
            amount: 1000000000,
            received: false,
            sent: false,
            bounces: 0,
            abandoned: false,
        },
    );
    jAssets.set(
        2,
        Asset {
            kind: 1,
            ownerSide: 2,
            addr: address(MINT_A),
            jettonWallet: null,
            amount: 2500000000,
            received: false,
            sent: false,
            bounces: 0,
            abandoned: false,
        },
    );
    jAssets.set(
        3,
        Asset {
            kind: 1,
            ownerSide: 2,
            addr: address(MINT_B),
            jettonWallet: null,
            amount: 7,
            received: false,
            sent: false,
            bounces: 0,
            abandoned: false,
        },
    );

    val jStorage = Storage {
        swapId: SWAP_ID,
        phase: PHASE_SETUP,
        owner1: address(OWNER1),
        owner2: address(OWNER2),
        feeWallet: address(FEE_WALLET),
        assetsCount: 4,
        required1Count: 2,
        required2Count: 2,
        received1Count: 0,
        received2Count: 0,
        pendingWallets: 2,
        jettonsCount: 3,
        receivedJettons1: 0,
        receivedJettons2: 0,
        assets: jAssets,
        grams: GramState {
            gram1Amount: 0,
            gram2Amount: 0,
            gram1Received: 0,
            gram2Received: 0,
            gram1DepositReserve: 0,
            gram2DepositReserve: 0,
            serviceFee1: 0,
            serviceFee2: 0,
        }.toCell(),
        sup: SupervisorState {
            supervisor: address(SUPERVISOR),
            rescueAssets: [],
            rescueCount: 0,
        }.toCell(),
        dist: DistState {
            mode: DIST_IDLE,
            cursor: 0,
            retryCount: 0,
            retry: [],
        }.toCell(),
    };
    val jEscrow = SwapEscrow.fromStorage(jStorage);
    println("jetton_escrow_address {}", jEscrow.address);
    println("jetton_storage_data_hash {:x}", jStorage.toCell().hash());

    // Jetton deposit body in the application's form: amount 1 jetton
    // (9 decimals), forwardTonAmount 0.1 TON, index-1 hint.
    val jDeposit = JettonTransfer {
        queryId: 0,
        amount: 1000000000,
        destination: address(OWNER2),
        responseDestination: address(OWNER1),
        customPayload: null,
        forwardTonAmount: ton("0.1"),
        forwardPayload: beginCell().storeUint(0, 1).storeUint(1, 16).endCell().beginParse(),
    }.toCell();
    println("app_jetton_deposit_hint1 {:x}", jDeposit.hash());
}
