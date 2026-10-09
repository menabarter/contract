// GENERATED from tests/nosup/section2_limits.test.tolk by ts-tests/gen-v2-tests.ts — edit the source, then run npm run gen:v2.
// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// The registry sizes the one-signature flow handles. AcceptDeal writes claims
// and starts discovery only while its modelled gas fits one transaction;
// above that it only credits, so it never fails for its size and the batch's
// transfers always find the escrow.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowV2.gen"
import "@contracts/shared/types"
import "@contracts/v2/storage"
import "v2_helpers"

// `jettons` slots of one minter on side 2 and `nfts` dummy NFT entries on
// side 1, prepared; claims for the minter.
struct WideDeal {
    escrow: EscrowFixture
    o1: Treasury
    o2: Treasury
    minter: address
    claims: map<address, address>
}

fun wideDeal(tag: string, seed: int, nfts: int, jettons: int): WideDeal {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val dummy = testing.treasury(tagged(tag, "-d"));
    val m = deployJettonMinter(o2, seed);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    var i = 0;
    while (i < nfts) {
        a.set(i as uint16, dummy.address);
        i += 1;
    }
    cfg.nfts1 = a;
    cfg.nfts1Count = nfts;
    var js: map<uint16, JettonCfg> = [];
    i = 0;
    while (i < jettons) {
        js.set(
            i as uint16,
            JettonCfg {
                minter: m,
                ownerSide: 2,
                amount: ton("1"),
            },
        );
        i += 1;
    }
    cfg.jettons = js;
    cfg.jettonsCount = jettons;
    val escrow = prepareEscrow(cfg);
    var c: map<address, address> = [];
    c.set(m, jwAddr(m, escrow.address));
    return WideDeal {
        escrow,
        o1,
        o2,
        minter: m,
        claims: c,
    };
}

// At the model's edge AcceptDeal writes every claim, starts discovery, and
// its real gas stays under the ceiling with the model's margin.
get fun `test AcceptDeal at the largest admitted registry fits`() {
    val j = largestClaimedRegistry();
    val d = wideDeal("sl1", 0x760000, 0, j);
    val res = sendAcceptDeal(d.o2.address, d.escrow, d.claims, ton("5"), true);
    expect(res).toHaveAllSuccessfulTxs();
    expect(res.at(0).gasUsed * 12 / 10 <= TX_GAS_LIMIT_CEILING).toEqual(true);
    expect(d.escrow.jettonWalletStatus(0)).toEqual((jwAddr(d.minter, d.escrow.address), true));
    expect(d.escrow.pendingWalletsLeft()).toEqual(0);
}

get fun `test one claim above the edge AcceptDeal only credits`() {
    val j = largestClaimedRegistry() + 1;
    val d = wideDeal("sl2", 0x760100, 0, j);
    expect(
        sendAcceptDeal(d.o2.address, d.escrow, d.claims, ton("5"), true),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.jettonWalletStatus(0)).toEqual((null, false));
    expect(d.escrow.phase()).toEqual(PHASE_SETUP);
    expect(d.escrow.pendingWalletsLeft()).toEqual(1);
    expect(d.escrow.gramState().serviceFee2).toEqual(SERVICE_FEE);
}

// AcceptDeal pays its own walks and claim writes out of the value it carries:
// at exactly the discovery price (which prices only deploy_fee's single scan)
// it must still succeed — credit, write the claims — and simply not start
// discovery, rather than abort its action phase on a fresh, empty balance.
get fun `test AcceptDeal at exactly the discovery price never aborts`() {
    val d = wideDeal("sl7", 0x760600, 0, 40);
    var s: map<uint16, uint16> = [];
    s.set(0, 40);
    val res = sendAcceptDeal(d.o2.address, d.escrow, d.claims, discoveryValue(40, s), true);
    expect(res).toHaveAllSuccessfulTxs();
    expect(d.escrow.jettonWalletStatus(0)).toEqual((jwAddr(d.minter, d.escrow.address), false));
    expect(d.escrow.pendingWalletsLeft()).toEqual(1);
    expect(d.escrow.gramState().serviceFee2 > 0).toEqual(true);
    // with its own gas on top, discovery starts and the minter confirms
    val d2 = wideDeal("sl8", 0x760700, 0, 40);
    expect(
        sendAcceptDeal(d2.o2.address, d2.escrow, d2.claims, acceptDiscoveryValue(40, 40, s), true),
    ).toHaveAllSuccessfulTxs();
    expect(d2.escrow.pendingWalletsLeft()).toEqual(0);
}

// The bound is by modelled gas, not by registry size: many NFTs and a few
// jettons still get their claims.
get fun `test a large NFT registry with few jettons keeps its claims`() {
    val d = wideDeal("sl3", 0x760200, 300, 2);
    expect(acceptModel(302, 2) <= TX_GAS_LIMIT_CEILING).toEqual(true);
    expect(
        sendAcceptDeal(d.o2.address, d.escrow, d.claims, ton("5"), true),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.jettonWalletStatus(300)).toEqual((jwAddr(d.minter, d.escrow.address), true));
}

// The worst answer (every slot of the minter provisionally received from a
// false claim, all undone) at the largest registry AcceptDeal still writes
// claims for. Larger registries get no claims, so no answer undoes more.
get fun `test the worst answer at the largest claimed registry fits its reserve`() {
    val j = largestClaimedRegistry();
    val d = wideDeal("sl4", 0x760300, 0, j);
    val fake = testing.treasury("sl4-fake");
    var c: map<address, address> = [];
    c.set(d.minter, fake.address);
    var s: map<uint16, uint16> = [];
    s.set(0, j as uint16);
    expect(
        sendAcceptDeal(d.o2.address, d.escrow, c, discoveryValue(j, s) - 1, true),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.pendingWalletsLeft()).toEqual(1);
    var i = 0;
    while (i < j) {
        expect(
            fakeNotification(
                fake.address,
                d.escrow.address,
                d.o2.address,
                ton("1"),
                i,
                ton("0.05"),
            ),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    expect(d.escrow.receivedCounts().1).toEqual(j);
    val res = d.escrow.sendText(d.o2.address, "deploy_fee", discoveryValue(j, s));
    expect(res).toHaveAllSuccessfulTxs();
    expect(maxGasOn(res, d.escrow.address) * 12 / 10 <= TX_GAS_LIMIT_CEILING).toEqual(true);
    expect(d.escrow.receivedCounts().1).toEqual(0);
    expect(d.escrow.pendingWalletsLeft()).toEqual(0);
}

// TAKE_MAX_SLOTS slots of one minter: AcceptDeal writes no claims at this size,
// so the answer only records the wallet, within the ceiling with its margin.
get fun `test the answer at TAKE_MAX_SLOTS fits its reserve`() {
    val d = wideDeal("sl6", 0x760500, 0, TAKE_MAX_SLOTS);
    var s: map<uint16, uint16> = [];
    s.set(0, TAKE_MAX_SLOTS as uint16);
    expect(
        sendAcceptDeal(
            d.o2.address,
            d.escrow,
            d.claims,
            discoveryValue(TAKE_MAX_SLOTS, s) - 1,
            true,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.jettonWalletStatus(0)).toEqual((null, false));
    val res = d.escrow.sendText(d.o2.address, "deploy_fee", discoveryValue(TAKE_MAX_SLOTS, s));
    expect(res).toHaveAllSuccessfulTxs();
    expect(maxGasOn(res, d.escrow.address) * 12 / 10 <= TX_GAS_LIMIT_CEILING).toEqual(true);
    expect(d.escrow.pendingWalletsLeft()).toEqual(0);
}

// ONE_SIGNATURE_MAX_ASSETS jetton slots of one minter, all deposited before
// the answer: the answer executes the deal in its own transaction.
get fun `test the answer executes a deal of ONE_SIGNATURE_MAX_ASSETS`() {
    val n = ONE_SIGNATURE_MAX_ASSETS;
    val d = wideDeal("sl5", 0x760400, 0, n);
    mintJettons(d.minter, d.o2, ton("1000"));
    var s: map<uint16, uint16> = [];
    s.set(0, n as uint16);
    val price = discoveryValue(n, s);
    expect(
        sendAcceptDeal(d.o2.address, d.escrow, d.claims, price - 1, true),
    ).toHaveAllSuccessfulTxs();
    expect(
        d.escrow.sendText(d.o2.address, "service_fee_owner2", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    var i = 0;
    while (i < n) {
        expect(
            sendJettonTransfer2(
                d.o2,
                d.minter,
                d.escrow.address,
                ton("1"),
                ton("0.1"),
                i,
            ),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    expect(
        d.escrow.sendText(d.o1.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    payShortfalls(d.escrow, d.o1, d.o2);
    d.escrow.sendText(d.o2.address, "deploy_fee", price);
    expect(d.escrow.phase()).toEqual(PHASE_DONE);
}
