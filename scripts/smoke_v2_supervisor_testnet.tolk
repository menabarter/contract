// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Testnet smoke: SwapEscrowV2's supervisor commands on the live network.
//
// Deal A (1x1 NFT): both fees and side 1's NFT are in; the supervisor sends
// emergency_return_assets → CANCELLED, the NFT is back with side 1.
// Deal B (2 NFTs of side 1, none of side 2): both deliveries to side 2 are
// made to bounce, so the deal reaches DONE with both NFTs claimable; the
// supervisor then sends ForceDeliver(0, fallback = false) → side 2 gets the
// first NFT, and ForceDeliver(1, fallback = true) → the supervisor gets the
// second.
//
// Wallets (Acton): wallet1 = owner1, wallet2 = owner2 and fee wallet,
// v2-sup = the supervisor.
// Run: acton script scripts/smoke_v2_supervisor_testnet.tolk [--net testnet]
// Budget: ~1 TON net across the three wallets.
import "@acton/build"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/messages"
import "@contracts/nft_item_mock"
import "@wrappers/SwapEscrowV2.gen"
import "@contracts/shared/types"
import "@contracts/v2/storage"

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

// A per-run seed, so every run gets fresh mock and escrow addresses.
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

fun setReject(sender: address, nft: address, reject: bool): SendResultList {
    return net.send(
        sender,
        createMessage({
            bounce: false,
            value: ton("0.03"),
            dest: nft,
            body: SetNftReject {
                queryId: 0,
                reject,
            },
        }),
    );
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

fun dealStorage(
    seed: int,
    owner1: address,
    owner2: address,
    supervisor: address,
    assets: map<uint16, Asset>,
    count: int,
    req1: int,
    req2: int,
): Storage {
    return Storage {
        swapId: seed,
        phase: PHASE_ACTIVE,
        owner1,
        owner2,
        feeWallet: owner2,
        assetsCount: count as uint16,
        required1Count: req1 as uint16,
        required2Count: req2 as uint16,
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
        sup: SupervisorState {
            supervisor,
            rescueAssets: [],
            rescueCount: 0,
        }.toCell(),
        dist: DistState {
            mode: DIST_IDLE,
            cursor: 0,
        }.toCell(),
    };
}

fun deployEscrow(deployer: address, st: Storage, label: string): SwapEscrowV2 {
    val escrow = SwapEscrowV2.fromStorage(st);
    println("{} = {}", label, escrow.address);
    waitFirst(
        net.send(
            deployer,
            createMessage({
                bounce: false,
                value: ton("0.05"),
                dest: { stateInit: escrow.stateInit! },
                body: textBody("deploy_fee"),
            }),
        ),
        label,
    );
    return escrow;
}

fun payFee(escrow: SwapEscrowV2, from: address, cmd: string) {
    waitFirst(escrow.sendAny(from, textBody(cmd), { value: SERVICE_FEE, bounce: true }), cmd);
}

fun main() {
    println("=== SwapEscrowV2 testnet smoke: supervisor commands ===");
    println("Broadcasting to real network: {}", net.isBroadcasting());

    val wallet1 = scripts.wallet("wallet1");
    val wallet2 = scripts.wallet("wallet2");
    val sup = scripts.wallet("v2-sup");
    println("wallet1 = {}", wallet1.address);
    println("wallet2 = {}", wallet2.address);
    println("v2-sup = {}", sup.address);
    val seed = runSeed(wallet1.address);
    println("run seed = {}", seed);

    // ── Deal A: emergency_return_assets ──
    val a1 = deployNftMock(wallet1.address, wallet1.address, seed);
    val a2 = deployNftMock(wallet2.address, wallet2.address, seed + 1);
    var assetsA: map<uint16, Asset> = [];
    assetsA.set(0, mkAsset(1, a1));
    assetsA.set(1, mkAsset(2, a2));
    val escrowA = deployEscrow(
        wallet1.address,
        dealStorage(
            seed,
            wallet1.address,
            wallet2.address,
            sup.address,
            assetsA,
            2,
            1,
            1,
        ),
        "deal A",
    );
    payFee(escrowA, wallet1.address, "service_fee_owner1");
    payFee(escrowA, wallet2.address, "service_fee_owner2");
    waitTrace(depositNft(wallet1.address, a1, escrowA.address, 0), "deal A: deposit a1");
    waitTrace(
        escrowA.sendAny(
            sup.address,
            textBody("emergency_return_assets"),
            { value: ton("0.1"), bounce: true },
        ),
        "deal A: emergency_return_assets",
    );
    val phaseA = net.runGetMethod<int>(escrowA.address, "phase");
    val a1Owner = net.runGetMethod<address>(a1, "ownerAddr");
    println("deal A: phase = {} (expect 4 = CANCELLED)", phaseA);
    println("deal A: a1 back with wallet1 = {}", a1Owner == wallet1.address);

    // ── Deal B: ForceDeliver after bounced deliveries ──
    val b0 = deployNftMock(wallet1.address, wallet1.address, seed + 2);
    val b1 = deployNftMock(wallet1.address, wallet1.address, seed + 3);
    var assetsB: map<uint16, Asset> = [];
    assetsB.set(0, mkAsset(1, b0));
    assetsB.set(1, mkAsset(1, b1));
    val escrowB = deployEscrow(
        wallet1.address,
        dealStorage(
            seed + 1,
            wallet1.address,
            wallet2.address,
            sup.address,
            assetsB,
            2,
            2,
            0,
        ),
        "deal B",
    );
    payFee(escrowB, wallet1.address, "service_fee_owner1");
    // Side 2 deposits no asset; its half of the shared costs comes as an
    // owner's deploy_fee, which counts as its payment.
    waitFirst(
        escrowB.sendAny(
            wallet2.address,
            textBody("deploy_fee"),
            { value: ton("0.05"), bounce: true },
        ),
        "deal B: deploy_fee from wallet2",
    );
    waitTrace(depositNft(wallet1.address, b0, escrowB.address, 0), "deal B: deposit b0");
    waitTrace(depositNft(wallet1.address, b1, escrowB.address, 1), "deal B: deposit b1");
    // Both items, now held by the escrow, refuse transfers; side 2's fee
    // then completes the deal, and both deliveries bounce.
    waitFirst(setReject(wallet2.address, b0, true), "deal B: SetNftReject(true) on b0");
    waitFirst(setReject(wallet2.address, b1, true), "deal B: SetNftReject(true) on b1");
    waitTrace(
        escrowB.sendAny(
            wallet2.address,
            textBody("service_fee_owner2"),
            { value: SERVICE_FEE, bounce: true },
        ),
        "deal B: service_fee_owner2 (executes; both deliveries bounce)",
    );
    val phaseB = net.runGetMethod<int>(escrowB.address, "phase");
    val s0 = net.runGetMethod<(bool, bool, int)>(escrowB.address, "assetStatus", [0]);
    val s1 = net.runGetMethod<(bool, bool, int)>(escrowB.address, "assetStatus", [1]);
    println("deal B: phase = {} (expect 3 = DONE)", phaseB);
    println("deal B: claimable b0 = {}, b1 = {} (expect both true)", s0.1, s1.1);
    waitFirst(setReject(wallet2.address, b0, false), "deal B: SetNftReject(false) on b0");
    waitFirst(setReject(wallet2.address, b1, false), "deal B: SetNftReject(false) on b1");
    waitTrace(
        escrowB.sendForceDeliver(sup.address, 0, 0, false, { value: ton("0.1"), bounce: true }),
        "deal B: ForceDeliver(0, false)",
    );
    waitTrace(
        escrowB.sendForceDeliver(sup.address, 0, 1, true, { value: ton("0.1"), bounce: true }),
        "deal B: ForceDeliver(1, true)",
    );
    val b0Owner = net.runGetMethod<address>(b0, "ownerAddr");
    val b1Owner = net.runGetMethod<address>(b1, "ownerAddr");

    println("");
    println("=== RESULT ===");
    println("deal A phase {} (expected 4), a1 owner {} (expected wallet1)", phaseA, a1Owner);
    println("deal B phase {} (expected 3)", phaseB);
    println("b0 owner {} (expected wallet2 {})", b0Owner, wallet2.address);
    println("b1 owner {} (expected v2-sup {})", b1Owner, sup.address);
    val ok = phaseA == PHASE_CANCELLED && a1Owner == wallet1.address && phaseB == PHASE_DONE &&
        s0.1 &&
        s1.1 &&
        b0Owner == wallet2.address &&
        b1Owner == sup.address;
    if (ok) {
        println("SMOKE PASSED: emergency_return and ForceDeliver verified.");
    } else {
        println("SMOKE FAILED: see above.");
    }
    println("");
    println("deal A: https://testnet.tonviewer.com/{}", escrowA.address);
    println("deal B: https://testnet.tonviewer.com/{}", escrowB.address);
}
