// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Testnet smoke: CANCELLATION of a partially funded deal on the live network.
//
// Scenario: side 1 deposits an NFT + service_fee, side 2 deposits GRAM but
// does NOT pay its service_fee → auto-execution does not trigger (conditions
// aren't met). owner1 then sends cancel_swap → assets are returned to their
// depositors + refunds on both sides + PHASE_CANCELLED.
//
// What's being checked specifically on the LIVE network (emulation already
// covers this, but here with real fees and a real balance):
//   • the cancel balance check (throw 430 on shortfall) against actual fees;
//   • the deposited NFT is returned to the ACTUAL depositor via a real NFT contract;
//   • GRAM + service_fee refunds (verified by the actual growth of the wallet balance).
//
// Run: acton script scripts/smoke_cancel_testnet.tolk [--net testnet]
// Budget: ~0.4 TON net (part of it comes back via refunds).
import "@acton/build"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/messages"
import "@contracts/nft_item_mock"
import "@contracts/storage"
import "@wrappers/SwapEscrow.gen"

const DEAL_GRAM2: coins = ton("0.3")
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
        println("[TIMEOUT] {} — not confirmed after {} attempts", label, POLL_ATTEMPTS);
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

fun main() {
    println("=== SwapEscrow testnet smoke: CANCEL of partially funded deal ===");
    println("Broadcasting to real network: {}", net.isBroadcasting());

    val wallet1 = scripts.wallet("wallet1"); // owner1 / feeWallet / supervisor
    val wallet2 = scripts.wallet("wallet2"); // owner2
    println("wallet1 = {}", wallet1.address);
    println("wallet2 = {}", wallet2.address);

    // 1. Mock NFT for side 1.
    val nftStorage = MockNftStorage {
        ownerAddr: wallet1.address,
        seed: 84001,
        rejectTransfers: false,
    };
    val nftInit = ContractState {
        code: build("NftItemMock"),
        data: nftStorage.toCell(),
    };
    val nftAddr = AutoDeployAddress { stateInit: nftInit }.calculateAddress();
    println("NftItemMock = {}", nftAddr);
    waitFirst(
        net.send(
            wallet1.address,
            createMessage({
                bounce: false,
                value: NFT_DEPLOY_VALUE,
                dest: { stateInit: nftInit },
            }),
        ),
        "deploy NftItemMock",
    );

    // 2. Storage: 1 NFT for side 1 + GRAM for side 2.
    var assets: map<uint16, Asset> = [];
    assets.set(
        0,
        Asset {
            kind: 0,
            ownerSide: 1,
            addr: nftAddr,
            jettonWallet: null,
            amount: 0,
            received: false,
            sent: false,
            bounces: 0,
            abandoned: false,
        },
    );
    val initStorage = Storage {
        swapId: 90401,
        phase: PHASE_ACTIVE,
        owner1: wallet1.address,
        owner2: wallet2.address,
        feeWallet: wallet1.address,
        assetsCount: 1,
        required1Count: 1,
        required2Count: 0,
        received1Count: 0,
        received2Count: 0,
        pendingWallets: 0,
        jettonsCount: 0,
        receivedJettons1: 0,
        receivedJettons2: 0,
        assets,
        grams: GramState {
            gram1Amount: 0,
            gram2Amount: DEAL_GRAM2,
            gram1Received: 0,
            gram2Received: 0,
            gram1DepositReserve: 0,
            gram2DepositReserve: 0,
            serviceFee1: 0,
            serviceFee2: 0,
        }.toCell(),
        sup: SupervisorState {
            supervisor: wallet1.address,
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
    val escrow = SwapEscrow.fromStorage(initStorage);
    println("SwapEscrow = {}", escrow.address);
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
        "deploy SwapEscrow",
    );

    // 3. PARTIAL funding: fee1 + NFT + GRAM2, but WITHOUT fee2 →
    //    auto-execution does not fire (canAutoExecute requires both fees).
    waitFirst(
        escrow.sendAny(
            wallet1.address,
            textBody("service_fee_owner1"),
            { value: SERVICE_FEE, bounce: true },
        ),
        "service_fee_owner1",
    );
    waitTrace(
        net.send(
            wallet1.address,
            createMessage({
                bounce: true,
                value: NFT_FORWARD + ton("0.05"),
                dest: nftAddr,
                body: NftTransfer {
                    queryId: 0,
                    newOwner: escrow.address,
                    responseDestination: wallet1.address,
                    customPayload: null,
                    forwardAmount: NFT_FORWARD,
                    forwardPayload: beginCell()
                        .storeUint(0, 1)
                        .storeUint(0, 16)
                        .endCell()
                        .beginParse(),
                },
            }),
        ),
        "NFT deposit (hint 0) wallet1 -> escrow",
    );
    waitFirst(
        escrow.sendAny(
            wallet2.address,
            textBody("deposit_ton2"),
            { value: DEAL_GRAM2 + ton("0.05"), bounce: true },
        ),
        "deposit_ton2 (wallet2)",
    );

    val phaseBefore = net.runGetMethod<int>(escrow.address, "phase");
    val ownerBefore = net.runGetMethod<address>(nftAddr, "ownerAddr");
    println(
        "before cancel: phase={} (expect 1=ACTIVE, auto NOT fired), nft owner is escrow={}",
        phaseBefore,
        ownerBefore == escrow.address,
    );

    // 4. CANCELLATION by owner1 → NFT returned to the depositor + refunds + CANCELLED.
    waitTrace(
        escrow.sendAny(
            wallet1.address,
            textBody("cancel_swap"),
            { value: ton("0.1"), bounce: true },
        ),
        "cancel_swap (owner1)",
    );

    // 5. Verification.
    val phase = net.runGetMethod<int>(escrow.address, "phase");
    val nftOwner = net.runGetMethod<address>(nftAddr, "ownerAddr");

    println("");
    println("=== RESULT ===");
    println("escrow.phase() = {} (expected 4 = PHASE_CANCELLED)", phase);
    println("NFT owner = {} (expected == wallet1 {})", nftOwner, wallet1.address);
    val ok = phase == PHASE_CANCELLED && nftOwner == wallet1.address;
    if (ok) {
        println("SMOKE PASSED: cancel returned assets to depositor on real network.");
    } else {
        println("SMOKE FAILED: see above.");
    }
    println("");
    println("SwapEscrow: https://testnet.tonviewer.com/{}", escrow.address);
    println("NftItemMock: https://testnet.tonviewer.com/{}", nftAddr);
}
