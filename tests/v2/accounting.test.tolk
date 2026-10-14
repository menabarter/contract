// GENERATED from tests/nosup/accounting.test.tolk by ts-tests/gen-v2-tests.ts — edit the source, then run npm run gen:v2.
// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Settlement: each side pays for moving its own assets; the rest of what the
// deal spends is shared equally; the excess of anything a side paid comes back
// to that side.
import "@stdlib/gas-payments"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/messages"
import "@wrappers/SwapEscrowV2.gen"
import "@contracts/shared/accounting"
import "@contracts/shared/types"
import "@contracts/v2/accounting"
import "@contracts/v2/storage"
import "v2_helpers"

// ── the arithmetic ──

get fun `test split gives each side its own net when nothing is shared`() {
    expect(splitRefunds(100, 60, 40)).toEqual((60, 40));
}

get fun `test split charges shared costs half to each side`() {
    // 20 of shared costs left R = 80: each side loses 10
    expect(splitRefunds(80, 60, 40)).toEqual((50, 30));
}

get fun `test split never goes negative and always sums to R`() {
    expect(splitRefunds(10, 100, -50)).toEqual((10, 0));
    expect(splitRefunds(10, -50, 100)).toEqual((0, 10));
    expect(splitRefunds(-5, 1, 1)).toEqual((0, 0));
    val (a, b) = splitRefunds(7, 3, 0);
    expect(a + b).toEqual(7);
}

// ── settlement on a real deal ──

struct LegDeal {
    escrow: EscrowFixture
    o1: Treasury
    o2: Treasury
    fw: Treasury
    completing: SendResultList // the trace of side 2's completing NFT deposit
}

// 1x1 NFT deal with TON legs; side 1 deposits everything first; side 2's NFT
// completes the deal.
fun legDeal(tag: string, seed: int, gram1: coins, gram2: coins, fee1: coins): LegDeal {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val n1 = deployNft(o1, seed);
    val n2 = deployNft(o2, seed + 1);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, n1);
    var b: map<uint16, address> = [];
    b.set(0, n2);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = 1;
    cfg.gram1Amount = gram1;
    cfg.gram2Amount = gram2;
    val escrow = deployEscrow(o1, cfg);
    if (gram1 > 0) {
        expect(escrow.sendText(o1.address, "deposit_ton1", gram1)).toHaveAllSuccessfulTxs();
    }
    expect(escrow.sendText(o1.address, "service_fee_owner1", fee1)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, n1, escrow.address, ton("0.5"), 0)).toHaveAllSuccessfulTxs();
    if (gram2 > 0) {
        expect(escrow.sendText(o2.address, "deposit_ton2", gram2)).toHaveAllSuccessfulTxs();
    }
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    val completing = sendNftToEscrow(o2, n2, escrow.address, ton("0.5"), 1);
    expect(escrow.phase()).toEqual(PHASE_DONE);
    return LegDeal { escrow, o1, o2, fw, completing };
}

// Side 1 receives, during side 2's completing deposit, exactly side 2's leg,
// its own refund and its NFT's transfer excess — and sends nothing. The excess
// is the same in every deal, so comparing two deals isolates the refund.
fun side1Refund(tag: string, seed: int, gram2: coins): coins {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val n1 = deployNft(o1, seed);
    val n2 = deployNft(o2, seed + 1);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, n1);
    var b: map<uint16, address> = [];
    b.set(0, n2);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = 1;
    cfg.gram2Amount = gram2;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, n1, escrow.address, ton("0.5"), 0)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "deposit_ton2", gram2)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    val before = testing.getAccountBalance(o1.address);
    sendNftToEscrow(o2, n2, escrow.address, ton("0.5"), 1);
    expect(escrow.phase()).toEqual(PHASE_DONE);
    return testing.getAccountBalance(o1.address) - before - gram2;
}

// A refund weighted by contributions would move side 1's refund with side 2's
// TON leg.
get fun `test side 1 refund does not depend on side 2 TON leg`() {
    val small = side1Refund("acc-l1", 75001, ton("1"));
    val big = side1Refund("acc-l5", 75011, ton("5"));
    val diff = small > big ? small - big : big - small;
    expect(diff).toBeLess(ton("0.001"));
}

// An overpaid service fee: the fee wallet gets exactly 2 x SERVICE_FEE and the
// excess comes back to its payer.
get fun `test overpaid fee comes back on execute`() {
    val d = legDeal("acc-fee", 75021, 0, 0, ton("1"));
    // mode 0 takes the forwarding fee out of the message value, so the fee
    // arrives slightly below 2 x SERVICE_FEE
    expect(d.completing).toHaveTx({
        from: d.escrow.address,
        to: d.fw.address,
        value: fun(v: coins): bool {
            return v > SERVICE_FEE * 2 - ton("0.01") && v <= SERVICE_FEE * 2;
        },
    });
    expect(d.completing).toHaveTx({
        from: d.escrow.address,
        to: d.o1.address,
        value: fun(v: coins): bool {
            return v >= ton("0.9");
        },
    });
}

// On a fast execute the refunds carry everything except this transaction's
// gas reserve, DUST and the storage floor, so the fee wallet gets 2 x
// SERVICE_FEE plus a sweep of at most the execution gas reserve plus DUST
// (the unused part of the reserve, plus DUST). Anything else reaching the fee
// wallet is money taken from the refunds. The reserve is the one the contract
// prices for this deal: two assets and five other sends (fee wallet, two
// refunds, two TON legs), no batch chain on the fast path.
get fun `test fast execute sends the fee wallet no more than the fee, the gas reserve and DUST`() {
    val o1 = testing.treasury("acc-sw-o1");
    val o2 = testing.treasury("acc-sw-o2");
    val fw = testing.treasury("acc-sw-fw");
    val n1 = deployNft(o1, 75031);
    val n2 = deployNft(o2, 75032);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, n1);
    var b: map<uint16, address> = [];
    b.set(0, n2);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = 1;
    cfg.gram1Amount = ton("1");
    cfg.gram2Amount = ton("1");
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "deposit_ton1", ton("1"))).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, n1, escrow.address, ton("0.5"), 0)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "deposit_ton2", ton("1"))).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    val before = testing.getAccountBalance(fw.address);
    sendNftToEscrow(o2, n2, escrow.address, ton("0.5"), 1);
    expect(escrow.phase()).toEqual(PHASE_DONE);
    val received = testing.getAccountBalance(fw.address) - before;
    val reserve = calculateGasFee(
        BASECHAIN,
        EXEC_GAS_UNITS_BASE + EXEC_GAS_UNITS_PER_SEND * (2 + 5),
    );
    expect(received > SERVICE_FEE * 2 - ton("0.01")).toEqual(true);
    expect(received <= SERVICE_FEE * 2 + reserve + DUST).toEqual(true);
}

// A side's refund does not depend on how many assets the other side moves,
// apart from its half of the shared costs. Side 1 has one NFT; side 2 has k
// NFTs, each deposited with 0.05. Nine more assets on side 2 add nine sends
// to the shared gas reserve and nine deposits' gas (deposit gas is credited
// gross, so it ends up shared); side 1 carries half of that, well under
// 0.01 TON.
fun side1RefundAgainst(tag: string, seed: int, k: int): coins {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val a1 = deployNft(o1, seed);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, a1);
    var b: map<uint16, address> = [];
    var i = 0;
    while (i < k) {
        b.set(i as uint16, deployNft(o2, seed + 1 + i));
        i += 1;
    }
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = k;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, a1, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    i = 0;
    while (i < k - 1) {
        expect(
            sendNftToEscrow(o2, b.mustGet(i as uint16), escrow.address, ton("0.05"), 1 + i),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    val before = testing.getAccountBalance(o1.address);
    sendNftToEscrow(o2, b.mustGet((k - 1) as uint16), escrow.address, ton("0.05"), k);
    expect(escrow.phase()).toEqual(PHASE_DONE);
    return testing.getAccountBalance(o1.address) - before;
}

get fun `test side 1 refund does not depend on the number of side 2 assets`() {
    val one = side1RefundAgainst("acc-k1", 75101, 1);
    val ten = side1RefundAgainst("acc-k10", 75201, 10);
    val diff = one - ten;
    expect(diff >= 0).toEqual(true);
    expect(diff).toBeLess(ton("0.01"));
}

// Value that reaches the deal before it settles and belongs to neither side
// (here an Excesses from a stranger) is split equally, whatever the sides
// contributed. Side 2 contributes three times side 1's NFT forward, so a
// split by contribution would give side 1 a quarter.
fun side1RefundWithInflow(tag: string, seed: int, inflow: coins): coins {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val n1 = deployNft(o1, seed);
    val n2 = deployNft(o2, seed + 1);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, n1);
    var b: map<uint16, address> = [];
    b.set(0, n2);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, n1, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    if (inflow > 0) {
        val stranger = testing.treasury(tagged(tag, "-x"));
        val m = createMessage({
            bounce: BounceMode.NoBounce,
            value: inflow,
            dest: escrow.address,
            body: Excesses { queryId: 0 },
        });
        expect(net.send(stranger.address, m)).toHaveAllSuccessfulTxs();
    }
    val before = testing.getAccountBalance(o1.address);
    sendNftToEscrow(o2, n2, escrow.address, ton("0.6"), 1);
    expect(escrow.phase()).toEqual(PHASE_DONE);
    return testing.getAccountBalance(o1.address) - before;
}

get fun `test an unattributed inflow before execution is split equally`() {
    val plain = side1RefundWithInflow("acc-in0", 75301, 0);
    val more = side1RefundWithInflow("acc-in1", 75401, ton("1"));
    expect(more - plain).toBeInRange(ton("0.499"), ton("0.501"));
}

// kick during execution pays for finishing the chain for both sides: what the
// chain does not spend of it is part of R and is split equally. Two identical
// stalled executions, kicked with 1 and with 2 TON: owner 2 (who did not
// kick) receives exactly half of the difference.
fun o2ReceiptAfterKick(tag: string, seed: int, mode: int, kick: coins): coins {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, deployNft(o1, seed));
    a.set(1, deployNft(o1, seed + 1));
    var b: map<uint16, address> = [];
    b.set(0, deployNft(o2, seed + 2));
    b.set(1, deployNft(o2, seed + 3));
    cfg.nfts1 = a;
    cfg.nfts1Count = 2;
    cfg.nfts2 = b;
    cfg.nfts2Count = 2;
    val escrow = deployEscrowMidDistribution(o1, cfg, 2, mode);
    val before = testing.getAccountBalance(o2.address);
    expect(escrow.sendText(o1.address, "kick", kick)).toHaveAllSuccessfulTxs();
    expect(escrow.distributionProgress().0).toEqual(DIST_IDLE);
    return testing.getAccountBalance(o2.address) - before;
}

get fun `test kick during execution is split equally`() {
    val one = o2ReceiptAfterKick("acc-kx1", 75501, DIST_EXECUTE, ton("1"));
    val two = o2ReceiptAfterKick("acc-kx2", 75601, DIST_EXECUTE, ton("2"));
    expect(two - one).toBeInRange(ton("0.499"), ton("0.501"));
}

// A side that cannot cover its own transfers is not carried by the other,
// even when the other side's overpayment would cover the balance check.
fun underfundedSide2(tag: string, seed: int): EscrowFixture {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val n1 = deployNft(o1, seed);
    val n2 = deployNft(o2, seed + 1);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, n1);
    var b: map<uint16, address> = [];
    b.set(0, n2);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, n1, escrow.address, ton("2"), 0)).toHaveAllSuccessfulTxs();
    // side 2's forward cannot pay for its own NFT's transfer (0.03)
    sendNftToEscrow(o2, n2, escrow.address, ton("0.005"), 1);
    return escrow;
}

get fun `test an underfunded side does not execute`() {
    val escrow = underfundedSide2("acc-uf0", 75021);
    expect(escrow.receivedCounts()).toEqual((1, 1));
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
}

get fun `test an underfunded side blocks execution until it pays its share`() {
    val escrow = underfundedSide2("acc-uf", 75031);
    // the same name the deal was built with: a literal "acc-uf-o2" names a
    // different treasury than one assembled at runtime by `tagged`
    val o2 = testing.treasury(tagged("acc-uf", "-o2"));
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    val (s1, s2) = escrow.executionShortfall();
    expect(s1).toEqual(0);
    expect(s2 > 0).toEqual(true);
    // the extra 0.05 is gas headroom for the transaction that executes; it is
    // an overpayment and comes back in side 2's refund
    escrow.sendText(o2.address, "deposit_ton2", s2 + ton("0.05"));
    expect(escrow.phase()).toEqual(PHASE_DONE);
}

// A side with only a TON leg pays its half of the shared costs.
get fun `test a TON-only side pays its share and the deal executes`() {
    val o1 = testing.treasury("acc-ton-o1");
    val o2 = testing.treasury("acc-ton-o2");
    val fw = testing.treasury("acc-ton-fw");
    val n1 = deployNft(o1, 75041);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, n1);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.gram2Amount = ton("1");
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, n1, escrow.address, ton("0.05"), 0)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    escrow.sendText(o2.address, "deposit_ton2", ton("1"));
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    val (_s1, s2) = escrow.executionShortfall();
    expect(s2 > 0).toEqual(true);
    // the extra 0.05 is gas headroom for the transaction that executes; it is
    // an overpayment and comes back in side 2's refund
    escrow.sendText(o2.address, "deposit_ton2", s2 + ton("0.05"));
    expect(escrow.phase()).toEqual(PHASE_DONE);
}

// A mixed deal with typical funding: 0.05 per NFT, 0.2 forward per jetton,
// fees of exactly SERVICE_FEE.
get fun `test a mixed deal with typical dapp funding executes`() {
    val o1 = testing.treasury("acc-mix-o1");
    val o2 = testing.treasury("acc-mix-o2");
    val fw = testing.treasury("acc-mix-fw");
    val minter = deployJettonMinter(o1, 75051);
    mintJettons(minter, o1, ton("100"));
    val a1 = deployNft(o1, 75052);
    val a2 = deployNft(o1, 75053);
    val b1 = deployNft(o2, 75054);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, a1);
    a.set(1, a2);
    var b: map<uint16, address> = [];
    b.set(0, b1);
    cfg.nfts1 = a;
    cfg.nfts1Count = 2;
    cfg.nfts2 = b;
    cfg.nfts2Count = 1;
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter,
            ownerSide: 1,
            amount: ton("10"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, a1, escrow.address, ton("0.05"), 0)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, a2, escrow.address, ton("0.05"), 1)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o2, b1, escrow.address, ton("0.05"), 2)).toHaveAllSuccessfulTxs();
    sendJettonTransfer2(
        o1,
        minter,
        escrow.address,
        ton("10"),
        ton("0.2"),
        3,
    );
    expect(escrow.phase()).toEqual(PHASE_DONE);
}

// The completing jetton deposit overpays: its refund is queued before execution
// and the settlement must leave room for it (otherwise action code 37 rolls
// the deposit back).
get fun `test a completing jetton deposit with overpayment executes`() {
    val f = jdSetup("acc-ovp", 75061);
    expect(
        f.escrow.sendText(f.o1.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(
        f.escrow.sendText(f.o2.address, "service_fee_owner2", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendJettonTransfer2(
            f.o1,
            f.minter,
            f.escrow.address,
            ton("100"),
            ton("0.2"),
            0,
        ),
    ).toHaveAllSuccessfulTxs();
    val res = sendJettonTransfer2(
        f.o2,
        f.minter,
        f.escrow.address,
        ton("60"),
        ton("0.2"),
        1,
    );
    expect(res).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_DONE);
}
