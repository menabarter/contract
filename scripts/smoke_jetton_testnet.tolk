// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Testnet smoke (jettons): a full jetton-only 1x1 swap
//   100 jettons from wallet1 (side 1)  <->  50 jettons from wallet2 (side 2)
// one mock minter for both sides, both sides pay SERVICE_FEE = 0.1 TON.
// Run: acton script scripts/smoke_jetton_testnet.tolk [--net testnet].
//
// Why separate from smoke_testnet.tolk (NFT): jettons add a piece not yet
// checked ON THE REAL NETWORK — TEP-89 wallet discovery. A jetton deal
// deploys into PHASE_SETUP and only transitions to ACTIVE after the minter
// asynchronously replies with take_wallet_address to the escrow's
// provide_wallet_address (in emulation this cascade is synchronous, on
// testnet these are separate transactions). That's why waitForTrace is used
// here after deploy_fee (it follows the WHOLE chain of descendants:
// deploy -> provide -> take), rather than waitForFirstTransaction.
import "@acton/build"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/jetton_minter_mock"
import "@contracts/jetton_mock_lib"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/SwapEscrow.gen"

const DEAL_AMOUNT1: coins = ton("100") // side 1's jettons (wallet1)
const DEAL_AMOUNT2: coins = ton("50") // side 2's jettons (wallet2)
const MINT_AMOUNT: coins = ton("500") // starting balance for each side
const JETTON_FORWARD: coins = ton("0.2")

const POLL_ATTEMPTS = 30
const POLL_SLEEP_MS = 3000

fun textBody(text: string): cell {
    return beginCell().storeUint(0, 32).storeSlice(text.beginParse()).endCell();
}

// In broadcast mode (--net), net.send only returns a pseudo transaction;
// only waitForFirstTransaction/waitForTrace give a real confirmation of
// inclusion in a block (they're also the only waiting primitive in Acton
// scripts — there's no separate sleep() in the runtime). In emulation they
// return the result immediately.
fun waitFirst(res: SendResultList, label: string): SendResultList {
    val applied = res.waitForFirstTransaction(false, POLL_ATTEMPTS, POLL_SLEEP_MS);
    if (applied == null) {
        println("[TIMEOUT] {} — not confirmed after {} attempts", label, POLL_ATTEMPTS);
    } else {
        println("[OK] {} — lt={}", label, applied.lt);
    }
    return res;
}

// Wait for the WHOLE cascade of descendants (discovery / auto-execute), not just the first tx.
fun waitTrace(res: SendResultList, label: string): SendResultList {
    val applied = res.waitForTrace(false, POLL_ATTEMPTS, POLL_SLEEP_MS);
    if (applied == null) {
        println("[TIMEOUT] {} (trace) — not confirmed after {} attempts", label, POLL_ATTEMPTS);
    } else {
        println("[OK] {} (full trace confirmed)", label);
    }
    return res;
}

fun main() {
    println("=== SwapEscrow testnet smoke: jetton 1x1 (100 vs 50, one minter) ===");
    println("Broadcasting to real network: {}", net.isBroadcasting());

    // Fresh wallets (jw1/jw2) set up for the jetton smoke test: reusing
    // wallet1/wallet2 from the NFT smoke test ran into a seqno desync on the
    // light server (the seqno getter lagged behind the collator →
    // "Duplicate msg_seqno"). Fresh wallets start at seqno 0 and sidestep that lag.
    val wallet1 = scripts.wallet("jw1"); // owner1: deposits 100 jettons
    val wallet2 = scripts.wallet("jw2"); // owner2: deposits 50 jettons
    // feeWallet and supervisor reuse wallet1 (we don't test the supervisor
    // flow here — saves a third funded wallet, same as in smoke_testnet.tolk).
    println("wallet1 (owner1/feeWallet/supervisor) = {}", wallet1.address);
    println("wallet2 (owner2)                       = {}", wallet2.address);

    // 1. Deploy the mock minter (TEP-89 discovery + test mint).
    val minterStorage = MinterMockStorage {
        seed: 77001,
        walletCode: build("JettonWalletMock"),
    };
    val minterInit = ContractState {
        code: build("JettonMinterMock"),
        data: minterStorage.toCell(),
    };
    val minter = AutoDeployAddress { stateInit: minterInit }.calculateAddress();
    println("JettonMinterMock address = {}", minter);
    waitFirst(
        net.send(
            wallet1.address,
            createMessage({ bounce: false, value: ton("0.1"), dest: { stateInit: minterInit } }),
        ),
        "deploy JettonMinterMock",
    );

    // 2. Mint 500 jettons to each side (mint deploys their jetton wallets).
    waitFirst(
        net.send(
            wallet1.address,
            createMessage({
                bounce: true,
                value: ton("0.1"),
                dest: minter,
                body: MintMock {
                    queryId: 0,
                    to: wallet1.address,
                    amount: MINT_AMOUNT,
                },
            }),
        ),
        "mint 500 -> wallet1",
    );
    waitFirst(
        net.send(
            wallet2.address,
            createMessage({
                bounce: true,
                value: ton("0.1"),
                dest: minter,
                body: MintMock {
                    queryId: 0,
                    to: wallet2.address,
                    amount: MINT_AMOUNT,
                },
            }),
        ),
        "mint 500 -> wallet2",
    );

    // 3. Initial Storage for the jetton-only deal (2 jetton assets, one
    //    minter → pendingWallets = 1, deploy into PHASE_SETUP). The shape
    //    mirrors buildInitialStorage (tests/escrow_helpers.tolk) for this config.
    var assets: map<uint16, Asset> = [];
    assets.set(
        0,
        Asset {
            kind: 1,
            ownerSide: 1,
            addr: minter,
            jettonWallet: null,
            amount: DEAL_AMOUNT1,
            received: false,
            sent: false,
            bounces: 0,
            abandoned: false,
        },
    );
    assets.set(
        1,
        Asset {
            kind: 1,
            ownerSide: 2,
            addr: minter,
            jettonWallet: null,
            amount: DEAL_AMOUNT2,
            received: false,
            sent: false,
            bounces: 0,
            abandoned: false,
        },
    );
    val initStorage = Storage {
        swapId: 90002,
        phase: PHASE_SETUP,
        owner1: wallet1.address,
        owner2: wallet2.address,
        feeWallet: wallet1.address,
        assetsCount: 2,
        required1Count: 1,
        required2Count: 1,
        received1Count: 0,
        received2Count: 0,
        pendingWallets: 1,
        jettonsCount: 2,
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
    val escrowJw = walletAddrFor(minter, escrow.address, build("JettonWalletMock"));
    println("escrow jetton wallet (expected resolve) = {}", escrowJw);

    // 4. Deploy the escrow with a deploy_fee transaction. The exact
    //    deployEscrow formula (tests/escrow_helpers.tolk) = 0.05 + (0.02 +
    //    takeReserve)×minters + deployReserve; for 1 minter/2 assets at
    //    testnet gas prices that's ≈0.072 TON (takeReserve+deployReserve ≈
    //    0.0016 TON combined). This smoke test doesn't use calculateGasFee
    //    (its gas-payments module hits a double-alias in the script
    //    environment — the same collision described in
    //    tests/escrow_helpers.tolk), and instead uses a value with margin:
    //    0.1 TON comfortably covers 0.05 + PROVIDE_WALLET_VALUE(0.02) +
    //    reserves. The overpayment isn't gated (handleDeployFee only checks
    //    value >= the required amount) and comes back as change/excesses —
    //    it doesn't affect the outcome of the deal.
    val deployValue = ton("0.1");
    // waitForTrace: follows the discovery cascade deploy ->
    // provide_wallet_address -> take_wallet_address (on testnet these are
    // separate async transactions).
    waitTrace(
        net.send(
            wallet1.address,
            createMessage({
                bounce: false,
                value: deployValue,
                dest: { stateInit: escrow.stateInit! },
                body: textBody("deploy_fee"),
            }),
        ),
        "deploy SwapEscrow (deploy_fee) + TEP-89 discovery",
    );

    // 5. Check that discovery finished: SETUP -> ACTIVE, minter resolved.
    val phaseAfterSetup = net.runGetMethod<int>(escrow.address, "phase");
    val pendingLeft = net.runGetMethod<int>(escrow.address, "pendingWalletsLeft");
    val resolved0 = net.runGetMethod<address?>(escrow.address, "assetJettonWallet", [0]);
    println(
        "after discovery: phase={} (expected 1=ACTIVE), pendingWalletsLeft={} (expected 0)",
        phaseAfterSetup,
        pendingLeft,
    );
    println("assetJettonWallet(0)={} (expected == escrow jetton wallet {})", resolved0, escrowJw);

    // 6. Deposits: both sides' service fee, then jettons. The last jetton
    //    deposit (side 2) completes all conditions and triggers
    //    auto-execution in the same cascade (phase = DONE is set on the
    //    first line of executeSwap, before sending).
    waitFirst(
        escrow.sendAny(
            wallet1.address,
            textBody("service_fee_owner1"),
            { value: ton("0.1"), bounce: true },
        ),
        "service_fee_owner1 (wallet1)",
    );
    waitFirst(
        escrow.sendAny(
            wallet2.address,
            textBody("service_fee_owner2"),
            { value: ton("0.1"), bounce: true },
        ),
        "service_fee_owner2 (wallet2)",
    );

    // Side-1 jetton deposit: 100 jettons, hint index 0.
    val payload0 = beginCell().storeUint(0, 1).storeUint(0, 16).endCell().beginParse();
    waitTrace(
        net.send(
            wallet1.address,
            createMessage({
                bounce: true,
                value: JETTON_FORWARD + ton("0.08"),
                dest: walletAddrFor(minter, wallet1.address, build("JettonWalletMock")),
                body: JettonTransfer {
                    queryId: 7,
                    amount: DEAL_AMOUNT1,
                    destination: escrow.address,
                    responseDestination: wallet1.address,
                    customPayload: null,
                    forwardTonAmount: JETTON_FORWARD,
                    forwardPayload: payload0,
                },
            }),
        ),
        "jetton deposit wallet1 -> escrow (100, hint 0)",
    );

    // Side-2 jetton deposit: 50 jettons, hint index 1 — auto-execution TRIGGER.
    val payload1 = beginCell().storeUint(0, 1).storeUint(1, 16).endCell().beginParse();
    waitTrace(
        net.send(
            wallet2.address,
            createMessage({
                bounce: true,
                value: JETTON_FORWARD + ton("0.08"),
                dest: walletAddrFor(minter, wallet2.address, build("JettonWalletMock")),
                body: JettonTransfer {
                    queryId: 7,
                    amount: DEAL_AMOUNT2,
                    destination: escrow.address,
                    responseDestination: wallet2.address,
                    customPayload: null,
                    forwardTonAmount: JETTON_FORWARD,
                    forwardPayload: payload1,
                },
            }),
        ),
        "jetton deposit wallet2 -> escrow (50, hint 1, auto-execute trigger)",
    );

    // 7. Verify the outcome via getters (real calls on testnet).
    val phase = net.runGetMethod<int>(escrow.address, "phase");
    val bal1 = net.runGetMethod<coins>(
        walletAddrFor(minter, wallet1.address, build("JettonWalletMock")),
        "jettonBalance",
    );
    val bal2 = net.runGetMethod<coins>(
        walletAddrFor(minter, wallet2.address, build("JettonWalletMock")),
        "jettonBalance",
    );
    val balEscrow = net.runGetMethod<coins>(escrowJw, "jettonBalance");

    println("");
    println("=== RESULT ===");
    println("escrow.phase() = {} (expected 3 = PHASE_DONE)", phase);
    println("wallet1 jetton balance = {} (expected 450 = 500-100+50)", bal1);
    println("wallet2 jetton balance = {} (expected 550 = 500-50+100)", bal2);
    println("escrow  jetton balance = {} (expected 0)", balEscrow);
    if (phase == PHASE_DONE && bal1 == ton("450") && bal2 == ton("550") && balEscrow == 0) {
        println("SMOKE PASSED: jetton 1x1 swap executed end-to-end (incl. TEP-89 discovery).");
    } else {
        println("SMOKE FAILED: final state does not match expectations, see above.");
    }

    println("");
    println("=== Tonviewer links (testnet.tonviewer.com) ===");
    println("wallet1: https://testnet.tonviewer.com/{}", wallet1.address);
    println("wallet2: https://testnet.tonviewer.com/{}", wallet2.address);
    println("JettonMinterMock: https://testnet.tonviewer.com/{}", minter);
    println("SwapEscrow: https://testnet.tonviewer.com/{}", escrow.address);
}
