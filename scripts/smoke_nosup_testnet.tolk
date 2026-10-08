// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Testnet smoke: SwapEscrowNosup happy path — a 1x1 NFT deal in which every
// delivery succeeds.
//
// Checked on the live network:
//   • the last deposit auto-executes the swap and the deal reaches DONE;
//   • each NFT ends up with the opposite side;
//   • no asset is marked claimable and no delivery bounced;
//   • the escrow's balance is swept to feeWallet, leaving it at zero — the
//     counterpart to smoke_nosup_claim_testnet.tolk, where a bounce returns
//     its own value after the sweep and that value stays put.
//
// Run: acton script scripts/smoke_nosup_testnet.tolk [--net testnet]
// Budget: ~0.4 TON net.
import "@acton/build"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/messages"
import "@contracts/nft_item_mock"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"

const NFT_DEPLOY_VALUE: coins = ton("0.03")
const NFT_FORWARD: coins = ton("0.05")
const POLL_ATTEMPTS = 40
const POLL_SLEEP_MS = 3000

fun textBody(text: string): cell {
    return beginCell().storeUint(0, 32).storeSlice(text.beginParse()).endCell();
}

fun waitFirst(res: SendResultList, label: string): SendResultList {
    val applied = res.waitForFirstTransaction(false, POLL_ATTEMPTS, POLL_SLEEP_MS);
    if (applied == null) {
        println("[TIMEOUT] {} — not confirmed", label);
    } else {
        println("[OK] {} — lt={}", label, applied.lt);
    }
    return res;
}

fun waitTrace(res: SendResultList, label: string): SendResultList {
    val applied = res.waitForTrace(false, POLL_ATTEMPTS, POLL_SLEEP_MS);
    if (applied == null) {
        println("[TIMEOUT] {} (trace) — not confirmed", label);
    } else {
        println("[OK] {} (full trace confirmed)", label);
    }
    return res;
}

// A per-run seed. The wallet's last transaction LT changes with every run, so
// the mocks and the escrow get fresh addresses instead of landing on objects a
// previous run left on the network (an NFT already handed to the other side).
fun runSeed(wallet: address): int {
    val shard = scripts.fetchShardAccount(wallet);
    if (shard == null) {
        return 0;
    }
    return shard.lastTransLt % 1000000000;
}

fun deployNftMock(deployer: address, owner: address, seed: int): address {
    val init = ContractState {
        code: build("NftItemMock"),
        data: MockNftStorage {
            ownerAddr: owner,
            seed: seed as uint32,
            rejectTransfers: false,
        }.toCell(),
    };
    val addr = AutoDeployAddress { stateInit: init }.calculateAddress();
    waitFirst(
        net.send(
            deployer,
            createMessage({ bounce: false, value: NFT_DEPLOY_VALUE, dest: { stateInit: init } }),
        ),
        "deploy NftItemMock",
    );
    return addr;
}

fun depositNft(owner: address, nft: address, escrow: address, hint: int): SendResultList {
    return net.send(
        owner,
        createMessage({
            bounce: true,
            value: NFT_FORWARD + ton("0.05"),
            dest: nft,
            body: NftTransfer {
                queryId: hint,
                newOwner: escrow,
                responseDestination: owner,
                customPayload: null,
                forwardAmount: NFT_FORWARD,
                forwardPayload: beginCell()
                    .storeUint(0, 1)
                    .storeUint(hint, 16)
                    .endCell()
                    .beginParse(),
            },
        }),
    );
}

fun mkAsset(side: int, addr: address): Asset {
    return Asset {
        kind: 0,
        ownerSide: side as uint2,
        addr,
        jettonWallet: null,
        amount: 0,
        received: false,
        walletUnverified: false,
        bounces: 0,
        claimable: false,
    };
}

fun main() {
    println("=== SwapEscrowNosup testnet smoke: happy path ===");
    println("Broadcasting to real network: {}", net.isBroadcasting());

    val wallet1 = scripts.wallet("wallet1"); // owner1
    val wallet2 = scripts.wallet("wallet2"); // owner2 / feeWallet
    println("wallet1 = {}", wallet1.address);
    println("wallet2 = {}", wallet2.address);

    val seed = runSeed(wallet1.address);
    println("run seed = {}", seed);

    val nft1 = deployNftMock(wallet1.address, wallet1.address, seed);
    println("nft1 (side1 -> wallet2) = {}", nft1);
    val nft2 = deployNftMock(wallet2.address, wallet2.address, seed + 1);
    println("nft2 (side2 -> wallet1) = {}", nft2);

    var assets: map<uint16, Asset> = [];
    assets.set(0, mkAsset(1, nft1));
    assets.set(1, mkAsset(2, nft2));
    val initStorage = Storage {
        swapId: seed,
        phase: PHASE_ACTIVE,
        owner1: wallet1.address,
        owner2: wallet2.address,
        feeWallet: wallet2.address,
        assetsCount: 2,
        required1Count: 1,
        required2Count: 1,
        received1Count: 0,
        received2Count: 0,
        pendingWallets: 0,
        jettonsCount: 0,
        receivedJettons1: 0,
        receivedJettons2: 0,
        assets,
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
        dist: DistState {
            mode: DIST_IDLE,
            cursor: 0,
        }.toCell(),
    };
    val escrow = SwapEscrowNosup.fromStorage(initStorage);
    println("SwapEscrowNosup = {}", escrow.address);
    waitFirst(
        net.send(
            wallet1.address,
            createMessage({
                bounce: false,
                value: ton("0.05"),
                dest: { stateInit: escrow.stateInit! },
                body: textBody("deploy_fee"),
            }),
        ),
        "deploy SwapEscrowNosup",
    );

    waitFirst(
        escrow.sendAny(
            wallet1.address,
            textBody("service_fee_owner1"),
            { value: SERVICE_FEE, bounce: true },
        ),
        "service_fee_owner1",
    );
    waitTrace(depositNft(wallet1.address, nft1, escrow.address, 0), "deposit nft1 (hint 0)");
    waitFirst(
        escrow.sendAny(
            wallet2.address,
            textBody("service_fee_owner2"),
            { value: SERVICE_FEE, bounce: true },
        ),
        "service_fee_owner2",
    );
    waitTrace(
        depositNft(wallet2.address, nft2, escrow.address, 1),
        "deposit nft2 (hint 1; execute trigger)",
    );

    val phaseAfter = net.runGetMethod<int>(escrow.address, "phase");
    val status0 = net.runGetMethod<(bool, bool, int)>(escrow.address, "assetStatus", [0]);
    val status1 = net.runGetMethod<(bool, bool, int)>(escrow.address, "assetStatus", [1]);
    val nft1Owner = net.runGetMethod<address>(nft1, "ownerAddr");
    val nft2Owner = net.runGetMethod<address>(nft2, "ownerAddr");

    println("");
    println("=== RESULT ===");
    println("phase = {} (expected 3 = PHASE_DONE)", phaseAfter);
    println(
        "assetStatus(0) = received={} claimable={} bounces={}",
        status0.0,
        status0.1,
        status0.2,
    );
    println(
        "assetStatus(1) = received={} claimable={} bounces={}",
        status1.0,
        status1.1,
        status1.2,
    );
    println("nft1 owner = {} (expected wallet2 {})", nft1Owner, wallet2.address);
    println("nft2 owner = {} (expected wallet1 {})", nft2Owner, wallet1.address);

    val ok = phaseAfter == PHASE_DONE && nft1Owner == wallet2.address &&
        nft2Owner == wallet1.address &&
        !status0.1 &&
        !status1.1 &&
        status0.2 == 0 &&
        status1.2 == 0;
    if (ok) {
        println("SMOKE PASSED: happy path delivered both assets, nothing marked claimable.");
    } else {
        println("SMOKE FAILED");
    }
    println("");
    println("escrow: https://testnet.tonviewer.com/{}", escrow.address);
}
