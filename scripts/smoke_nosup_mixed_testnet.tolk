// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Testnet smoke (mixed deal) for SwapEscrowNosup: NFT + jettons on BOTH sides.
//   side 1 (wallet1): 1 NFT (nftA) + 100 jettons
//   side 2 (wallet2): 1 NFT (nftB) +  50 jettons
// One mock minter serves both sides, both sides pay SERVICE_FEE.
//
// Checked on the live network:
//   • TEP-89 discovery resolves the escrow's jetton wallet and SETUP -> ACTIVE;
//   • the last deposit auto-executes and distributes NFTs and jettons together;
//   • each side ends up with the other side's NFT and jettons;
//   • the escrow keeps no jettons and its TON balance is swept to zero.
//
// Run: acton script scripts/smoke_nosup_mixed_testnet.tolk [--net testnet]
import "@acton/build"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/jetton_minter_mock"
import "@contracts/jetton_mock_lib"
import "@contracts/messages"
import "@contracts/nft_item_mock"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"

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

// Wait for the WHOLE cascade of descendants (discovery / auto-execute).
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

fun mkNft(side: int, addr: address): Asset {
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

fun mkJetton(side: int, minter: address, amount: coins): Asset {
    return Asset {
        kind: 1,
        ownerSide: side as uint2,
        addr: minter,
        jettonWallet: null,
        amount,
        received: false,
        sent: false,
        bounces: 0,
        claimable: false,
    };
}

fun main() {
    println("=== SwapEscrowNosup testnet smoke: MIXED (NFT+jetton both sides) ===");
    println("Broadcasting to real network: {}", net.isBroadcasting());

    val wallet1 = scripts.wallet("wallet1"); // side 1: nftA + 100 jettons
    val wallet2 = scripts.wallet("wallet2"); // side 2: nftB + 50 jettons
    println("wallet1 (owner1/feeWallet) = {}", wallet1.address);
    println("wallet2 (owner2)           = {}", wallet2.address);

    val walletCode = build("JettonWalletMock");

    // 1. Minter (fresh seed → jetton wallets start from zero).
    val minterInit = ContractState {
        code: build("JettonMinterMock"),
        data: MinterMockStorage {
            seed: 88002,
            walletCode,
        }.toCell(),
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
    val nftA = deployNftMock(wallet1.address, wallet1.address, 88001);
    println("nftA (side 1) = {}", nftA);
    val nftB = deployNftMock(wallet2.address, wallet2.address, 88003);
    println("nftB (side 2) = {}", nftB);

    // 4. Registry order: side 1's NFTs, then side 2's NFTs, then jettons →
    //    nftA@0(side1), nftB@1(side2), jetton@2(side1,100), jetton@3(side2,50).
    //    One minter → pendingWallets=1, so the deal deploys into SETUP.
    var assets: map<uint16, Asset> = [];
    assets.set(0, mkNft(1, nftA));
    assets.set(1, mkNft(2, nftB));
    assets.set(2, mkJetton(1, minter, DEAL_JETTON1));
    assets.set(3, mkJetton(2, minter, DEAL_JETTON2));
    val initStorage = Storage {
        swapId: 90801,
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
        dist: DistState {
            mode: DIST_IDLE,
            cursor: 0,
        }.toCell(),
    };
    val escrow = SwapEscrowNosup.fromStorage(initStorage);
    println("SwapEscrowNosup address = {}", escrow.address);
    val escrowJw = walletAddrFor(minter, escrow.address, walletCode);
    println("escrow jetton wallet (expected resolve) = {}", escrowJw);

    // 5. deploy_fee carries the TEP-89 discovery cascade; the overpayment is
    //    not gated and comes back as excesses.
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
        "deploy SwapEscrowNosup (deploy_fee) + TEP-89 discovery",
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

    // 6. Side-1 deposits: service fee, nftA, jettons (hint index 2).
    waitFirst(
        escrow.sendAny(
            wallet1.address,
            textBody("service_fee_owner1"),
            { value: SERVICE_FEE, bounce: true },
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

    // 7. Side-2 deposits: the jetton one completes the conditions and triggers
    //    auto-execution of both asset classes.
    waitFirst(
        escrow.sendAny(
            wallet2.address,
            textBody("service_fee_owner2"),
            { value: SERVICE_FEE, bounce: true },
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
    val claimable = net.runGetMethod<map<uint16, bool>>(escrow.address, "claimableAssets");

    println("");
    println("=== RESULT ===");
    println("escrow.phase() = {} (expected 3 = PHASE_DONE)", phase);
    println("nftA owner = {} (expected == wallet2 {})", ownerA, wallet2.address);
    println("nftB owner = {} (expected == wallet1 {})", ownerB, wallet1.address);
    println("wallet1 jetton balance = {} (expected 450 = 500-100+50)", bal1);
    println("wallet2 jetton balance = {} (expected 550 = 500-50+100)", bal2);
    println("escrow  jetton balance = {} (expected 0)", balEscrow);
    println("claimableAssets empty = {} (expected true)", claimable.isEmpty());

    val ok = phase == PHASE_DONE && ownerA == wallet2.address && ownerB == wallet1.address &&
        bal1 == ton("450") &&
        bal2 == ton("550") &&
        balEscrow == 0 &&
        claimable.isEmpty();
    if (ok) {
        println("SMOKE PASSED: mixed NFT+jetton swap (both sides) executed end-to-end.");
    } else {
        println("SMOKE FAILED: final state does not match expectations, see above.");
    }

    println("");
    println("escrow: https://testnet.tonviewer.com/{}", escrow.address);
    println("minter: https://testnet.tonviewer.com/{}", minter);
}
