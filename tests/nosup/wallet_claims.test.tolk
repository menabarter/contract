// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Jetton wallet discovery with claims: side 2 claims the escrow's wallet
// addresses in AcceptDeal, a deposit from a claimed address is recorded
// provisionally, and the minter's take_wallet_address confirms or undoes it.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "nosup_helpers"

// A minter answers addr_none for an owner it does not serve. The answer must
// not throw: the minter's slots stay without a wallet, nothing counts as
// resolved and the deal stays in SETUP until it is cancelled.
get fun `test an addr_none answer keeps the deal in SETUP`() {
    val d = setupWithSilentMinter("wc1", 0x710000, false);
    val res = sendTakeWallet(d.silent.address, d.escrow.address, null);
    expect(res).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_SETUP);
    expect(d.escrow.pendingWalletsLeft()).toEqual(1);
    expect(d.escrow.assetJettonWallet(1)).toEqual(null);
}

get fun `test claims are written to side 2 slots as unverified`() {
    val d = oneSigDeal("wc2", 0x730000);
    acceptWithoutDiscovery(d, d.trueClaims());
    expect(d.escrow.jettonWalletStatus(2)).toEqual((jwAddr(d.m1, d.escrow.address), false));
    expect(d.escrow.jettonWalletStatus(3)).toEqual((jwAddr(d.m2, d.escrow.address), false));
}

get fun `test a deposit before the answer is provisional and the answer confirms it`() {
    val d = oneSigDeal("wc3", 0x730100);
    acceptWithoutDiscovery(d, d.trueClaims());
    expect(
        sendJettonTransfer2(
            d.o2,
            d.m1,
            d.escrow.address,
            ton("10"),
            ton("0.2"),
            2,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.receivedCounts().1).toEqual(1);
    expect(d.escrow.phase()).toEqual(PHASE_SETUP);
    expect(d.escrow.sendText(d.o2.address, "deploy_fee", d.discovery())).toHaveAllSuccessfulTxs();
    expect(d.escrow.pendingWalletsLeft()).toEqual(0);
    expect(d.escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(d.escrow.receivedCounts().1).toEqual(1);
    expect(d.escrow.jettonWalletStatus(2)).toEqual((jwAddr(d.m1, d.escrow.address), true));
}

get fun `test answers before the deposits record them as usual`() {
    val d = oneSigDeal("wc4", 0x730200);
    expect(
        sendAcceptDeal(
            d.o2.address,
            d.escrow,
            d.trueClaims(),
            SERVICE_FEE + d.discovery(),
            true,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(
        sendJettonTransfer2(
            d.o2,
            d.m2,
            d.escrow.address,
            ton("20"),
            ton("0.2"),
            3,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.receivedCounts().1).toEqual(1);
}

// With every slot claimed, "resolved" cannot mean jettonWallet == null: the
// answers must still bring pendingWallets to zero.
get fun `test claims on every minter still reach ACTIVE`() {
    val d = oneSigDeal("wc5", 0x730300);
    acceptWithoutDiscovery(d, d.trueClaims());
    expect(d.escrow.sendText(d.o2.address, "deploy_fee", d.discovery())).toHaveAllSuccessfulTxs();
    expect(d.escrow.pendingWalletsLeft()).toEqual(0);
    expect(d.escrow.phase()).toEqual(PHASE_ACTIVE);
}

// owner2 claims its own contract and deposits from it: recorded
// provisionally, undone by the minter's answer, the deal never executes on it.
get fun `test a false claim's deposit is undone by the answer`() {
    val d = oneSigDeal("wc6", 0x730400);
    val fakeW = testing.treasury("wc6-fake");
    var c = d.trueClaims();
    c.set(d.m1, fakeW.address);
    acceptWithoutDiscovery(d, c);
    expect(
        fakeNotification(
            fakeW.address,
            d.escrow.address,
            d.o2.address,
            ton("10"),
            2,
            ton("0.2"),
        ),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.receivedCounts().1).toEqual(1);
    expect(d.escrow.sendText(d.o2.address, "deploy_fee", d.discovery())).toHaveAllSuccessfulTxs();
    expect(d.escrow.receivedCounts().1).toEqual(0);
    expect(d.escrow.assetStatus(2).0).toEqual(false);
    expect(d.escrow.jettonWalletStatus(2)).toEqual((jwAddr(d.m1, d.escrow.address), true));
    expect(d.escrow.phase()).toEqual(PHASE_ACTIVE);
    // the real deposit now lands
    expect(
        sendJettonTransfer2(
            d.o2,
            d.m1,
            d.escrow.address,
            ton("10"),
            ton("0.2"),
            2,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.receivedCounts().1).toEqual(1);
}

get fun `test a stranger's notification matches no claim`() {
    val d = oneSigDeal("wc7", 0x730500);
    acceptWithoutDiscovery(d, d.trueClaims());
    val mallory = testing.treasury("wc7-m");
    expect(
        fakeNotification(
            mallory.address,
            d.escrow.address,
            d.o2.address,
            ton("10"),
            2,
            ton("0.2"),
        ),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.receivedCounts().1).toEqual(0);
    expect(
        sendJettonTransfer2(
            d.o2,
            d.m1,
            d.escrow.address,
            ton("10"),
            ton("0.2"),
            2,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.receivedCounts().1).toEqual(1);
}

// Side 1's slots take their wallet only from the minter.
get fun `test a claim for a side 1 minter does nothing`() {
    val o1 = testing.treasury("wc8-o1");
    val o2 = testing.treasury("wc8-o2");
    val fw = testing.treasury("wc8-fw");
    val m = deployJettonMinter(o1, 0x730600);
    var cfg = makeBasicConfig(o1, o2, fw);
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter: m,
            ownerSide: 1,
            amount: ton("5"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 1;
    val escrow = prepareEscrow(cfg);
    var c: map<address, address> = [];
    c.set(m, jwAddr(m, escrow.address));
    var s: map<uint16, uint16> = [];
    s.set(0, 1);
    expect(
        sendAcceptDeal(o2.address, escrow, c, discoveryValue(1, s) - 1, true),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.jettonWalletStatus(0)).toEqual((null, false));
}

get fun `test claims for an unknown minter change nothing`() {
    val d = oneSigDeal("wc9", 0x730700);
    var c: map<address, address> = [];
    c.set(testing.treasury("wc9-x").address, testing.treasury("wc9-w").address);
    acceptWithoutDiscovery(d, c);
    expect(d.escrow.jettonWalletStatus(2)).toEqual((null, false));
    expect(d.escrow.jettonWalletStatus(3)).toEqual((null, false));
}

get fun `test a second AcceptDeal keeps the first claims`() {
    val d = oneSigDeal("wc10", 0x730800);
    acceptWithoutDiscovery(d, d.trueClaims());
    var other: map<address, address> = [];
    other.set(d.m1, testing.treasury("wc10-w").address);
    expect(
        sendAcceptDeal(d.o2.address, d.escrow, other, d.discovery(), false),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.jettonWalletStatus(2)).toEqual((jwAddr(d.m1, d.escrow.address), true));
    expect(d.escrow.phase()).toEqual(PHASE_ACTIVE);
}

get fun `test an underpaid deposit to a claimed slot is returned`() {
    val d = oneSigDeal("wc11", 0x730900);
    acceptWithoutDiscovery(d, d.trueClaims());
    expect(
        sendJettonTransfer2(
            d.o2,
            d.m1,
            d.escrow.address,
            ton("4"),
            ton("0.2"),
            2,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.receivedCounts().1).toEqual(0);
    expect(readJettonBalance(d.m1, d.o2.address)).toEqual(ton("100"));
}

get fun `test a repeated answer does not count twice`() {
    val d = oneSigDeal("wc12", 0x730a00);
    acceptWithoutDiscovery(d, d.trueClaims());
    expect(d.escrow.sendText(d.o2.address, "deploy_fee", d.discovery())).toHaveAllSuccessfulTxs();
    expect(d.escrow.pendingWalletsLeft()).toEqual(0);
    expect(
        sendTakeWallet(d.m1, d.escrow.address, jwAddr(d.m1, d.escrow.address)),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.pendingWalletsLeft()).toEqual(0);
}

// addr_none after a provisional deposit: the deposit is undone and the claim
// erased, so the claimed address cannot record anything afterwards.
get fun `test addr_none undoes a provisional deposit and erases the claim`() {
    val d = oneSigDeal("wc13", 0x730b00);
    val fakeW = testing.treasury("wc13-fake");
    var c = d.trueClaims();
    c.set(d.m1, fakeW.address);
    acceptWithoutDiscovery(d, c);
    expect(
        fakeNotification(
            fakeW.address,
            d.escrow.address,
            d.o2.address,
            ton("10"),
            2,
            ton("0.2"),
        ),
    ).toHaveAllSuccessfulTxs();
    expect(sendTakeWallet(d.m1, d.escrow.address, null)).toHaveAllSuccessfulTxs();
    expect(d.escrow.receivedCounts().1).toEqual(0);
    expect(d.escrow.jettonWalletStatus(2)).toEqual((null, false));
    expect(d.escrow.phase()).toEqual(PHASE_SETUP);
    expect(d.escrow.pendingWalletsLeft()).toEqual(2);
    expect(
        fakeNotification(
            fakeW.address,
            d.escrow.address,
            d.o2.address,
            ton("10"),
            2,
            ton("0.2"),
        ),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.receivedCounts().1).toEqual(0);
}
