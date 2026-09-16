// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Testnet smoke (mixed deal): NFT + jettons on BOTH sides.
//   side 1 (wallet1): 1 NFT (nftA) + 100 jettons
//   side 2 (wallet2): 1 NFT (nftB) +  50 jettons
// one mock minter for both sides, both sides pay SERVICE_FEE = 0.1 TON.
// Run: acton script scripts/smoke_mixed_testnet.tolk [--net testnet].
//
// Together, this covers everything checked separately in smoke_testnet.tolk
// (the NFT path) and smoke_jetton_testnet.tolk (the jetton path + TEP-89
// discovery): a single escrow holds both NFTs and jettons on both sides, and
// auto-execution distributes both asset classes in one atomic transaction.
// Asset order in Storage (buildInitialStorage, tests/escrow_helpers.tolk):
// side 1's NFTs first, then side 2's NFTs, then jettons — hence the global
// indices and hints.
import "@acton/build"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/jetton_minter_mock"
import "@contracts/jetton_mock_lib"
import "@contracts/messages"
import "@contracts/nft_item_mock"
import "@contracts/storage"
import "@wrappers/SwapEscrow.gen"

const DEAL_JETTON1: coins = ton("100") // side 1's jettons (wallet1)
const DEAL_JETTON2: coins = ton("50") // side 2's jettons (wallet2)
const MINT_AMOUNT: coins = ton("500")
const JETTON_FORWARD: coins = ton("0.2")
const NFT_FORWARD: coins = ton("0.2")

const POLL_ATTEMPTS = 30
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

fun deployNftMock(deployer: address, owner: address, seed: int): address {
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
            createMessage({ bounce: false, value: ton("0.1"), dest: { stateInit: init } }),
        ),
        "deploy NftItemMock",
    );
    return addr;
}

fun sendNft(owner: address, nft: address, escrow: address): SendResultList {
    return net.send(
        owner,
        createMessage({
            bounce: true,
            value: NFT_FORWARD + ton("0.05"),
            dest: nft,
            body: NftTransfer {
                queryId: 1,
                newOwner: escrow,
                responseDestination: owner,
                customPayload: null,
                forwardAmount: NFT_FORWARD,
                forwardPayload: zeroBitSlice(),
            },
        }),
    );
}

fun sendJetton(
    owner: address,
    jw: address,
    escrow: address,
    amount: coins,
    hint: int,
): SendResultList {
    val payload = beginCell().storeUint(0, 1).storeUint(hint, 16).endCell().beginParse();
    return net.send(
        owner,
        createMessage({
            bounce: true,
            value: JETTON_FORWARD + ton("0.08"),
            dest: jw,
            body: JettonTransfer {
                queryId: 7,
                amount,
                destination: escrow,
                responseDestination: owner,
                customPayload: null,
                forwardTonAmount: JETTON_FORWARD,
                forwardPayload: payload,
            },
        }),
    );
}

fun main() {
    println("=== SwapEscrow testnet smoke: MIXED (NFT+jetton both sides) ===");
    println("Broadcasting to real network: {}", net.isBroadcasting());

    val wallet1 = scripts.wallet("jw1"); // side 1: nftA + 100 jettons
    val wallet2 = scripts.wallet("jw2"); // side 2: nftB + 50 jettons
    println("wallet1 (owner1/feeWallet/supervisor) = {}", wallet1.address);
    println("wallet2 (owner2)                       = {}", wallet2.address);

    val walletCode = build("JettonWalletMock");

    // 1. Minter (fresh seed → jetton wallets start from zero).
    val minterStorage = MinterMockStorage {
        seed: 77002,
        walletCode,
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

    // 2. Mint 500 jettons to each side.
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

    // 3. Two mock NFTs: nftA on side 1, nftB on side 2.
    val nftA = deployNftMock(wallet1.address, wallet1.address, 78001);
    println("nftA (side 1) = {}", nftA);
    val nftB = deployNftMock(wallet2.address, wallet2.address, 78002);
    println("nftB (side 2) = {}", nftB);

    // 4. Storage: 4 assets. Indices (buildInitialStorage): NFT1 first, then
    //    NFT2, then jettons → nftA@0(side1), nftB@1(side2), jetton@2(side1,100),
    //    jetton@3(side2,50). One minter → pendingWallets=1, deploy into SETUP.
    var assets: map<uint16, Asset> = [];
    assets.set(
        0,
        Asset {
            kind: 0,
            ownerSide: 1,
            addr: nftA,
            jettonWallet: null,
            amount: 0,
            received: false,
            sent: false,
            bounces: 0,
            abandoned: false,
        },
    );
    assets.set(
        1,
        Asset {
            kind: 0,
            ownerSide: 2,
            addr: nftB,
            jettonWallet: null,
            amount: 0,
            received: false,
            sent: false,
            bounces: 0,
            abandoned: false,
        },
    );
    assets.set(
        2,
        Asset {
            kind: 1,
            ownerSide: 1,
            addr: minter,
            jettonWallet: null,
            amount: DEAL_JETTON1,
            received: false,
            sent: false,
            bounces: 0,
            abandoned: false,
        },
    );
    assets.set(
        3,
        Asset {
            kind: 1,
            ownerSide: 2,
            addr: minter,
            jettonWallet: null,
            amount: DEAL_JETTON2,
            received: false,
            sent: false,
            bounces: 0,
            abandoned: false,
        },
    );
    val initStorage = Storage {
        swapId: 90003,
        phase: PHASE_SETUP,
        owner1: wallet1.address,
        owner2: wallet2.address,
        feeWallet: wallet1.address,
        assetsCount: 4,
        required1Count: 2, // nftA + side 1's jetton
        required2Count: 2, // nftB + side 2's jetton
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
    val escrowJw = walletAddrFor(minter, escrow.address, walletCode);
    println("escrow jetton wallet (expected resolve) = {}", escrowJw);

    // 5. Deploy deploy_fee + async TEP-89 discovery (waitForTrace follows
    //    deploy -> provide_wallet_address -> take_wallet_address). value has
    //    a 0.1 TON buffer (see smoke_jetton_testnet.tolk — we don't call
    //    calculateGasFee because of double-alias gas payments in the script
    //    environment; the overpayment isn't gated and comes back as excesses).
    waitTrace(
        net.send(
            wallet1.address,
            createMessage({
                bounce: false,
                value: ton("0.1"),
                dest: { stateInit: escrow.stateInit! },
                body: textBody("deploy_fee"),
            }),
        ),
        "deploy SwapEscrow (deploy_fee) + TEP-89 discovery",
    );

    val phaseAfterSetup = net.runGetMethod<int>(escrow.address, "phase");
    val pendingLeft = net.runGetMethod<int>(escrow.address, "pendingWalletsLeft");
    val resolved2 = net.runGetMethod<address?>(escrow.address, "assetJettonWallet", [2]);
    println(
        "after discovery: phase={} (expected 1=ACTIVE), pendingWalletsLeft={} (expected 0)",
        phaseAfterSetup,
        pendingLeft,
    );
    println("assetJettonWallet(2)={} (expected == escrow jetton wallet {})", resolved2, escrowJw);

    // 6. Side-1 deposits: service fee, nftA, jetton (hint index 2).
    waitFirst(
        escrow.sendAny(
            wallet1.address,
            textBody("service_fee_owner1"),
            { value: ton("0.1"), bounce: true },
        ),
        "service_fee_owner1 (wallet1)",
    );
    waitTrace(sendNft(wallet1.address, nftA, escrow.address), "nftA deposit wallet1 -> escrow");
    waitTrace(
        sendJetton(
            wallet1.address,
            walletAddrFor(minter, wallet1.address, walletCode),
            escrow.address,
            DEAL_JETTON1,
            2,
        ),
        "jetton deposit wallet1 -> escrow (100, hint 2)",
    );

    // 7. Side-2 deposits: service fee, nftB, jetton (hint index 3) — the last
    //    one completes the conditions and triggers auto-execution (NFT+jetton distribution).
    waitFirst(
        escrow.sendAny(
            wallet2.address,
            textBody("service_fee_owner2"),
            { value: ton("0.1"), bounce: true },
        ),
        "service_fee_owner2 (wallet2)",
    );
    waitTrace(sendNft(wallet2.address, nftB, escrow.address), "nftB deposit wallet2 -> escrow");
    waitTrace(
        sendJetton(
            wallet2.address,
            walletAddrFor(minter, wallet2.address, walletCode),
            escrow.address,
            DEAL_JETTON2,
            3,
        ),
        "jetton deposit wallet2 -> escrow (50, hint 3, auto-execute trigger)",
    );

    // 8. Verify the outcome with getters.
    val phase = net.runGetMethod<int>(escrow.address, "phase");
    val ownerA = net.runGetMethod<address>(nftA, "ownerAddr");
    val ownerB = net.runGetMethod<address>(nftB, "ownerAddr");
    val bal1 = net.runGetMethod<coins>(
        walletAddrFor(minter, wallet1.address, walletCode),
        "jettonBalance",
    );
    val bal2 = net.runGetMethod<coins>(
        walletAddrFor(minter, wallet2.address, walletCode),
        "jettonBalance",
    );
    val balEscrow = net.runGetMethod<coins>(escrowJw, "jettonBalance");

    println("");
    println("=== RESULT ===");
    println("escrow.phase() = {} (expected 3 = PHASE_DONE)", phase);
    println("nftA owner = {} (expected == wallet2 {})", ownerA, wallet2.address);
    println("nftB owner = {} (expected == wallet1 {})", ownerB, wallet1.address);
    println("wallet1 jetton balance = {} (expected 450 = 500-100+50)", bal1);
    println("wallet2 jetton balance = {} (expected 550 = 500-50+100)", bal2);
    println("escrow  jetton balance = {} (expected 0)", balEscrow);
    val ok = phase == PHASE_DONE && ownerA == wallet2.address && ownerB == wallet1.address &&
    bal1 == ton("450") &&
    bal2 == ton("550") &&
    balEscrow == 0;
    if (ok) {
        println("SMOKE PASSED: mixed NFT+jetton swap (both sides) executed end-to-end.");
    } else {
        println("SMOKE FAILED: final state does not match expectations, see above.");
    }

    println("");
    println("=== Tonviewer links (testnet.tonviewer.com) ===");
    println("wallet1: https://testnet.tonviewer.com/{}", wallet1.address);
    println("wallet2: https://testnet.tonviewer.com/{}", wallet2.address);
    println("nftA: https://testnet.tonviewer.com/{}", nftA);
    println("nftB: https://testnet.tonviewer.com/{}", nftB);
    println("JettonMinterMock: https://testnet.tonviewer.com/{}", minter);
    println("SwapEscrow: https://testnet.tonviewer.com/{}", escrow.address);
}
