// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Testnet smoke (BATCH deal, >100 assets): 101 NFTs, 51 from side 1 (wallet1)
// <-> 50 from side 2 (wallet2). assetsCount = 101 > FAST_PATH_MAX_ASSETS (100)
// → auto-execution goes into EXECUTING and distributes in BATCHES via the
// ContinueDistribution self-trigger chain (BATCH_MAX_SENDS = 50):
//   batch 1: assets 0..49   + self-msg ContinueDistribution
//   batch 2: assets 50..99  + self-msg ContinueDistribution
//   batch 3: asset 100      + self-msg → a separate final transaction → DONE
// On the LIVE network these are DIFFERENT asynchronous transactions (in the
// emulator the cascade applies atomically within a single net.send) — this
// is exactly what's being checked here, which emulation cannot prove.
//
// Run: acton script scripts/smoke_batch_testnet.tolk [--net testnet]
//   Without --net — emulation (validates the script itself for free, DONE atomically).
//   With --net testnet — broadcast; wallet1/wallet2 must be funded
//   (~10 TON each: 101 NFT deploys + 101 deposits; see the budget breakdown).
//
// Each side pays SERVICE_FEE = 0.1 TON. Side 1's NFTs go to owner2 (wallet2),
// side 2's NFTs go to owner1 (wallet1). Order in Storage: all of side 1's
// NFTs first (indices 0..50), then side 2's (51..100) — hence the hints.
import "@acton/build"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/messages"
import "@contracts/nft_item_mock"
import "@contracts/storage"
import "@wrappers/SwapEscrow.gen"

const SIDE1_COUNT = 51 // side 1's NFTs (wallet1) → go to wallet2
const SIDE2_COUNT = 50 // side 2's NFTs (wallet2) → go to wallet1
const TOTAL = SIDE1_COUNT + SIDE2_COUNT // 101 > 100 → batch path

// The mock NFT is tiny (ownerAddr+seed+bool) and gets topped up by the
// deposit's own value (0.05) on acceptance — 0.03 for deploy is enough with margin.
const NFT_DEPLOY_VALUE: coins = ton("0.03")
// The deposit forward is what the NFT forwards to the escrow (it settles
// into the raw balance and, in aggregate, funds the distribution; NOT the
// service_fee, which is earmarked for fee/refund and accounted for
// separately in minBalanceForSwap).
// minBalanceForSwap(101 NFT) ≈ 0.03*101 + gasReserve(~0.46) + 2*0.1 fee ≈ 3.7 TON.
// 101 * ~0.045 (0.05 forward minus acceptance gas) ≈ 4.5 TON in the escrow — covers it.
const NFT_FORWARD: coins = ton("0.05")

const POLL_ATTEMPTS = 30
const POLL_SLEEP_MS = 3000
// The final transaction triggers the entire async chain (3 batches + final)
// — we allow more attempts, since a cascade of 101 transfers settles slower
// on the live network.
const POLL_ATTEMPTS_FINAL = 80

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

fun waitTraceN(res: SendResultList, label: string, attempts: int): SendResultList {
    val applied = res.waitForTrace(false, attempts, POLL_SLEEP_MS);
    if (applied == null) {
        println("[TIMEOUT] {} (trace) — not confirmed after {} attempts", label, attempts);
    } else {
        println("[OK] {} (full trace confirmed)", label);
    }
    return res;
}

fun deployNft(deployer: address, owner: address, seed: int): address {
    val st = MockNftStorage {
        ownerAddr: owner,
        seed: seed as uint32,
        rejectTransfers: false,
    };
    val init = ContractState {
        code: build("NftItemMock"),
        data: st.toCell(),
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

// Deposit an NFT into the escrow with an O(1) hint (asset_index in
// forwardPayload: either-0 + uint16 — the same format as for jettons, see
// parseAssetIndexHint). Without the hint, the linear acceptance scan hits an
// ~850-gas ceiling at 101 assets.
fun sendNftHint(owner: address, nft: address, escrow: address, idx: int): SendResultList {
    val payload = beginCell().storeUint(0, 1).storeUint(idx, 16).endCell().beginParse();
    return net.send(
        owner,
        createMessage({
            bounce: true,
            value: NFT_FORWARD + ton("0.05"),
            dest: nft,
            body: NftTransfer {
                queryId: idx,
                newOwner: escrow,
                responseDestination: owner,
                customPayload: null,
                forwardAmount: NFT_FORWARD,
                forwardPayload: payload,
            },
        }),
    );
}

fun emptyAsset(ownerSide: int, addr: address): Asset {
    return Asset {
        kind: 0,
        ownerSide: ownerSide as uint2,
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
    println(
        "=== SwapEscrow testnet smoke: BATCH deal ({} NFT, {}<->{}) ===",
        TOTAL,
        SIDE1_COUNT,
        SIDE2_COUNT,
    );
    println("Broadcasting to real network: {}", net.isBroadcasting());

    val wallet1 = scripts.wallet("wallet1"); // side 1: 51 NFTs → go to wallet2
    val wallet2 = scripts.wallet("wallet2"); // side 2: 50 NFTs → go to wallet1
    println("wallet1 (owner1/feeWallet/supervisor) = {}", wallet1.address);
    println("wallet2 (owner2)                       = {}", wallet2.address);

    // 1. Deploy 101 mock NFTs: indices 0..50 owned by wallet1 (side 1),
    //    51..100 by wallet2 (side 2). Addresses are deterministic (AutoDeployAddress).
    var nftAddrs: map<uint16, address> = [];
    var i = 0;
    while (i < TOTAL) {
        val owner = i < SIDE1_COUNT ? wallet1.address : wallet2.address;
        val deployer = owner;
        val addr = deployNft(deployer, owner, 80000 + i);
        nftAddrs.set(i as uint16, addr);
        i += 1;
    }
    println("deployed {} NFT mocks", TOTAL);

    // 2. Storage: 101 NFT assets, no jettons or GRAM → phase ACTIVE right away
    //    (no TEP-89 discovery needed, pendingWallets = 0).
    var assets: map<uint16, Asset> = [];
    i = 0;
    while (i < TOTAL) {
        val side = i < SIDE1_COUNT ? 1 : 2;
        assets.set(i as uint16, emptyAsset(side, nftAddrs.mustGet(i as uint16)));
        i += 1;
    }
    val initStorage = Storage {
        swapId: 90101,
        phase: PHASE_ACTIVE,
        owner1: wallet1.address,
        owner2: wallet2.address,
        feeWallet: wallet1.address,
        assetsCount: TOTAL as uint16,
        required1Count: SIDE1_COUNT as uint16,
        required2Count: SIDE2_COUNT as uint16,
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
    println("SwapEscrow address = {}", escrow.address);

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
        "deploy SwapEscrow (deploy_fee)",
    );

    // 3. Service fee from both sides.
    waitFirst(
        escrow.sendAny(
            wallet1.address,
            textBody("service_fee_owner1"),
            { value: ton("0.1"), bounce: true },
        ),
        "service_fee_owner1",
    );
    waitFirst(
        escrow.sendAny(
            wallet2.address,
            textBody("service_fee_owner2"),
            { value: ton("0.1"), bounce: true },
        ),
        "service_fee_owner2",
    );

    // 4. Deposits: first all of side 1's NFTs (0..50), then side 2's (51..99),
    //    the LAST one (index 100) completes received2 = 50 and triggers the batch cascade.
    i = 0;
    while (i < TOTAL - 1) {
        val owner = i < SIDE1_COUNT ? wallet1.address : wallet2.address;
        waitFirst(
            sendNftHint(owner, nftAddrs.mustGet(i as uint16), escrow.address, i),
            "deposit NFT (non-trigger)",
        );
        i += 1;
    }

    // 5. Trigger: the last deposit (side 2, index 100) → auto-execution →
    //    EXECUTING → 3 batches through the async self-trigger chain → DONE.
    //    Wait for the WHOLE cascade of descendants (waitForTrace) with a
    //    higher attempt count.
    val trigger = sendNftHint(
        wallet2.address,
        nftAddrs.mustGet((TOTAL - 1) as uint16),
        escrow.address,
        TOTAL - 1,
    );
    waitTraceN(trigger, "deposit NFT #100 (BATCH trigger)", POLL_ATTEMPTS_FINAL);

    // 6. Safety kick: if the async chain is still EXECUTING (didn't finish
    //    or got parked), owner1 finishes it off with kick — not needed on
    //    the happy path, but this also exercises the recovery path.
    var phase = net.runGetMethod<int>(escrow.address, "phase");
    println("phase after trigger trace = {} (3 = DONE, 2 = EXECUTING)", phase);
    if (phase == PHASE_EXECUTING) {
        println("still EXECUTING → sending kick (owner1) to drain remaining batches");
        waitTraceN(
            escrow.sendAny(wallet1.address, textBody("kick"), { value: ton("0.2"), bounce: true }),
            "kick (drain distribution)",
            POLL_ATTEMPTS_FINAL,
        );
        phase = net.runGetMethod<int>(escrow.address, "phase");
        println("phase after kick = {}", phase);
    }

    // 7. Verification: phase == DONE + spot-check owners across batch
    //    boundaries (0, 49, 50 — end of batch 1 / start of batch 2; 100 —
    //    batch 3). Side 1's NFTs (idx < 51) → wallet2; side 2's (idx >= 51) → wallet1.
    val owner0 = net.runGetMethod<address>(nftAddrs.mustGet(0), "ownerAddr");
    val owner49 = net.runGetMethod<address>(nftAddrs.mustGet(49), "ownerAddr");
    val owner50 = net.runGetMethod<address>(nftAddrs.mustGet(50), "ownerAddr");
    val owner100 = net.runGetMethod<address>(nftAddrs.mustGet(100), "ownerAddr");

    println("");
    println("=== RESULT ===");
    println("escrow.phase() = {} (expected 3 = PHASE_DONE)", phase);
    println("nft[0]  owner = {} (side1 → expected wallet2 {})", owner0, wallet2.address);
    println("nft[49] owner = {} (side1 → expected wallet2 {})", owner49, wallet2.address);
    println("nft[50] owner = {} (side1 → expected wallet2 {})", owner50, wallet2.address);
    println("nft[100] owner = {} (side2 → expected wallet1 {})", owner100, wallet1.address);
    val ok = phase == PHASE_DONE && owner0 == wallet2.address && owner49 == wallet2.address &&
    owner50 == wallet2.address &&
    owner100 == wallet1.address;
    if (ok) {
        println("SMOKE PASSED: batch (>100) swap executed end-to-end via async self-trigger chain.");
    } else {
        println("SMOKE FAILED: final state does not match expectations, see above.");
    }

    println("");
    println("=== Tonviewer links (testnet.tonviewer.com) ===");
    println("wallet1: https://testnet.tonviewer.com/{}", wallet1.address);
    println("wallet2: https://testnet.tonviewer.com/{}", wallet2.address);
    println("SwapEscrow: https://testnet.tonviewer.com/{}", escrow.address);
}
