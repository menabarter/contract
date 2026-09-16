// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// A test jetton for checking jetton offers in the application on testnet.
//
// WHY OUR OWN, NOT A THIRD-PARTY ONE. The escrow contract resolves jetton
// wallets via TEP-89: it sends provide_wallet_address to the minter and
// waits for take_wallet_address. If the test jetton's minter doesn't support
// this or doesn't respond, the deal stays in the SETUP phase FOREVER — the
// contract won't accept a jetton deposit before that resolves. Using our own
// minter removes that risk and also lets us mint exactly as much as needed.
//
// Compatibility with real jetton implementations is checked separately, not
// by this script: tests/jetton_fork_usdt.test.tolk forks mainnet USDT and
// runs the full cycle against its real code.
//
// What it does:
//   1. deploys a JettonMinterMock (TEP-89) to testnet;
//   2. mints jettons to wallet1 and wallet2;
//   3. prints the minter address and both sides' jetton wallet addresses.
//
// The minter address is what gets entered in the application as the
// "jetton": the contract stores the MINTER itself in the registry, and
// computes the wallet on its own.
//
// Run: acton script scripts/deploy_test_jetton.tolk [--net testnet]
// Budget: ~0.25 TON net.
import "@acton/build"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/jetton_minter_mock"
import "@contracts/jetton_mock_lib"
import "@contracts/messages"

// Change the seed to get a NEW independent jetton (the minter address is
// deterministic from the seed and the wallet code).
const MINTER_SEED = 770126

const MINTER_DEPLOY_VALUE: coins = ton("0.05")
const MINT_VALUE: coins = ton("0.08")
// 9 decimal places, like most jettons: 1000.0 of the jetton.
const MINT_AMOUNT: coins = 1000000000000

const POLL_ATTEMPTS = 40
const POLL_SLEEP_MS = 3000

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

fun main() {
    println("=== Test jetton for testnet (TEP-89 minter + mint) ===");
    println("Broadcasting to real network: {}", net.isBroadcasting());

    val wallet1 = scripts.wallet("wallet1");
    val wallet2 = scripts.wallet("wallet2");
    println("wallet1 = {}", wallet1.address);
    println("wallet2 = {}", wallet2.address);

    val walletCode = build("JettonWalletMock");
    val minterInit = ContractState {
        code: build("JettonMinterMock"),
        data: MinterMockStorage {
            seed: MINTER_SEED as uint32,
            walletCode,
        }.toCell(),
    };
    val minter = AutoDeployAddress { stateInit: minterInit }.calculateAddress();
    println("");
    println("minter = {}", minter);

    waitFirst(
        net.send(
            wallet1.address,
            createMessage({
                bounce: false,
                value: MINTER_DEPLOY_VALUE,
                dest: { stateInit: minterInit },
            }),
        ),
        "deploy JettonMinterMock",
    );

    // Mint to both sides. The wallets get deployed by the transfer itself
    // (internal_transfer with stateInit), no separate deploy needed.
    waitTrace(
        net.send(
            wallet1.address,
            createMessage({
                bounce: true,
                value: MINT_VALUE,
                dest: minter,
                body: MintMock {
                    queryId: 1,
                    to: wallet1.address,
                    amount: MINT_AMOUNT,
                },
            }),
        ),
        "mint -> wallet1",
    );
    waitTrace(
        net.send(
            wallet2.address,
            createMessage({
                bounce: true,
                value: MINT_VALUE,
                dest: minter,
                body: MintMock {
                    queryId: 2,
                    to: wallet2.address,
                    amount: MINT_AMOUNT,
                },
            }),
        ),
        "mint -> wallet2",
    );

    val jw1 = walletAddrFor(minter, wallet1.address, walletCode);
    val jw2 = walletAddrFor(minter, wallet2.address, walletCode);
    val bal1 = net.runGetMethod<int>(jw1, "jettonBalance");
    val bal2 = net.runGetMethod<int>(jw2, "jettonBalance");

    println("");
    println("=== RESULT ===");
    println("MINTER (enter this in the application) = {}", minter);
    println("jetton wallet wallet1 = {} | balance = {}", jw1, bal1);
    println("jetton wallet wallet2 = {} | balance = {}", jw2, bal2);
    if (bal1 == MINT_AMOUNT && bal2 == MINT_AMOUNT) {
        println("OK: both sides received 1000.0 of the jetton (9 decimals).");
    } else {
        println("WARNING: balances did not match expectations — see the traces above.");
    }
    println("");
    println("minter: https://testnet.tonviewer.com/{}", minter);
}
