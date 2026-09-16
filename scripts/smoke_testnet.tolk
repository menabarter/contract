// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Testnet smoke: a full 1x1 swap (1 NFT from wallet1 <-> 0.3 GRAM from wallet2)
// on the real network (acton script scripts/smoke_testnet.tolk --net testnet).
//
// Why a separate script instead of reusing tests/escrow_helpers.tolk: the
// test helpers use testing.treasury()/Treasury (emulated treasury addresses
// with no private keys) — they can't sign and send real external messages.
// The script uses scripts.wallet(), which resolves to a real wallet
// (wallets.toml) when run with --net.
//
// Without --net the script runs in emulation (scripts.wallet returns
// testing.treasury) — handy for a local check before broadcasting.
import "@acton/build"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/messages"
import "@contracts/nft_item_mock"
import "@contracts/storage"
import "@wrappers/SwapEscrow.gen"

// Side-2 GRAM amount (economics: SERVICE_FEE = 0.1 TON from each side,
// see contracts/storage.tolk). Budget for the whole check — ≤2 testnet GRAM per wallet.
const DEAL_GRAM2: coins = ton("0.3")
const NFT_DEPLOY_VALUE: coins = ton("0.1")
const NFT_FORWARD_VALUE: coins = ton("0.1")
const DEPOSIT_BUFFER: coins = ton("0.01")

// Retry/backoff for waiting on confirmation on the real network: the testnet
// API is shared and rate-limited (see .env.example), so we do NOT hammer it
// more than once every 3 seconds and cap the total number of attempts.
const POLL_ATTEMPTS = 30
const POLL_SLEEP_MS = 3000

fun textBody(text: string): cell {
    return beginCell().storeUint(0, 32).storeSlice(text.beginParse()).endCell();
}

// In --net mode, net.send() in broadcast mode only returns a pseudo
// transaction (see .acton/emulation/network.tolk: net.send doc) — only
// waitForFirstTransaction confirms actual inclusion in a block, and it
// implements the retry/backoff polling itself (this is the only waiting
// primitive available to Acton scripts — there is no separate sleep()
// function in the runtime). In emulation mode (without --net),
// waitForFirstTransaction returns immediately, since the trace has already
// been applied locally.
fun waitAndReport(res: SendResultList, label: string): SendResultList {
    val applied = res.waitForFirstTransaction(false, POLL_ATTEMPTS, POLL_SLEEP_MS);
    if (applied == null) {
        println(
            "[TIMEOUT] {} — transaction not confirmed after {} attempts (~{} s)",
            label,
            POLL_ATTEMPTS,
            POLL_ATTEMPTS * POLL_SLEEP_MS / 1000,
        );
    } else {
        println("[OK] {} — lt={}", label, applied.lt);
    }
    return res;
}

fun main() {
    println("=== SwapEscrow testnet smoke: 1x1 deal (1 NFT vs 0.3 GRAM) ===");
    println("Broadcasting to real network: {}", net.isBroadcasting());

    val wallet1 = scripts.wallet("wallet1"); // owner1: deposits 1 NFT
    val wallet2 = scripts.wallet("wallet2"); // owner2: deposits 0.3 GRAM
    // feeWallet and supervisor reuse wallet1 — a smoke-test simplification
    // (we don't test the supervisor flow here), saves a third funded wallet.
    println("wallet1 (owner1/feeWallet/supervisor) = {}", wallet1.address);
    println("wallet2 (owner2)                       = {}", wallet2.address);

    // 1. Deploy mock NFT (owner wallet1)
    val nftStorage = MockNftStorage {
        ownerAddr: wallet1.address,
        seed: 7001,
        rejectTransfers: false,
    };
    val nftInit = ContractState {
        code: build("NftItemMock"),
        data: nftStorage.toCell(),
    };
    val nftAddr = AutoDeployAddress { stateInit: nftInit }.calculateAddress();
    println("NftItemMock address = {}", nftAddr);
    val nftDeployMsg = createMessage({
        bounce: false,
        value: NFT_DEPLOY_VALUE,
        dest: { stateInit: nftInit },
    });
    waitAndReport(net.send(wallet1.address, nftDeployMsg), "deploy NftItemMock");

    // 2. Build the escrow's initial Storage and deploy (deploy protocol:
    // a single deploy_fee transaction with value 0.05, see
    // tests/escrow_helpers.tolk deployEscrow — the same scheme, repeated
    // here for a real wallet).
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
        swapId: 90001,
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
    println("SwapEscrow address = {}", escrow.address);

    val deployMsg = createMessage({
        bounce: false,
        value: ton("0.05"),
        dest: { stateInit: escrow.stateInit! },
        body: textBody("deploy_fee"),
    });
    waitAndReport(net.send(wallet1.address, deployMsg), "deploy SwapEscrow (deploy_fee)");

    // 3. Side-1 deposits: service fee + NFT (gram1Amount = 0, side 1 doesn't
    // need a GRAM deposit).
    waitAndReport(
        escrow.sendAny(
            wallet1.address,
            textBody("service_fee_owner1"),
            { value: ton("0.1"), bounce: true },
        ),
        "service_fee_owner1 (wallet1)",
    );

    val nftTransferMsg = createMessage({
        bounce: true,
        value: NFT_FORWARD_VALUE + ton("0.05"),
        dest: nftAddr,
        body: NftTransfer {
            queryId: 1,
            newOwner: escrow.address,
            responseDestination: wallet1.address,
            customPayload: null,
            forwardAmount: NFT_FORWARD_VALUE,
            forwardPayload: zeroBitSlice(),
        },
    });
    waitAndReport(net.send(wallet1.address, nftTransferMsg), "NFT transfer wallet1 -> escrow");

    // 4. Side-2 deposits: GRAM + service fee. The last call (side 2's
    // service fee) completes all of tryAutoExecute()'s conditions and
    // triggers the cascade within THE SAME transaction — phase transitions
    // to DONE atomically before any sending happens (see
    // Storage.executeSwapSingleTx — phase = PHASE_DONE is set on the first
    // line, before send()). So confirming this one
    // transaction is enough for the phase() getter to already read DONE.
    waitAndReport(
        escrow.sendAny(
            wallet2.address,
            textBody("deposit_ton2"),
            { value: DEAL_GRAM2 + DEPOSIT_BUFFER, bounce: true },
        ),
        "deposit_ton2 (wallet2)",
    );

    waitAndReport(
        escrow.sendAny(
            wallet2.address,
            textBody("service_fee_owner2"),
            { value: ton("0.1"), bounce: true },
        ),
        "service_fee_owner2 (wallet2, auto-execute trigger)",
    );

    // 5. Verification via getters (real get-method calls on testnet).
    val phase = net.runGetMethod<int>(escrow.address, "phase");
    val nftOwner = net.runGetMethod<address>(nftAddr, "ownerAddr");

    println("");
    println("=== RESULT ===");
    println("escrow.phase() = {} (expected 3 = PHASE_DONE)", phase);
    println("NftItemMock.ownerAddr() = {} (expected == wallet2 {})", nftOwner, wallet2.address);
    if (phase == PHASE_DONE && nftOwner == wallet2.address) {
        println("SMOKE PASSED: full 1x1 swap executed end-to-end on real network.");
    } else {
        println("SMOKE FAILED: final state does not match expectations, see above.");
    }

    println("");
    println("=== Tonviewer links (testnet.tonviewer.com) ===");
    println("wallet1: https://testnet.tonviewer.com/{}", wallet1.address);
    println("wallet2: https://testnet.tonviewer.com/{}", wallet2.address);
    println("NftItemMock: https://testnet.tonviewer.com/{}", nftAddr);
    println("SwapEscrow: https://testnet.tonviewer.com/{}", escrow.address);
}
