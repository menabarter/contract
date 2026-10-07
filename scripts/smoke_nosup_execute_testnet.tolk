// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Testnet smoke: SwapEscrowNosup execute_swap on an underfunded deal — a 1x1
// NFT deal in which side 2 owes a TON leg. Both fees and both NFTs are in, but
// the leg is unpaid, so the last deposit does not execute. Side 2 reads
// executionShortfall() and sends execute_swap carrying exactly that figure:
// the payment and the execution happen in one message.
//
// Checked on the live network:
//   • the deal stays ACTIVE while the leg is unpaid;
//   • executionShortfall() for side 2 covers at least the unpaid leg;
//   • execute_swap carrying exactly the getter's figure executes the deal:
//     real fees do not exceed what the getter names;
//   • each NFT ends up with the other side and side 1 receives the TON leg;
//   • the escrow keeps its storage floor afterwards.
//
// Run: acton script scripts/smoke_nosup_execute_testnet.tolk [--net testnet]
// Budget: ~0.6 TON net (the TON leg moves from wallet2 to wallet1).
import "@acton/build"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/messages"
import "@contracts/nft_item_mock"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"

const NFT_DEPLOY_VALUE: coins = ton("0.03")
const NFT_FORWARD: coins = ton("0.2")
const GRAM2: coins = ton("0.3")
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
        sent: false,
        bounces: 0,
        claimable: false,
    };
}

fun main() {
    println("=== SwapEscrowNosup testnet smoke: execute_swap on an underfunded deal ===");
    println("Broadcasting to real network: {}", net.isBroadcasting());

    val wallet1 = scripts.wallet("wallet1"); // owner1 / feeWallet
    val wallet2 = scripts.wallet("wallet2"); // owner2, owes the TON leg, executes
    println("wallet1 = {}", wallet1.address);
    println("wallet2 = {}", wallet2.address);

    val seed = runSeed(wallet1.address);
    println("run seed = {}", seed);

    val nft1 = deployNftMock(wallet1.address, wallet1.address, seed);
    println("nft1 (side 1 -> wallet2) = {}", nft1);
    val nft2 = deployNftMock(wallet2.address, wallet2.address, seed + 1);
    println("nft2 (side 2 -> wallet1) = {}", nft2);

    var assets: map<uint16, Asset> = [];
    assets.set(0, mkAsset(1, nft1));
    assets.set(1, mkAsset(2, nft2));
    val initStorage = Storage {
        swapId: seed,
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
            gram2Amount: GRAM2,
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
    waitTrace(depositNft(wallet1.address, nft1, escrow.address, 0), "deposit nft1");
    waitFirst(
        escrow.sendAny(
            wallet2.address,
            textBody("service_fee_owner2"),
            { value: SERVICE_FEE, bounce: true },
        ),
        "service_fee_owner2",
    );
    waitTrace(depositNft(wallet2.address, nft2, escrow.address, 1), "deposit nft2 (leg unpaid)");

    val phaseBefore = net.runGetMethod<int>(escrow.address, "phase");
    println("phase before execute = {} (expected 1 = ACTIVE)", phaseBefore);
    val shortfall = net.runGetMethod<(int, int)>(escrow.address, "executionShortfall");
    println("executionShortfall = side1 {} / side2 {}", shortfall.0, shortfall.1);

    // A wallet without enough balance drops the outgoing message silently,
    // which would look like the escrow ignoring execute_swap.
    val w2Balance = scripts.fetchAccountBalance(wallet2.address);
    if (w2Balance < shortfall.1 + ton("0.02")) {
        println("[ABORT] wallet2 holds {}, not enough to send {} — top it up and rerun", w2Balance, shortfall.1);
        return;
    }

    val w1Before = scripts.fetchAccountBalance(wallet1.address);
    waitTrace(
        escrow.sendAny(
            wallet2.address,
            textBody("execute_swap"),
            { value: shortfall.1, bounce: true },
        ),
        "execute_swap from wallet2 (exactly the shortfall)",
    );

    val phaseAfter = net.runGetMethod<int>(escrow.address, "phase");
    val nft1Owner = net.runGetMethod<address>(nft1, "ownerAddr");
    val nft2Owner = net.runGetMethod<address>(nft2, "ownerAddr");
    val w1Gain = scripts.fetchAccountBalance(wallet1.address) - w1Before;
    val floor = net.runGetMethod<int>(escrow.address, "storageFloor");
    val escrowBalance = scripts.fetchAccountBalance(escrow.address);

    println("");
    println("=== RESULT ===");
    println("phase = {} (expected 3 = PHASE_DONE)", phaseAfter);
    println("nft1 owner = {} (expected wallet2 {})", nft1Owner, wallet2.address);
    println("nft2 owner = {} (expected wallet1 {})", nft2Owner, wallet1.address);
    println("wallet1 received {} (expected >= TON leg {})", w1Gain, GRAM2);
    println("escrow balance = {}, storageFloor = {} (expected balance >= floor)", escrowBalance, floor);

    val ok = phaseBefore == PHASE_ACTIVE && shortfall.0 == 0 && shortfall.1 >= GRAM2 &&
        phaseAfter == PHASE_DONE &&
        nft1Owner == wallet2.address &&
        nft2Owner == wallet1.address &&
        w1Gain >= GRAM2 &&
        escrowBalance >= floor;
    if (ok) {
        println("SMOKE PASSED: execute_swap on exactly the getter's figure paid the leg and executed.");
    } else {
        println("SMOKE FAILED");
    }
    println("");
    println("escrow: https://testnet.tonviewer.com/{}", escrow.address);
}
