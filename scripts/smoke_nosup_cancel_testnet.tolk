// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Testnet smoke: SwapEscrowNosup cancel settlement — a 1x1 NFT deal in which
// side 1 has paid everything (a TON leg, its fee and its NFT) and side 2 has
// deposited its NFT with a forward too small to cover its own costs and has
// not paid its fee. Side 2 cancels.
//
// Checked on the live network:
//   • a cancel with a token amount is refused and the deal stays ACTIVE;
//   • a cancel carrying exactly cancelCost() goes through: real fees do not
//     exceed the getter's quote;
//   • both NFTs return to their owners;
//   • side 1 gets back at least its TON leg and its service fee;
//   • the escrow keeps its storage floor afterwards.
//
// Run: acton script scripts/smoke_nosup_cancel_testnet.tolk [--net testnet]
// Budget: ~0.3 TON net (the TON leg comes back).
import "@acton/build"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/messages"
import "@contracts/nft_item_mock"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "@contracts/shared/types"

const NFT_DEPLOY_VALUE: coins = ton("0.03")
const NFT_FORWARD1: coins = ton("0.05")
const NFT_FORWARD2: coins = ton("0.002") // below side 2's own costs
const GRAM1: coins = ton("0.3")
const CHEAP_CANCEL: coins = ton("0.005")
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

fun depositNft(
    owner: address,
    nft: address,
    escrow: address,
    hint: int,
    forward: coins,
): SendResultList {
    return net.send(
        owner,
        createMessage({
            bounce: true,
            value: forward + ton("0.05"),
            dest: nft,
            body: NftTransfer {
                queryId: hint,
                newOwner: escrow,
                responseDestination: owner,
                customPayload: null,
                forwardAmount: forward,
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
    println("=== SwapEscrowNosup testnet smoke: cancel settlement ===");
    println("Broadcasting to real network: {}", net.isBroadcasting());

    val wallet1 = scripts.wallet("wallet1"); // owner1 (funded side)
    val wallet2 = scripts.wallet("wallet2"); // owner2 (underfunded side, cancels) / feeWallet
    println("wallet1 = {}", wallet1.address);
    println("wallet2 = {}", wallet2.address);

    val seed = runSeed(wallet1.address);
    println("run seed = {}", seed);

    val nft1 = deployNftMock(wallet1.address, wallet1.address, seed);
    println("nft1 (side 1) = {}", nft1);
    val nft2 = deployNftMock(wallet2.address, wallet2.address, seed + 1);
    println("nft2 (side 2) = {}", nft2);

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
            gram1Amount: GRAM1,
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

    // Side 1 pays everything.
    waitFirst(
        escrow.sendAny(wallet1.address, textBody("deposit_ton1"), { value: GRAM1, bounce: true }),
        "deposit_ton1",
    );
    waitFirst(
        escrow.sendAny(
            wallet1.address,
            textBody("service_fee_owner1"),
            { value: SERVICE_FEE, bounce: true },
        ),
        "service_fee_owner1",
    );
    waitTrace(depositNft(wallet1.address, nft1, escrow.address, 0, NFT_FORWARD1), "deposit nft1");
    // Side 2 deposits its NFT with a small forward and no fee.
    waitTrace(depositNft(wallet2.address, nft2, escrow.address, 1, NFT_FORWARD2), "deposit nft2");

    val phaseBefore = net.runGetMethod<int>(escrow.address, "phase");
    println("phase before cancel = {} (expected 1 = ACTIVE)", phaseBefore);

    waitTrace(
        escrow.sendAny(
            wallet2.address,
            textBody("cancel_swap"),
            { value: CHEAP_CANCEL, bounce: true },
        ),
        "cancel_swap with a token amount (must be refused)",
    );
    val phaseAfterCheap = net.runGetMethod<int>(escrow.address, "phase");
    println("phase after cheap cancel = {} (expected 1 = ACTIVE)", phaseAfterCheap);

    val quote = net.runGetMethod<(int, int)>(escrow.address, "cancelCost");
    println("cancelCost = required {} / attach {}", quote.0, quote.1);
    val w1Before = scripts.fetchAccountBalance(wallet1.address);

    waitTrace(
        escrow.sendAny(wallet2.address, textBody("cancel_swap"), { value: quote.1, bounce: true }),
        "cancel_swap with exactly cancelCost",
    );

    val phaseAfter = net.runGetMethod<int>(escrow.address, "phase");
    val nft1Owner = net.runGetMethod<address>(nft1, "ownerAddr");
    val nft2Owner = net.runGetMethod<address>(nft2, "ownerAddr");
    val w1Gain = scripts.fetchAccountBalance(wallet1.address) - w1Before;
    val floor = net.runGetMethod<int>(escrow.address, "storageFloor");
    val escrowBalance = scripts.fetchAccountBalance(escrow.address);

    println("");
    println("=== RESULT ===");
    println("phase = {} (expected 4 = PHASE_CANCELLED)", phaseAfter);
    println("nft1 owner = {} (expected wallet1 {})", nft1Owner, wallet1.address);
    println("nft2 owner = {} (expected wallet2 {})", nft2Owner, wallet2.address);
    println("wallet1 received {} (expected >= TON leg + fee = {})", w1Gain, GRAM1 + SERVICE_FEE);
    println(
        "escrow balance = {}, storageFloor = {} (expected balance >= floor)",
        escrowBalance,
        floor,
    );

    val ok = phaseBefore == PHASE_ACTIVE && phaseAfterCheap == PHASE_ACTIVE &&
        phaseAfter == PHASE_CANCELLED &&
        nft1Owner == wallet1.address &&
        nft2Owner == wallet2.address &&
        w1Gain >= GRAM1 + SERVICE_FEE &&
        escrowBalance >= floor;
    if (ok) {
        println("SMOKE PASSED: cancel on exactly cancelCost settled and returned every asset.");
    } else {
        println("SMOKE FAILED");
    }
    println("");
    println("escrow: https://testnet.tonviewer.com/{}", escrow.address);
}
