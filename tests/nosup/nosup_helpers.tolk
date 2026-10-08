// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Alias "@stdlib/..." (NOT "@acton/tolk-stdlib/...") — the same alias under
// which this physical file is already imported transitively via
// "@acton/testing/expect" above (see the explanation in
// tests/gas_probe.test.tolk). A different alias for the same physical file
// gives "redefinition of a symbol from stdlib".
import "@stdlib/gas-payments"
// Shared test helper (NOT *.test.tolk — a regular module).
// Resolved from test files via `import "nosup_helpers"` (see Acton.toml
// [import-mappings] tests = "tests" — test files and regular modules live
// under the same mapping, so a relative import by file name without an
// extension works).
import "@acton/build"
import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/tolk-stdlib/strings"
import "@acton/types/big_array"
import "@acton/types/message"
import "@acton/types/transaction"
import "@contracts/jetton_minter_mock"
import "@contracts/jetton_mock_lib"
import "@contracts/messages"
import "@contracts/nft_item_mock"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/messages"
import "@contracts/nosup/storage"

// `ownerSide: int` does not compile as a map value — "type `int` is not
// serializable, it doesn't define binary width" (Tolk requires map-value
// fields to have a fixed bit width; the test JettonCfg is stored in
// `map<uint16, JettonCfg>`, so it inherits the same serialization constraint
// as the real Storage). `int8` is the minimal sufficient fixed-width type for
// values 1|2 — comparisons against int literals (`jc.ownerSide == 1`) remain
// valid without extra casts.
struct JettonCfg {
    minter: address
    ownerSide: int8 // 1 | 2
    amount: coins
}

struct EscrowConfig {
    owner1: address
    owner2: address
    feeWallet: address
    nfts1: map<uint16, address>     // index → NFT address for side 1 (indices 0..n1-1)
    nfts1Count: int
    nfts2: map<uint16, address>     // indices n1..n1+n2-1 (unified numbering in assets)
    nfts2Count: int
    gram1Amount: coins
    gram2Amount: coins
    jettons: map<uint16, JettonCfg> // local keys 0..k-1; come AFTER the NFTs in assets
    jettonsCount: int
}

// Base config with no assets and no GRAM — a shared starting point for all
// test files (factored out of the duplicated makeBasicConfig in
// deploy/gram_deposits).
fun makeBasicConfig(o1: Treasury, o2: Treasury, fw: Treasury): EscrowConfig {
    return EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1: [],
        nfts1Count: 0,
        nfts2: [],
        nfts2Count: 0,
        gram1Amount: 0,
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
}

// `acton wrapper SwapEscrowNosup` already generates
// `SwapEscrowNosup.fromStorage(storage: Storage)` (wrappers/SwapEscrowNosup.gen.tolk),
// which accepts an ARBITRARY `Storage` (our custom one with the asset map,
// owners, and phase) and builds the `stateInit`/address itself — exactly what
// is needed to deploy with a custom initial state, without duplicating the
// address-calculation logic. So `EscrowFixture` is simply an alias for the
// generated `SwapEscrowNosup` type; `deployEscrow` takes `stateInit`/`address` from
// it but sends the deploy via an explicit `createMessage` (the deploy_fee
// protocol, see below).
type EscrowFixture = SwapEscrowNosup

fun buildInitialStorage(cfg: EscrowConfig): Storage {
    var assets: map<uint16, Asset> = [];
    var i = 0;
    var r1 = cfg.nfts1.findFirst();
    while (r1.isFound) {
        assets.set(
            i as uint16,
            Asset {
                kind: 0,
                ownerSide: 1,
                addr: r1.loadValue(),
                jettonWallet: null,
                amount: 0,
                received: false,
                walletUnverified: false,
                bounces: 0,
                claimable: false,
            },
        );
        i += 1;
        r1 = cfg.nfts1.iterateNext(r1);
    }
    var r2 = cfg.nfts2.findFirst();
    while (r2.isFound) {
        assets.set(
            i as uint16,
            Asset {
                kind: 0,
                ownerSide: 2,
                addr: r2.loadValue(),
                jettonWallet: null,
                amount: 0,
                received: false,
                walletUnverified: false,
                bounces: 0,
                claimable: false,
            },
        );
        i += 1;
        r2 = cfg.nfts2.iterateNext(r2);
    }

    var jettonsTotal = 0;
    var jr = cfg.jettons.findFirst();
    while (jr.isFound) {
        val jc = jr.loadValue();
        assets.set(
            i as uint16,
            Asset {
                kind: 1,
                ownerSide: jc.ownerSide as uint2,
                addr: jc.minter,
                jettonWallet: null,
                amount: jc.amount,
                received: false,
                walletUnverified: false,
                bounces: 0,
                claimable: false,
            },
        );
        i += 1;
        jettonsTotal += 1;
        jr = cfg.jettons.iterateNext(jr);
    }

    // required counters: NFTs + jettons for each side
    var req1 = cfg.nfts1Count;
    var req2 = cfg.nfts2Count;
    var jr2 = cfg.jettons.findFirst();
    while (jr2.isFound) {
        if (jr2.loadValue().ownerSide == 1) {
            req1 += 1;
        } else {
            req2 += 1;
        }
        jr2 = cfg.jettons.iterateNext(jr2);
    }

    // pendingWallets = number of UNIQUE minters (O(J²) dedup, J is small)
    var pending = 0;
    var ja = cfg.jettons.findFirst();
    var seen: map<uint16, address> = [];
    var seenCount = 0;
    while (ja.isFound) {
        val minter = ja.loadValue().minter;
        var isNew = true;
        var s = seen.findFirst();
        while (s.isFound) {
            if (s.loadValue() == minter) {
                isNew = false;
            }
            s = seen.iterateNext(s);
        }
        if (isNew) {
            seen.set(seenCount as uint16, minter);
            seenCount += 1;
            pending += 1;
        }
        ja = cfg.jettons.iterateNext(ja);
    }

    return Storage {
        swapId: 1,
        phase: pending > 0 ? PHASE_SETUP : PHASE_ACTIVE,
        owner1: cfg.owner1,
        owner2: cfg.owner2,
        feeWallet: cfg.feeWallet,
        assetsCount: i as uint16,
        required1Count: req1 as uint16,
        required2Count: req2 as uint16,
        received1Count: 0,
        received2Count: 0,
        pendingWallets: pending as uint16,
        jettonsCount: jettonsTotal as uint16,
        receivedJettons1: 0,
        receivedJettons2: 0,
        assets,
        grams: GramState {
            gram1Amount: cfg.gram1Amount,
            gram2Amount: cfg.gram2Amount,
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
}

// Deploy the contract with an arbitrary initial Storage — deploy protocol:
// the backend sends the deploy in ONE transaction with the text command
// "deploy_fee" (op 0 + inline ASCII, the same encoding as in sendText) and a
// value of 0.05 TON. The generated SwapEscrowNosup.deploy() is NOT used here — it
// sends an EMPTY body, and the deploy would end up in handlePlainTransfer
// instead of handleTextCommand → handleDeployFee. The stateInit is taken from
// the wrapper (SwapEscrowNosup.fromStorage fills it in from our custom Storage),
// while the deploy itself is an explicit createMessage with dest: { stateInit }.
//
// handleDeployFee is the real handler, and it DOES throw on insufficient
// value (Errors.InsufficientBalance, escrow_nosup_beta_v1.tolk) — the assert below is
// `toHaveSuccessfulDeploy` (deploy: true AND success: true), so any caller
// must attach enough value for the deploy to actually succeed.
// Slots per unique jetton minter of a registry (any key per minter): what
// discoveryValue needs for a deal whose wallets are all unknown.
fun pendingSlotsByMinter(st: Storage): map<uint16, uint16> {
    var seen: map<address, uint16> = [];
    var slots: map<uint16, uint16> = [];
    var count = 0;
    var r = st.assets.findFirst();
    while (r.isFound) {
        val a = r.loadValue();
        if (a.kind == 1) {
            val f = seen.get(a.addr);
            if (f.isFound) {
                val k = f.loadValue();
                slots.set(k, (slots.mustGet(k) + 1) as uint16);
            } else {
                seen.set(a.addr, count as uint16);
                slots.set(count as uint16, 1);
                count += 1;
            }
        }
        r = st.assets.iterateNext(r);
    }
    return slots;
}

// The deploy is sent by a stranger, not by `deployer`: an owner's deploy_fee
// counts as that owner's payment, and the tests built on this fixture keep
// the deploy value unattributed (shared equally), as their expectations
// assume. `deployer` is kept so callers read as before.
fun deployEscrow(deployer: Treasury, cfg: EscrowConfig): EscrowFixture {
    // 0.05 + the per-entry part of the registry scan + one provide per
    // unique minter, priced by its slots as handleDeployFee prices it. The
    // scan's fixed part (DEPLOY_BASE_GAS_UNITS) is inside the 0.05. A deal
    // without jettons gets exactly 0.05 + the per-entry scan, so its money
    // figures do not depend on the provide pricing.
    val st = buildInitialStorage(cfg);
    val escrow = SwapEscrowNosup.fromStorage(st);
    val n = st.assetsCount as int;
    val provides = discoveryValue(n, pendingSlotsByMinter(st)) -
        calculateGasFee(BASECHAIN, DEPLOY_BASE_GAS_UNITS + DEPLOY_GAS_UNITS_PER_ASSET * n);
    val deployValue = ton("0.05") + provides +
        calculateGasFee(BASECHAIN, DEPLOY_GAS_UNITS_PER_ASSET * n);
    val deployMessage = createMessage({
        bounce: BounceMode.NoBounce,
        value: deployValue,
        dest: { stateInit: escrow.stateInit! },
        body: textBody("deploy_fee"),
    });
    val res = net.send(testing.treasury("escrow-deployer").address, deployMessage);
    expect(res).toHaveSuccessfulDeploy({ to: escrow.address });
    return escrow;
}

// Shared text-command builder (op=0 + ASCII), used by both the deploy and
// sendText, so the two cannot silently drift apart.
//
// The body is built manually because `body: "some_text"` in
// `createMessage`/`sendAny` does NOT add the 32-bit op code automatically —
// see the detail in the textCmdIs writeup.
//
// Why not storeString: `builder.storeString(s)`
// stores the string AS A REF (`asm "STREF"`, common.tolk:1328), not as inline
// bits. After `cmd.skipBits(32)` in the router, `cmd` would then point at 0
// bits + 1 ref, while `expected.beginParse().hash()` in `textCmdIs` points at
// a cell with inline bytes and 0 refs: the hashes would never match, and ANY
// command (including known ones like "deploy_fee"/"execute_swap") would fail
// into throw 130, not just an unknown one. So the text is written via
// `storeSlice(text.beginParse())` (`asm "STSLICE"`) — it inserts the string's
// bytes inline into the same root cell, as `textCmdIs` expects.
fun textBody(text: string): cell {
    return beginCell().storeUint(0, 32).storeSlice(text.beginParse()).endCell();
}

// Text command with a value, from an address.
fun EscrowFixture.sendText(self, from: address, text: string, value: coins): SendResultList {
    return self.sendAny(from, textBody(text), { value, bounce: true });
}

// Moved from tests/nft_deposits.test.tolk: the parity matrix reuses these
// helpers alongside runFullSwap below, so they belong in the shared module
// rather than in an individual test file.

// Deploy a mock NFT: build("NftItemMock") — the contract name from Acton.toml
// ([contracts.NftItemMock], NOT a display name, see .acton/build.tolk) — not
// "nft_item_mock", which does not resolve for this project (build() looks up
// the section key, not the file name).
fun deployNft(owner: Treasury, seed: int): address {
    val st = MockNftStorage {
        ownerAddr: owner.address,
        seed: seed as uint32,
        rejectTransfers: false,
    };
    val init = ContractState {
        code: build("NftItemMock"),
        data: st.toCell(),
    };
    val addr = AutoDeployAddress { stateInit: init }.calculateAddress();
    val deployMessage = createMessage({
        bounce: BounceMode.NoBounce,
        value: ton("0.1"),
        dest: { stateInit: init },
    });
    val res = net.send(owner.address, deployMessage);
    expect(res).toHaveSuccessfulDeploy({ to: addr });
    return addr;
}

// The mock is not generated via `acton wrapper` (no typed wrapper) — it is
// simpler, and sufficient for a test, to send the body manually and read the
// getter through net.runGetMethod by address (see the deploy above and
// readMockOwner below).
// hintIdx >= 0 → asset_index goes into forward_payload (either-0 + uint16,
// the escrow's hint format), giving O(1) acceptance.
// hintIdx < 0 (the default) → an empty payload (either-0), accepted via the
// linear fallback — backward compatibility for existing calls without a
// hint.
fun sendNftToEscrow(
    owner: Treasury,
    nft: address,
    escrow: address,
    forwardValue: coins,
    hintIdx: int = -1,
): SendResultList {
    var pb = beginCell().storeUint(0, 1);
    if (hintIdx >= 0) {
        pb = pb.storeUint(hintIdx, 16);
    }
    val m = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        value: forwardValue + ton("0.05"),
        dest: nft,
        body: NftTransfer {
            queryId: 7,
            newOwner: escrow,
            responseDestination: owner.address,
            customPayload: null,
            forwardAmount: forwardValue,
            forwardPayload: pb.endCell().beginParse(),
        },
    });
    return net.send(owner.address, m);
}

fun readMockOwner(nft: address): address {
    return net.runGetMethod(nft, "ownerAddr");
}

// Gas a top-up deposit carries for its own transaction. A top-up of exactly a
// 0.00106 TON shortfall bought 15,917 gas and ran out; the top-up that
// completes a 1x0 deal and runs its execution used 29,721 gas. 0.05 TON buys
// 750,000 gas at today's price, over 25x that.
const TOP_UP_GAS_VALUE = ton("0.05")

// Full scenario: deploy an escrow with n1×n2 NFTs + GRAM amounts, submit all
// deposits for both sides, verify auto-execution.
// Reused by the parity matrix — hence it lives in the shared module rather
// than in tests/auto_execute.test.tolk.
//
// Returns EscrowFixture — the escrow address is needed AFTER the full cycle
// (the "cancel after done rejected 410" test sends cancel_swap once already
// in PHASE_DONE). Existing calls (auto_execute.test.tolk) do not use the
// return value — a call as a standalone statement is fine.
// `forwardPerNft` is optional (default 0.05 TON per NFT deposit). With 0.05,
// a large deal's auto-execution can be held back not by contract gas but by
// the test forward leaving too little balance at the moment of the
// auto-cascade (canAutoExecute compares contract.getOriginalBalance() against
// minBalanceForSwap). The gas probes and the parity matrix therefore pass
// ton("0.20") explicitly, so what they measure is gas, not a shortfall in the
// test forward.
fun runFullSwap(
    n1: int,
    n2: int,
    gram1: coins,
    gram2: coins,
    forwardPerNft: coins = ton("0.05"),
    topUp: bool = false,
): EscrowFixture {
    val o1 = testing.treasury("rf-o1");
    val o2 = testing.treasury("rf-o2");
    val fw = testing.treasury("rf-fw");

    var nfts1: map<uint16, address> = [];
    var i = 0;
    while (i < n1) {
        nfts1.set(i as uint16, deployNft(o1, 1000 + i));
        i += 1;
    }
    var nfts2: map<uint16, address> = [];
    var j = 0;
    while (j < n2) {
        nfts2.set(j as uint16, deployNft(o2, 2000 + j));
        j += 1;
    }

    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: n1,
        nfts2,
        nfts2Count: n2,
        gram1Amount: gram1,
        gram2Amount: gram2,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    // side-1 deposits
    if (gram1 > 0) {
        expect(
            escrow.sendText(o1.address, "deposit_ton1", gram1 + ton("0.01")),
        ).toHaveAllSuccessfulTxs();
    }
    var lastRes = escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE);
    expect(lastRes).toHaveAllSuccessfulTxs();
    // Global asset index (for the O(1) acceptance hint): nfts1 occupy indices
    // 0..n1-1 in the registry (buildInitialStorage places them first), nfts2
    // occupy n1..n1+n2-1. The map key matches the local position.
    var r1 = nfts1.findFirst();
    while (r1.isFound) {
        lastRes = sendNftToEscrow(
            o1,
            r1.loadValue(),
            escrow.address,
            forwardPerNft,
            r1.getKey() as int,
        );
        expect(lastRes).toHaveAllSuccessfulTxs();
        r1 = nfts1.iterateNext(r1);
    }
    // side-2 deposits
    if (gram2 > 0) {
        lastRes = escrow.sendText(o2.address, "deposit_ton2", gram2 + ton("0.01"));
        expect(lastRes).toHaveAllSuccessfulTxs();
    }
    lastRes = escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE);
    expect(lastRes).toHaveAllSuccessfulTxs();
    // A side whose own deposits cannot carry its half of the shared costs
    // pays the rest as TON before the last deposits; what its NFT forwards
    // then also cover comes back in its refund. The top-up also carries the
    // gas of its own transaction (TOP_UP_GAS_VALUE): a shortfall can be
    // smaller than the gas one deposit needs, and when the top-up is the last
    // deposit it runs the execution. What it pays above the shortfall comes
    // back in the same refund.
    if (topUp) {
        val (s1, s2) = escrow.executionShortfall();
        if (s1 > 0) {
            lastRes = escrow.sendText(o1.address, "deposit_ton1", s1 + TOP_UP_GAS_VALUE);
            expect(lastRes).toHaveAllSuccessfulTxs();
        }
        if (s2 > 0) {
            lastRes = escrow.sendText(o2.address, "deposit_ton2", s2 + TOP_UP_GAS_VALUE);
            expect(lastRes).toHaveAllSuccessfulTxs();
        }
    }
    var r2 = nfts2.findFirst();
    while (r2.isFound) {
        lastRes = sendNftToEscrow(
            o2,
            r2.loadValue(),
            escrow.address,
            forwardPerNft,
            n1 + (r2.getKey() as int),
        );
        expect(lastRes).toHaveAllSuccessfulTxs();
        r2 = nfts2.iterateNext(r2);
    }

    // Outcome checks: auto-execution should have fired on the last deposit
    // (the last call above is the one that pushed received/gram/fee over the
    // threshold).
    expect(escrow.phase()).toEqual(PHASE_DONE);
    var c1 = nfts1.findFirst();
    while (c1.isFound) {
        expect(readMockOwner(c1.loadValue())).toEqual(o2.address);
        c1 = nfts1.iterateNext(c1);
    }
    var c2 = nfts2.findFirst();
    while (c2.isFound) {
        expect(readMockOwner(c2.loadValue())).toEqual(o1.address);
        c2 = nfts2.iterateNext(c2);
    }
    // fee_wallet received at least serviceFee1+serviceFee2 (0.2 GRAM) out of
    // the 2 x SERVICE_FEE transfer within the cascade triggered by the last
    // deposit (lastRes contains the full executeSwap transaction tree —
    // GRAM/NFT/fee/refund/dust).
    expect(lastRes).toHaveTx({
        to: fw.address,
        value: fun(v: coins): bool {
            return v >= ton("0.19");
        },
    });
    return escrow;
}

// An ACTIVE NFT deal whose side-1 registry has `n` entries. The first
// `deposited` are real NFTs, deposited by owner 1 with a 0.05 forward and
// their index hint; the rest are synthetic addresses that only give the
// registry its size. No fee is paid, so nothing executes.
struct ActiveRegistry {
    escrow: EscrowFixture
    o1: Treasury
    o2: Treasury
    fw: Treasury
    nfts: map<uint16, address> // the deposited items, by registry index
}

fun deployActiveRegistry(tag: string, n: int, deposited: int, seedBase: int): ActiveRegistry {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    var entries: map<uint16, address> = [];
    var nfts: map<uint16, address> = [];
    var i = 0;
    while (i < n) {
        if (i < deposited) {
            val nft = deployNft(o1, seedBase + i);
            nfts.set(i as uint16, nft);
            entries.set(i as uint16, nft);
        } else {
            entries.set(i as uint16, address.fromWorkchainAndHash(0, seedBase + i));
        }
        i += 1;
    }
    var cfg = makeBasicConfig(o1, o2, fw);
    cfg.nfts1 = entries;
    cfg.nfts1Count = n;
    val escrow = deployEscrow(o1, cfg);
    i = 0;
    while (i < deposited) {
        expect(
            sendNftToEscrow(o1, nfts.mustGet(i as uint16), escrow.address, ton("0.05"), i),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    return ActiveRegistry { escrow, o1, o2, fw, nfts };
}

// ── Jetton mock helpers ──

fun deployJettonMinter(deployer: Treasury, seed: int): address {
    val st = MinterMockStorage {
        seed: seed as uint32,
        walletCode: build("JettonWalletMock"),
    };
    val init = ContractState {
        code: build("JettonMinterMock"),
        data: st.toCell(),
    };
    val addr = AutoDeployAddress { stateInit: init }.calculateAddress();
    val res = net.send(
        deployer.address,
        createMessage({ bounce: BounceMode.NoBounce, value: ton("0.1"), dest: {
                stateInit: init,
            } }),
    );
    expect(res).toHaveSuccessfulDeploy({ to: addr });
    return addr;
}

// Jetton wallet address of owner `owner` at minter `minter` (mock derivation).
fun jwAddr(minter: address, owner: address): address {
    return walletAddrFor(minter, owner, build("JettonWalletMock"));
}

fun mintJettons(minter: address, to: Treasury, amount: coins) {
    val m = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        value: ton("0.1"),
        dest: minter,
        body: MintMock {
            queryId: 0,
            to: to.address,
            amount,
        },
    });
    expect(net.send(to.address, m)).toHaveAllSuccessfulTxs();
}

fun readJettonBalance(minter: address, owner: address): coins {
    return net.runGetMethod(jwAddr(minter, owner), "jettonBalance");
}

// Jetton transfer from the owner's wallet to an arbitrary recipient owner.
// hintIdx >= 0 → forward_payload gets an either-bit 0 + uint16 hintIdx (the
// escrow's hint format); hintIdx < 0 → an empty payload
// (a single either-bit 0).
fun sendJettonTransfer2(
    owner: Treasury,
    minter: address,
    destOwner: address,
    amount: coins,
    forwardTon: coins,
    hintIdx: int,
): SendResultList {
    var pb = beginCell().storeUint(0, 1);
    if (hintIdx >= 0) {
        pb = pb.storeUint(hintIdx, 16);
    }
    val m = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        value: forwardTon + ton("0.08"),
        dest: jwAddr(minter, owner.address),
        body: JettonTransfer {
            queryId: 7,
            amount,
            destination: destOwner,
            responseDestination: owner.address,
            customPayload: null,
            forwardTonAmount: forwardTon,
            forwardPayload: pb.endCell().beginParse(),
        },
    });
    return net.send(owner.address, m);
}

// ── Moved from tests/jetton_deposits.test.tolk so jetton_cancel.test.tolk
// can reuse jdSetup without duplicating the fixture — jetton_deposits.test.tolk
// uses this same copy via its existing `import "escrow_helpers"`. ──

struct JdFixture {
    o1: Treasury
    o2: Treasury
    fw: Treasury
    minter: address
    escrow: EscrowFixture
}

// `tag + "-o1"` does not compile — "can not apply operator `+` to `string`
// and `string`" (Tolk's `string` is a compile-time builtin, `+` is not
// defined for it, unlike FunC/JS-style concatenation). The working runtime
// way to concatenate is `StringBuilder` (strings.tolk:107-172).
fun tagged(tag: string, suffix: string): string {
    return StringBuilder.create().append(tag).append(suffix).build();
}

// Deal: side-1 jetton (100), side-2 jetton (50) — a SINGLE minter on both
// sides (a required case), no NFT/GRAM. Both start with a balance of 500.
fun jdSetup(tag: string, seed: int): JdFixture {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val minter = deployJettonMinter(o1, seed);
    mintJettons(minter, o1, ton("500"));
    mintJettons(minter, o2, ton("500"));
    var cfg = makeBasicConfig(o1, o2, fw);
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter,
            ownerSide: 1,
            amount: ton("100"),
        },
    );
    js.set(
        1,
        JettonCfg {
            minter,
            ownerSide: 2,
            amount: ton("50"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 2;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    return JdFixture { o1, o2, fw, minter, escrow };
}

// A mixed runner modeled on runFullSwap — NFTs + jettons (one minter) on
// EACH side plus GRAM, a full cycle through to DONE. Lives in the shared
// module because the parity matrix, and potentially other test files, can
// reuse a mixed deal without duplicating the config/deposit-cycle assembly
// (the same way runFullSwap is already reused by parity_matrix/auto_execute).
//
// n1/n2 — number of NFTs on side 1/2; k1/k2 — number of jetton entries for a
// single minter (amount ton("1") each, the same methodology as runJettonSwap
// above); gram1/gram2 — GRAM exchange amounts. forwardPerNft follows the gas
// probe methodology (ton("0.20") for the parity matrix, see the
// comment above runFullSwap); forwardPerJetton is fixed at ton("0.2") — the
// same forward used in runJettonSwap (gas_probe.test.tolk) and the jdSetup
// family of tests.
fun runMixedSwap(
    n1: int,
    k1: int,
    n2: int,
    k2: int,
    gram1: coins,
    gram2: coins,
    forwardPerNft: coins = ton("0.20"),
): EscrowFixture {
    val o1 = testing.treasury("rm-o1");
    val o2 = testing.treasury("rm-o2");
    val fw = testing.treasury("rm-fw");

    var nfts1: map<uint16, address> = [];
    var i = 0;
    while (i < n1) {
        nfts1.set(i as uint16, deployNft(o1, 3000 + i));
        i += 1;
    }
    var nfts2: map<uint16, address> = [];
    var j = 0;
    while (j < n2) {
        nfts2.set(j as uint16, deployNft(o2, 4000 + j));
        j += 1;
    }

    val minter = deployJettonMinter(o1, 91);
    mintJettons(minter, o1, ton("100000"));
    mintJettons(minter, o2, ton("100000"));
    var js: map<uint16, JettonCfg> = [];
    var ji = 0;
    while (ji < k1) {
        js.set(
            ji as uint16,
            JettonCfg {
                minter,
                ownerSide: 1,
                amount: ton("1"),
            },
        );
        ji += 1;
    }
    var jj = 0;
    while (jj < k2) {
        js.set(
            (k1 + jj) as uint16,
            JettonCfg {
                minter,
                ownerSide: 2,
                amount: ton("1"),
            },
        );
        jj += 1;
    }

    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: n1,
        nfts2,
        nfts2Count: n2,
        gram1Amount: gram1,
        gram2Amount: gram2,
        jettons: js,
        jettonsCount: k1 + k2,
    };
    val escrow = deployEscrow(o1, cfg);

    // side-1 deposits: GRAM, fee, NFT, jettons (in this order — as in
    // jetton_swap.test.tolk "mixed NFT+jetton swap auto-executes")
    if (gram1 > 0) {
        expect(
            escrow.sendText(o1.address, "deposit_ton1", gram1 + ton("0.01")),
        ).toHaveAllSuccessfulTxs();
    }
    var lastRes = escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE);
    expect(lastRes).toHaveAllSuccessfulTxs();
    // Global NFT index for the O(1) hint: nfts1 → 0..n1-1, nfts2 →
    // n1..n1+n2-1 (buildInitialStorage: NFT1, NFT2, then jettons).
    var r1 = nfts1.findFirst();
    while (r1.isFound) {
        lastRes = sendNftToEscrow(
            o1,
            r1.loadValue(),
            escrow.address,
            forwardPerNft,
            r1.getKey() as int,
        );
        expect(lastRes).toHaveAllSuccessfulTxs();
        r1 = nfts1.iterateNext(r1);
    }
    var i1 = 0;
    while (i1 < k1) {
        lastRes = sendJettonTransfer2(
            o1,
            minter,
            escrow.address,
            ton("1"),
            ton("0.2"),
            i1,
        );
        expect(lastRes).toHaveAllSuccessfulTxs();
        i1 += 1;
    }
    // side-2 deposits: GRAM, fee, NFT, jettons (the last one triggers auto)
    if (gram2 > 0) {
        lastRes = escrow.sendText(o2.address, "deposit_ton2", gram2 + ton("0.01"));
        expect(lastRes).toHaveAllSuccessfulTxs();
    }
    lastRes = escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE);
    expect(lastRes).toHaveAllSuccessfulTxs();
    var r2 = nfts2.findFirst();
    while (r2.isFound) {
        lastRes = sendNftToEscrow(
            o2,
            r2.loadValue(),
            escrow.address,
            forwardPerNft,
            n1 + (r2.getKey() as int),
        );
        expect(lastRes).toHaveAllSuccessfulTxs();
        r2 = nfts2.iterateNext(r2);
    }
    var j2 = 0;
    while (j2 < k2) {
        lastRes = sendJettonTransfer2(
            o2,
            minter,
            escrow.address,
            ton("1"),
            ton("0.2"),
            k1 + j2,
        );
        expect(lastRes).toHaveAllSuccessfulTxs();
        j2 += 1;
    }

    // Outcome checks: auto-execution on the last deposit.
    expect(escrow.phase()).toEqual(PHASE_DONE);
    var c1 = nfts1.findFirst();
    while (c1.isFound) {
        expect(readMockOwner(c1.loadValue())).toEqual(o2.address);
        c1 = nfts1.iterateNext(c1);
    }
    var c2 = nfts2.findFirst();
    while (c2.isFound) {
        expect(readMockOwner(c2.loadValue())).toEqual(o1.address);
        c2 = nfts2.iterateNext(c2);
    }
    // the escrow's jettons are emptied out — all k1+k2 entries have been
    // handed to the opposite sides
    expect(readJettonBalance(minter, escrow.address)).toEqual(0);
    expect(lastRes).toHaveTx({
        to: fw.address,
        value: fun(v: coins): bool {
            return v >= ton("0.19");
        },
    });
    return escrow;
}

// ── Fixture: "broken chain" ──
// Deploys a deal DIRECTLY in a broken-delivery state ("broken chain → kick"):
// phase EXECUTING, cursor in the middle. In emulation, the continue cascade
// is applied atomically within a single net.send — there is no way to
// actually interrupt it, so the mid-state is constructed directly in
// StateInit (exactly the state the contract would be in on a real network if
// the continue message were lost or failed).
//
// The circular address dependency (the escrow address depends on the NFT
// addresses in Storage, while the NFT owner must be the escrow itself —
// otherwise an outgoing NftTransfer from the escrow would not pass the
// mock's owner check) is broken using a test-only mock opcode, SetNftOwner:
// (1) the mocks are deployed by the deployer-owner (the normal path, with
// addresses deterministic from {deployer, seed}); (2) the escrow address is
// computed from the assembled Storage; (3) each NFT mock is sent
// SetNftOwner(escrow); (4) the escrow is deployed with an `Excesses` message —
// Excesses is credited silently in any phase, so the mid-state deploy does
// not have to pass through a deposit handler to reach EXECUTING or CANCELLED.
fun deployEscrowMidDistribution(
    deployer: Treasury,
    cfg: EscrowConfig,
    cursorAt: int,
    mode: int = DIST_EXECUTE,
): EscrowFixture {
    assert (mode == DIST_EXECUTE || mode == DIST_CANCEL) throw 0xBAD;
    // `mode` parameter (default DIST_EXECUTE).
    // DIST_EXECUTE → phase EXECUTING; DIST_CANCEL → phase CANCELLED, as in
    // the real handler after the balance check/refunds. All assets are still
    // marked received either way (the mid-state is only reachable after a
    // full deposit collection).
    val execPhase = mode == DIST_EXECUTE ? PHASE_EXECUTING : PHASE_CANCELLED;
    var st = buildInitialStorage(cfg);
    st.phase = execPhase;
    // all assets are marked received (EXECUTING is only reachable after a
    // full deposit collection)
    var i = 0;
    while (i < (st.assetsCount as int)) {
        var a = st.assets.mustGet(i as uint16);
        a.received = true;
        st.assets.set(i as uint16, a);
        i += 1;
    }
    st.received1Count = st.required1Count;
    st.received2Count = st.required2Count;
    st.dist = DistState {
        mode: mode as uint3,
        cursor: cursorAt as uint16,
    }.toCell();
    val escrow = SwapEscrowNosup.fromStorage(st);

    // Transfer ownership of all NFT mocks to the escrow (SetNftOwner is a
    // test-only opcode).
    var r = st.assets.findFirst();
    while (r.isFound) {
        val a = r.loadValue();
        if (a.kind == 0) {
            val m = createMessage({
                bounce: BounceMode.NoBounce,
                value: ton("0.05"),
                dest: a.addr,
                body: SetNftOwner {
                    queryId: 0,
                    newOwner: escrow.address,
                },
            });
            expect(net.send(deployer.address, m)).toHaveAllSuccessfulTxs();
        }
        r = st.assets.iterateNext(r);
    }

    val deployMessage = createMessage({
        bounce: BounceMode.NoBounce,
        value: ton("10"),
        dest: { stateInit: escrow.stateInit! },
        // Excesses is credited silently in any phase, so the escrow can be
        // deployed straight into EXECUTING or CANCELLED without passing
        // through a deposit handler.
        body: Excesses { queryId: 0 },
    });
    expect(
        net.send(deployer.address, deployMessage),
    ).toHaveSuccessfulDeploy({ to: escrow.address });
    expect(net.runGetMethod<int>(escrow.address, "phase")).toEqual(execPhase);
    return escrow;
}

// ─────────────────────────────────────────────────────────────────────────
// A synthetic check of the GASCONSUMED safeguard (BATCH_GAS_SOFT_CAP=600000).
// The cancel cursor walks the ENTIRE registry (not just received assets),
// skipping unreceived assets (received=false) WITHOUT sending — but every
// skip still costs gas (assets.mustGet — a dict lookup). A long tail of
// unreceived entries exhausts the soft cap ON ITS OWN, before the cursor
// even reaches the actually received (received=true) assets in the tail of
// the registry — the batch must stop (preserving the cursor, NOT failing on
// gas) and finish on the next continue. Construction: a skip zone of "empty"
// entries (a dummy address — received=false, sendAsset is never called, so
// the address does not need to be a real NFT contract — no actual deploy of
// that many NFTs is required) + a tail of real NFTs (received=true, actually
// delivered to the depositor on cancel).
// ─────────────────────────────────────────────────────────────────────────

struct SparseCancelFixture {
    escrow: EscrowFixture
    o1: Treasury
    o2: Treasury
    fw: Treasury
    tailNfts: map<uint16, address>
}

// `distinctSkip`: give every skip entry its own address. With one shared
// address the skip entries are identical cells and the account's stored size
// is deduplicated to a fraction of a real registry's, which matters wherever
// the storage fee is measured. `deployValue` is the escrow's starting balance.
fun deploySparseCancelMidState(
    tag: string,
    skipCount: int,
    tailCount: int,
    distinctSkip: bool = false,
    deployValue: coins = ton("5"),
): SparseCancelFixture {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val dummy = testing.treasury(tagged(tag, "-dummy"));

    // Skip zone: "empty" side-1 entries, all pointing at ONE dummy address
    // unless distinctSkip (never dereferenced — received=false, sendAsset is
    // not called).
    var nfts1: map<uint16, address> = [];
    var i = 0;
    while (i < skipCount) {
        nfts1.set(
            i as uint16,
            distinctSkip ? address.fromWorkchainAndHash(0, 0x5100000 + i) : dummy.address,
        );
        i += 1;
    }
    // Tail: real side-2 NFTs — the only ones that will actually be sent.
    var tailNfts: map<uint16, address> = [];
    var j = 0;
    while (j < tailCount) {
        tailNfts.set(j as uint16, deployNft(o1, 80000 + j));
        j += 1;
    }
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: skipCount,
        nfts2: tailNfts,
        nfts2Count: tailCount,
        gram1Amount: 0,
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    var st = buildInitialStorage(cfg);
    // buildInitialStorage already sets received=false for ALL assets — exactly
    // what the skip zone needs. The tail (the last tailCount entries — nfts2)
    // is flipped to received=true: as if side 2 actually deposited its
    // assets while side 1 (skipCount dummy entries) did not (the deal is
    // cancelled while side 1 still hasn't finished the registry — a typical
    // "broken chain" scenario).
    val total = st.assetsCount as int;
    var k = skipCount;
    while (k < total) {
        var a = st.assets.mustGet(k as uint16);
        a.received = true;
        st.assets.set(k as uint16, a);
        k += 1;
    }
    st.received2Count = tailCount as uint16;
    st.phase = PHASE_CANCELLED;
    st.dist = DistState {
        mode: DIST_CANCEL,
        cursor: 0,
    }.toCell();

    val escrow = SwapEscrowNosup.fromStorage(st);

    // Transfer ownership of the tail NFTs to the escrow (a test opcode,
    // SetNftOwner, as in deployEscrowMidDistribution) — the skip zone uses a
    // single dummy address and is never dereferenced by the contract, so
    // real mock contracts for the skip zone are NOT needed (saves wall time).
    var r = tailNfts.findFirst();
    while (r.isFound) {
        val m = createMessage({
            bounce: false,
            value: ton("0.05"),
            dest: r.loadValue(),
            body: SetNftOwner {
                queryId: 0,
                newOwner: escrow.address,
            },
        });
        expect(net.send(o1.address, m)).toHaveAllSuccessfulTxs();
        r = tailNfts.iterateNext(r);
    }

    val deployMessage = createMessage({
        bounce: false,
        value: deployValue,
        dest: { stateInit: escrow.stateInit! },
        // Excesses is credited silently in any phase, so the escrow can be
        // deployed straight into EXECUTING or CANCELLED without passing
        // through a deposit handler.
        body: Excesses { queryId: 0 },
    });
    expect(net.send(o1.address, deployMessage)).toHaveSuccessfulDeploy({ to: escrow.address });
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);

    return SparseCancelFixture { escrow, o1, o2, fw, tailNfts };
}

// ── Shared bounce/claim fixtures, used by both tests/nosup/bounce.test.tolk
// and tests/nosup/claim.test.tolk. ──

fun setReject(from: address, nft: address, reject: bool) {
    val m = createMessage({
        bounce: BounceMode.NoBounce,
        value: ton("0.05"),
        dest: nft,
        body: SetNftReject {
            queryId: 0,
            reject,
        },
    });
    expect(net.send(from, m)).toHaveAllSuccessfulTxs();
}

// True if the transaction's compute phase ran to completion without
// throwing. Used after an injected bounce to confirm onBouncedMessage
// actually returned normally — a thrown exception also rolls back any
// storage write, so without this check a broken guard that crashes could
// look identical to one that correctly ignores the bounce.
fun SendResult.ranWithoutThrow(self): bool {
    val descr = self.tx.load().description.load();
    if (descr is TlbTransOrd) {
        return !descr.aborted;
    }
    return false;
}

// Builds a synthetic bounced message the way the network would after a
// failed BounceMode.Only256BitsOfBody delivery — 0xFFFFFFFF followed by the
// first bits of the original outgoing body (op + queryId, all
// onBouncedMessage ever reads) — and delivers it directly to `escrow` with
// testing.processSingleTraceStep (single transaction, no recursive
// re-delivery). This exercises each guard in onBouncedMessage in isolation,
// without needing a real failing NFT/jetton transfer to produce it.
fun injectBounce(from: address, escrow: address, op: int, queryId: int): SendResult {
    val body = beginCell()
        .storeUint(0xFFFFFFFF, 32)
        .storeUint(op, 32)
        .storeUint(queryId, 64)
        .endCell();
    val msg = createMessage({
        bounce: BounceMode.NoBounce,
        value: ton("0.05"),
        dest: escrow,
        body,
    }).bounced();
    return testing.processSingleTraceStep(from, msg);
}

struct Deal1x1 {
    escrow: EscrowFixture
    o1: Treasury
    o2: Treasury
    fw: Treasury
    nft1: address
    nft2: address
}

// 1 NFT per side, both deposited except side 2's service fee.
fun setup1x1(tag: string, seed: int): Deal1x1 {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val nft1 = deployNft(o1, seed);
    val nft2 = deployNft(o2, seed + 1);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, nft1);
    var n2: map<uint16, address> = [];
    n2.set(0, nft2);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    cfg.nfts2 = n2;
    cfg.nfts2Count = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, nft1, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o2, nft2, escrow.address, ton("0.2"), 1)).toHaveAllSuccessfulTxs();
    return Deal1x1 { escrow, o1, o2, fw, nft1, nft2 };
}

// A deal with a jetton of `minter` on side 1 and one of a minter that never
// answers on side 2: it stays in SETUP. `silentFirst` puts the silent minter's
// slot first in the registry.
struct SetupDeal {
    escrow: EscrowFixture
    o1: Treasury
    o2: Treasury
    minter: address
    silent: Treasury
}

fun setupWithSilentMinter(tag: string, seed: int, silentFirst: bool): SetupDeal {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val silent = testing.treasury(tagged(tag, "-silent"));
    val minter = deployJettonMinter(o1, seed);
    mintJettons(minter, o1, ton("500"));
    var cfg = makeBasicConfig(o1, o2, fw);
    val ours = JettonCfg {
        minter,
        ownerSide: 1,
        amount: ton("100"),
    };
    val theirs = JettonCfg {
        minter: silent.address,
        ownerSide: 2,
        amount: ton("5"),
    };
    var js: map<uint16, JettonCfg> = [];
    js.set(0, silentFirst ? theirs : ours);
    js.set(1, silentFirst ? ours : theirs);
    cfg.jettons = js;
    cfg.jettonsCount = 2;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.phase()).toEqual(PHASE_SETUP);
    return SetupDeal { escrow, o1, o2, minter, silent };
}

// A take_wallet_address body. `wallet == null` encodes addr_none, which a
// minter sends for an owner it does not serve (TEP-89).
fun takeWalletBody(queryId: int, wallet: address?): cell {
    var b = beginCell().storeUint(0xd1735400, 32).storeUint(queryId, 64);
    if (wallet == null) {
        b = b.storeUint(0, 2);
    } else {
        b = b.storeAddress(wallet!);
    }
    return b.storeUint(0, 1).endCell();
}

// Deliver a take_wallet_address from `minter` (any address the test can send
// from) to `escrow`.
fun sendTakeWallet(minter: address, escrow: address, wallet: address?): SendResultList {
    return net.send(
        minter,
        createMessage({
            bounce: BounceMode.NoBounce,
            value: ton("0.05"),
            dest: escrow,
            body: takeWalletBody(0, wallet),
        }),
    );
}

// The escrow for `cfg`, not deployed: AcceptDeal deploys it.
fun prepareEscrow(cfg: EscrowConfig): EscrowFixture {
    return SwapEscrowNosup.fromStorage(buildInitialStorage(cfg));
}

// owner2's AcceptDeal. `withInit` attaches the escrow's StateInit, as the first
// message of a one-signature batch does.
fun sendAcceptDeal(
    from: address,
    escrow: EscrowFixture,
    claims: map<address, address>,
    value: coins,
    withInit: bool,
): SendResultList {
    if (withInit) {
        return net.send(
            from,
            createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                value,
                dest: { stateInit: escrow.stateInit! },
                body: AcceptDeal {
                    queryId: 0,
                    claims,
                },
            }),
        );
    }
    return net.send(
        from,
        createMessage({
            bounce: BounceMode.Only256BitsOfBody,
            value,
            dest: escrow.address,
            body: AcceptDeal {
                queryId: 0,
                claims,
            },
        }),
    );
}

// What starting discovery costs on an n-entry registry: one provide per
// minter with a pending slot plus the registry scan. `slots` holds, per
// minter (any key), how many of its slots are pending. Mirrors
// Storage.discoveryCost byte for byte.
fun discoveryValue(n: int, slots: map<uint16, uint16>): coins {
    var total: coins = calculateGasFee(
        BASECHAIN,
        DEPLOY_BASE_GAS_UNITS + DEPLOY_GAS_UNITS_PER_ASSET * n,
    );
    var r = slots.findFirst();
    while (r.isFound) {
        total += PROVIDE_WALLET_VALUE +
            calculateGasFee(
                BASECHAIN,
                TAKE_SCAN_BASE_UNITS + TAKE_SCAN_UNITS_PER_ENTRY * n +
                    TAKE_SET_UNITS * (r.loadValue() as int),
            );
        r = slots.iterateNext(r);
    }
    return total;
}

// A deal for the one-signature flow, prepared but not deployed.
// Registry: 0 nft1 (side 1); 1 nft2 (side 2); 2 jetton of m1, 10 (side 2);
// 3 jetton of m2, 20 (side 2). owner2 holds 100 of each jetton.
struct OneSigDeal {
    escrow: EscrowFixture
    o1: Treasury
    o2: Treasury
    fw: Treasury
    m1: address
    m2: address
    nft1: address
    nft2: address
}

fun oneSigDeal(tag: string, seed: int): OneSigDeal {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val m1 = deployJettonMinter(o2, seed);
    val m2 = deployJettonMinter(o2, seed + 1);
    mintJettons(m1, o2, ton("100"));
    mintJettons(m2, o2, ton("100"));
    val nft1 = deployNft(o1, seed + 2);
    val nft2 = deployNft(o2, seed + 3);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, nft1);
    var b: map<uint16, address> = [];
    b.set(0, nft2);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = 1;
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter: m1,
            ownerSide: 2,
            amount: ton("10"),
        },
    );
    js.set(
        1,
        JettonCfg {
            minter: m2,
            ownerSide: 2,
            amount: ton("20"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 2;
    return OneSigDeal {
        escrow: prepareEscrow(cfg),
        o1,
        o2,
        fw,
        m1,
        m2,
        nft1,
        nft2,
    };
}

// What the dapp claims: the escrow's wallets from each minter's derivation.
fun OneSigDeal.trueClaims(self): map<address, address> {
    var c: map<address, address> = [];
    c.set(self.m1, jwAddr(self.m1, self.escrow.address));
    c.set(self.m2, jwAddr(self.m2, self.escrow.address));
    return c;
}

fun OneSigDeal.discovery(self): coins {
    var s: map<uint16, uint16> = [];
    s.set(0, 1);
    s.set(1, 1);
    return discoveryValue(4, s);
}

// AcceptDeal below the discovery price writes the claims but asks no minter,
// so the deposits that follow arrive before any answer. (SERVICE_FEE alone
// would already cover discovery on this 4-entry registry.) The fee is then
// completed separately.
fun acceptWithoutDiscovery(d: OneSigDeal, claims: map<address, address>) {
    expect(
        sendAcceptDeal(d.o2.address, d.escrow, claims, d.discovery() - 1, true),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.pendingWalletsLeft()).toEqual(2);
    expect(
        d.escrow.sendText(d.o2.address, "service_fee_owner2", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
}

// A transfer_notification sent directly from `from` — a fake unless `from`
// is the escrow's real jetton wallet.
fun fakeNotification(
    from: address,
    escrow: address,
    depositor: address,
    amount: coins,
    hintIdx: int,
    value: coins,
): SendResultList {
    var pb = beginCell().storeUint(0, 1);
    if (hintIdx >= 0) {
        pb = pb.storeUint(hintIdx, 16);
    }
    return net.send(
        from,
        createMessage({
            bounce: BounceMode.NoBounce,
            value,
            dest: escrow,
            body: JettonTransferNotification {
                queryId: 1,
                amount,
                sender: depositor,
                forwardPayload: pb.endCell().beginParse(),
            },
        }),
    );
}

// Gas of the heaviest transaction `who` ran in this trace.
fun maxGasOn(res: SendResultList, who: address): int {
    var m = 0;
    var i = 0;
    while (i < res.size()) {
        val r = res.at(i);
        if (r.tx.load().getAccountAddress() == who && r.gasUsed > m) {
            m = r.gasUsed;
        }
        i += 1;
    }
    return m;
}

// Each side pays what executionShortfall names, plus 0.001 TON for the first
// payment's own gas (the getter's documented margin); side 2 first.
fun payShortfalls(escrow: EscrowFixture, o1: Treasury, o2: Treasury) {
    val (s1, s2) = escrow.executionShortfall();
    if (s2 > 0) {
        escrow.sendText(o2.address, "deposit_ton2", s2 + ton("0.001"));
    }
    if (s1 > 0) {
        escrow.sendText(o1.address, "deposit_ton1", s1 + ton("0.001"));
    }
}

// Scale the basechain gas price by num/den; returns the previous config so
// the caller can restore it.
fun scaleGasPrice(num: int, den: int): BlockchainConfigMap {
    val original = testing.getConfig();
    var cfg = testing.getConfig();
    var gp = cfg.getGasPrices(BASECHAIN);
    gp.flatGasPrice = (gp.flatGasPrice * num / den) as uint64;
    gp.other.gasPrice = (gp.other.gasPrice * num / den) as uint64;
    cfg.setGasPrices(gp, BASECHAIN);
    expect(testing.setConfig(cfg)).toEqual(true);
    return original;
}

// The contract's model of AcceptDeal's gas (Storage.acceptWorkUnits).
fun acceptModel(n: int, jettons: int): int {
    return ACCEPT_BASE_UNITS + ACCEPT_UNITS_PER_ENTRY * n + ACCEPT_UNITS_PER_CLAIM * jettons;
}

// What AcceptDeal must carry to start discovery itself: the discovery price
// plus the gas of its own claim and discovery passes (the contract's model).
fun acceptDiscoveryValue(n: int, jettons: int, slots: map<uint16, uint16>): coins {
    return discoveryValue(n, slots) + calculateGasFee(BASECHAIN, acceptModel(n, jettons));
}

// The most claimed slots a jetton-only registry may have for AcceptDeal to
// write them.
fun largestClaimedRegistry(): int {
    var j = 1;
    while (acceptModel(j + 1, j + 1) <= TX_GAS_LIMIT_CEILING) {
        j += 1;
    }
    return j;
}

// TON that `from` sent to `to` in this trace (the value of every message
// `to` received from `from`).
fun valueSentTo(res: SendResultList, from: address, to: address): coins {
    var sum: coins = 0;
    var i = 0;
    while (i < res.size()) {
        val tx = res.at(i).tx.load();
        if (tx.getAccountAddress() == to) {
            val m = tx.loadInMsg<RemainingBitsAndRefs>();
            val info = m.info;
            if (info is TlbInternalMessage) {
                if (info.src == from) {
                    sum += info.value.grams;
                }
            }
        }
        i += 1;
    }
    return sum;
}

// claim_asset from `from` for registry index `idx`, carrying `value`.
fun sendClaim(from: address, escrow: address, idx: int, value: coins): SendResultList {
    val m = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        value,
        dest: escrow,
        body: ClaimAsset {
            queryId: 0,
            assetIndex: idx as uint16,
        },
    });
    return net.send(from, m);
}
