// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Shared setup of the one-signature testnet smokes (smoke_nosup_onesig_*).
//
// The deal: side 1 (owner1) gives one NFT; side 2 (owner2) gives one NFT and
// jettons of two TEP-89 minters. Registry:
//   0 nft1 (side 1); 1 nft2 (side 2); 2 jetton of m1, 10 (side 2);
//   3 jetton of m2, 20 (side 2).
// owner2 takes it with ONE signature: AcceptDeal (deploys the escrow, pays
// side 2's fee and discovery, claims the escrow's wallets of m1 and m2), then
// the NFT and both jetton transfers. owner1 pays its fee and deposits its NFT
// after the escrow exists. `funder` pays for the minters, the mint and the NFTs,
// so owner2's balance holds only what the batch itself needs.
import "@stdlib/gas-payments"
import "@acton/build"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@acton/types/big_array"
import "@contracts/jetton_minter_mock"
import "@contracts/jetton_mock_lib"
import "@contracts/messages"
import "@contracts/nft_item_mock"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/messages"
import "@contracts/nosup/storage"
import "@contracts/shared/messages"
import "@contracts/shared/types"
import "wallet_batch"

const OS_JETTON1: coins = ton("10")
const OS_JETTON2: coins = ton("20")
const OS_MINT: coins = ton("100")
const OS_FORWARD: coins = ton("0.05") // forward TON of every deposit
const OS_NFT_GAS: coins = ton("0.05")
const OS_JETTON_GAS: coins = ton("0.08")
const OS_ACCEPT_MARGIN: coins = ton("0.05")

const OS_POLL_ATTEMPTS = 40
const OS_POLL_SLEEP_MS = 3000

struct OneSigSetup {
    escrow: SwapEscrowNosup
    owner1: address
    owner2: address
    m1: address
    m2: address
    nft1: address
    nft2: address
}

fun osText(text: string): cell {
    return beginCell().storeUint(0, 32).storeSlice(text.beginParse()).endCell();
}

fun osWaitFirst(res: SendResultList, label: string) {
    val applied = res.waitForFirstTransaction(false, OS_POLL_ATTEMPTS, OS_POLL_SLEEP_MS);
    if (applied == null) {
        println("[TIMEOUT] {}", label);
    } else {
        println("[OK] {} — lt={}", label, applied.lt);
    }
}

fun osWaitTrace(res: SendResultList, label: string) {
    val applied = res.waitForTrace(false, OS_POLL_ATTEMPTS, OS_POLL_SLEEP_MS);
    if (applied == null) {
        println("[TIMEOUT] {} (trace)", label);
    } else {
        println("[OK] {} (full trace)", label);
    }
}

// Waits for the whole trace of a batch. In a local dry run the batch was
// already applied message by message.
fun osWaitBatch(res: ExternalSendResult?, label: string) {
    if (res == null) {
        println("[DRY RUN] {} — sent message by message", label);
        return;
    }
    if (res.error != null) {
        println("[REJECTED] {} — the wallet did not accept the external message", label);
        return;
    }
    val applied = res.waitForTrace(false, OS_POLL_ATTEMPTS, OS_POLL_SLEEP_MS);
    if (applied == null) {
        println("[TIMEOUT] {} (trace)", label);
    } else {
        println("[OK] {} (full trace, {} transactions)", label, applied.size());
    }
}

// A per-run seed, so every run gets fresh minters, NFTs and escrow.
fun osRunSeed(wallet: address): int {
    val shard = scripts.fetchShardAccount(wallet);
    if (shard == null) {
        return 0;
    }
    return shard.lastTransLt % 1000000000;
}

fun osDeploy(funder: address, init: ContractState, label: string): address {
    val addr = AutoDeployAddress { stateInit: init }.calculateAddress();
    osWaitFirst(
        net.send(
            funder,
            createMessage({ bounce: false, value: ton("0.05"), dest: { stateInit: init } }),
        ),
        label,
    );
    return addr;
}

fun osMinter(funder: address, seed: int): address {
    return osDeploy(
        funder,
        ContractState {
            code: build("JettonMinterMock"),
            data: MinterMockStorage {
                seed: seed as uint32,
                walletCode: build("JettonWalletMock"),
            }.toCell(),
        },
        "deploy JettonMinterMock",
    );
}

fun osMint(funder: address, minter: address, to: address) {
    osWaitTrace(
        net.send(
            funder,
            createMessage({
                bounce: true,
                value: ton("0.08"),
                dest: minter,
                body: MintMock {
                    queryId: 0,
                    to,
                    amount: OS_MINT,
                },
            }),
        ),
        "mint",
    );
}

fun osNft(funder: address, owner: address, seed: int): address {
    return osDeploy(
        funder,
        ContractState {
            code: build("NftItemMock"),
            data: MockNftStorage {
                ownerAddr: owner,
                seed: seed as uint32,
                rejectTransfers: false,
            }.toCell(),
        },
        "deploy NftItemMock",
    );
}

fun osJw(minter: address, owner: address): address {
    return walletAddrFor(minter, owner, build("JettonWalletMock"));
}

fun osJettonBalance(minter: address, owner: address): coins {
    val jw = osJw(minter, owner);
    if (!scripts.isContractDeployed(jw)) {
        return 0;
    }
    return net.runGetMethod<coins>(jw, "jettonBalance");
}

fun osAsset(kind: int, side: int, addr: address, amount: coins): Asset {
    return Asset {
        kind: kind as uint2,
        ownerSide: side as uint2,
        addr,
        jettonWallet: null,
        amount,
        received: false,
        walletUnverified: false,
        bounces: 0,
        claimable: false,
    };
}

fun osSetup(funder: address, owner1: address, owner2: address): OneSigSetup {
    val seed = osRunSeed(funder);
    println("run seed = {}", seed);
    val m1 = osMinter(funder, seed);
    val m2 = osMinter(funder, seed + 1);
    osMint(funder, m1, owner2);
    osMint(funder, m2, owner2);
    val nft1 = osNft(funder, owner1, seed + 2);
    val nft2 = osNft(funder, owner2, seed + 3);

    var assets: map<uint16, Asset> = [];
    assets.set(0, osAsset(0, 1, nft1, 0));
    assets.set(1, osAsset(0, 2, nft2, 0));
    assets.set(2, osAsset(1, 2, m1, OS_JETTON1));
    assets.set(3, osAsset(1, 2, m2, OS_JETTON2));
    val escrow = SwapEscrowNosup.fromStorage(Storage {
        swapId: seed,
        phase: PHASE_SETUP,
        owner1,
        owner2,
        feeWallet: funder,
        assetsCount: 4,
        required1Count: 1,
        required2Count: 3,
        received1Count: 0,
        received2Count: 0,
        pendingWallets: 2,
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
    });
    println("m1 = {}", m1);
    println("m2 = {}", m2);
    println("nft1 (side 1) = {}", nft1);
    println("nft2 (side 2) = {}", nft2);
    println("escrow = {}", escrow.address);
    return OneSigSetup { escrow, owner1, owner2, m1, m2, nft1, nft2 };
}

// What AcceptDeal carries: side 2's service fee, discovery of both minters
// (one slot each) and AcceptDeal's own gas (the contract's model), plus a
// margin. Everything above the fee stays credited to side 2.
fun osAcceptValue(): coins {
    val n = 4;
    var discovery: coins = calculateGasFee(
        BASECHAIN,
        DEPLOY_BASE_GAS_UNITS + DEPLOY_GAS_UNITS_PER_ASSET * n,
    );
    discovery += 2 *
        (PROVIDE_WALLET_VALUE +
            calculateGasFee(
                BASECHAIN,
                TAKE_SCAN_BASE_UNITS + TAKE_SCAN_UNITS_PER_ENTRY * n + TAKE_SET_UNITS,
            ));
    val own = calculateGasFee(
        BASECHAIN,
        ACCEPT_BASE_UNITS + ACCEPT_UNITS_PER_ENTRY * n + ACCEPT_UNITS_PER_CLAIM * 2,
    );
    return SERVICE_FEE + discovery + own + OS_ACCEPT_MARGIN;
}

fun osDepositPayload(hint: int): slice {
    return beginCell().storeUint(0, 1).storeUint(hint, 16).endCell().beginParse();
}

// owner2's batch, in order: AcceptDeal first, then nft2, jetton m1, jetton m2.
fun osBatch(d: OneSigSetup): array<OutMessage> {
    var claims: map<address, address> = [];
    claims.set(d.m1, osJw(d.m1, d.escrow.address));
    claims.set(d.m2, osJw(d.m2, d.escrow.address));
    var msgs: array<OutMessage> = [];
    msgs.push(
        createMessage({
            bounce: BounceMode.Only256BitsOfBody,
            value: osAcceptValue(),
            dest: { stateInit: d.escrow.stateInit! },
            body: AcceptDeal {
                queryId: 0,
                claims,
            },
        }),
    );
    msgs.push(
        createMessage({
            bounce: BounceMode.Only256BitsOfBody,
            value: OS_FORWARD + OS_NFT_GAS,
            dest: d.nft2,
            body: NftTransfer {
                queryId: 1,
                newOwner: d.escrow.address,
                responseDestination: d.owner2,
                customPayload: null,
                forwardAmount: OS_FORWARD,
                forwardPayload: osDepositPayload(1),
            },
        }),
    );
    msgs.push(osJettonDeposit(d, d.m1, OS_JETTON1, 2));
    msgs.push(osJettonDeposit(d, d.m2, OS_JETTON2, 3));
    return msgs;
}

fun osJettonDeposit(d: OneSigSetup, minter: address, amount: coins, hint: int): OutMessage {
    return createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        value: OS_FORWARD + OS_JETTON_GAS,
        dest: osJw(minter, d.owner2),
        body: JettonTransfer {
            queryId: 2,
            amount,
            destination: d.escrow.address,
            responseDestination: d.owner2,
            customPayload: null,
            forwardTonAmount: OS_FORWARD,
            forwardPayload: osDepositPayload(hint),
        },
    });
}

// What the batch needs from owner2's balance, without forwarding fees.
fun osBatchValue(): coins {
    return osAcceptValue() + OS_FORWARD + OS_NFT_GAS + 2 * (OS_FORWARD + OS_JETTON_GAS);
}

fun osPrintState(d: OneSigSetup) {
    val (r1, r2) = d.escrow.receivedCounts();
    val (s1, s2) = d.escrow.executionShortfall();
    println("phase={} pendingWalletsLeft={}", d.escrow.phase(), d.escrow.pendingWalletsLeft());
    println("received=({}, {}) shortfall=({}, {})", r1, r2, s1, s2);
    val (w2, v2) = d.escrow.jettonWalletStatus(2);
    val (w3, v3) = d.escrow.jettonWalletStatus(3);
    println("jettonWalletStatus(2) = ({}, verified={})", w2, v2);
    println("jettonWalletStatus(3) = ({}, verified={})", w3, v3);
}

// owner1's side after the escrow exists: fee and NFT.
fun osOwner1Deposits(d: OneSigSetup) {
    osWaitFirst(
        d
            .escrow
            .sendAny(d.owner1, osText("service_fee_owner1"), { value: SERVICE_FEE, bounce: true }),
        "service_fee_owner1",
    );
    osWaitTrace(
        net.send(
            d.owner1,
            createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                value: OS_FORWARD + OS_NFT_GAS,
                dest: d.nft1,
                body: NftTransfer {
                    queryId: 1,
                    newOwner: d.escrow.address,
                    responseDestination: d.owner1,
                    customPayload: null,
                    forwardAmount: OS_FORWARD,
                    forwardPayload: osDepositPayload(0),
                },
            }),
        ),
        "nft1 deposit (owner1)",
    );
}

fun osOwnerOf(nft: address): address {
    return net.runGetMethod<address>(nft, "ownerAddr");
}
