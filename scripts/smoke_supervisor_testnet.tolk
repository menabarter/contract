// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Testnet smoke: SUPERVISOR flow on the live network —
// broken recipient → bounce AFTER finalization → asset stuck → rescue_nft.
//
// WHY THIS SCENARIO SPECIFICALLY (and not kick-redelivery):
// a 2-asset deal goes through the fast path (≤100), i.e. distribution runs
// in a SINGLE transaction and phase → DONE immediately. The bounce of the
// rejected transfer arrives AFTER finalization, when dist.mode == IDLE, so
// there's nothing left to continue, and `kick` fundamentally does NOT
// redeliver such an asset — this is the documented exception to "every
// received asset is delivered or returned", confirmed empirically. The only way to get the asset out is
// the supervisor's `rescue_nft`. A live check of kick-redelivery would
// require a deal with >100 assets (the batch path), which is already proven
// by the live run of smoke_batch_testnet (a 111-transaction trace).
//
// Checked on the live network:
//   • the transfer to the broken recipient actually bounces (real NFT contract);
//   • an exception on ONE asset does not block the deal: phase = DONE, the
//     other asset is delivered normally;
//   • while the NFT contract keeps rejecting transfers, not even rescue can
//     move the asset out (a property of the EXTERNAL contract);
//   • after the contract is "fixed", supervisor rescue_nft extracts the asset.
//
// Run: acton script scripts/smoke_supervisor_testnet.tolk [--net testnet]
// Budget: ~0.6 TON net.
import "@acton/build"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/messages"
import "@contracts/nft_item_mock"
import "@contracts/storage"
import "@wrappers/SwapEscrow.gen"

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
        sent: false,
        bounces: 0,
        abandoned: false,
    };
}

fun main() {
    println("=== SwapEscrow testnet smoke: SUPERVISOR rescue after bounce ===");
    println("Broadcasting to real network: {}", net.isBroadcasting());

    val wallet1 = scripts.wallet("wallet1"); // owner1 / feeWallet / supervisor
    val wallet2 = scripts.wallet("wallet2"); // owner2
    println("wallet1 (also supervisor) = {}", wallet1.address);
    println("wallet2 = {}", wallet2.address);

    // 1x1 deal: nftBad from side 1 (goes to wallet2 — this is the one we break),
    // nftGood from side 2 (goes to wallet1 — delivered normally).
    val nftBad = deployNftMock(wallet1.address, wallet1.address, 85001);
    println("nftBad (side1, will be broken) = {}", nftBad);
    val nftGood = deployNftMock(wallet2.address, wallet2.address, 85002);
    println("nftGood (side2) = {}", nftGood);

    var assets: map<uint16, Asset> = [];
    assets.set(0, mkAsset(1, nftBad));
    assets.set(1, mkAsset(2, nftGood));
    val initStorage = Storage {
        swapId: 90501,
        phase: PHASE_ACTIVE,
        owner1: wallet1.address,
        owner2: wallet2.address,
        feeWallet: wallet1.address,
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

    // Fees and deposits (both assets deposited normally — the mock is still healthy).
    waitFirst(
        escrow.sendAny(
            wallet1.address,
            textBody("service_fee_owner1"),
            { value: SERVICE_FEE, bounce: true },
        ),
        "service_fee_owner1",
    );
    waitTrace(depositNft(wallet1.address, nftBad, escrow.address, 0), "deposit nftBad (hint 0)");
    waitTrace(depositNft(wallet2.address, nftGood, escrow.address, 1), "deposit nftGood (hint 1)");

    // BREAK the recipient AFTER the deposits and BEFORE the trigger: otherwise
    // the deposit itself would break (the mock rejects ANY NftTransfer), and
    // auto-execution would never trigger.
    waitFirst(setReject(wallet1.address, nftBad, true), "SetNftReject(true) on nftBad");

    // Trigger: the second fee completes the conditions → distribution runs, the nftBad transfer bounces.
    waitTrace(
        escrow.sendAny(
            wallet2.address,
            textBody("service_fee_owner2"),
            { value: SERVICE_FEE, bounce: true },
        ),
        "service_fee_owner2 (execute trigger; nftBad transfer will bounce)",
    );

    val phaseAfter = net.runGetMethod<int>(escrow.address, "phase");
    val badOwner1 = net.runGetMethod<address>(nftBad, "ownerAddr");
    val goodOwner = net.runGetMethod<address>(nftGood, "ownerAddr");
    println("");
    println("after execute: phase={} (expect 3=DONE despite the broken recipient)", phaseAfter);
    println("nftBad  stuck on escrow = {}", badOwner1 == escrow.address);
    println("nftGood delivered to wallet1 = {}", goodOwner == wallet1.address);

    // While the mock keeps rejecting transfers, rescue can't move the asset out either.
    waitTrace(
        escrow.sendRescueNft(wallet1.address, nftBad, { value: ton("0.1") }),
        "rescue_nft while still broken (expected to fail on the NFT side)",
    );
    val badOwner2 = net.runGetMethod<address>(nftBad, "ownerAddr");
    println("nftBad still on escrow after rescue-while-broken = {}", badOwner2 == escrow.address);

    // "Fixing" the external contract → rescue extracts the asset to the supervisor.
    waitFirst(setReject(wallet1.address, nftBad, false), "SetNftReject(false) — recipient fixed");
    waitTrace(
        escrow.sendRescueNft(wallet1.address, nftBad, { value: ton("0.1") }),
        "rescue_nft after fix",
    );

    val badOwnerFinal = net.runGetMethod<address>(nftBad, "ownerAddr");
    println("");
    println("=== RESULT ===");
    println("escrow.phase() = {} (expected 3 = PHASE_DONE)", phaseAfter);
    println("nftGood owner = {} (expected wallet1 {})", goodOwner, wallet1.address);
    println(
        "nftBad owner after rescue = {} (expected supervisor/wallet1 {})",
        badOwnerFinal,
        wallet1.address,
    );
    val ok = phaseAfter == PHASE_DONE && goodOwner == wallet1.address &&
    badOwner1 == escrow.address &&
    badOwner2 == escrow.address &&
    badOwnerFinal == wallet1.address;
    if (ok) {
        println("SMOKE PASSED: documented exception (a) + supervisor rescue verified live.");
    } else {
        println("SMOKE FAILED: see above.");
    }
    println("");
    println("SwapEscrow: https://testnet.tonviewer.com/{}", escrow.address);
    println("nftBad: https://testnet.tonviewer.com/{}", nftBad);
}
