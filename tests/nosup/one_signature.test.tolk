// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// In the one-signature flow the last minter answer is what completes the deal:
// every deposit may already be in when it arrives. The answer must execute
// the deal, and it must never be lost because execution ran out of gas.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "nosup_helpers"

// The one-signature order: AcceptDeal (no discovery yet), side 2's deposits,
// side 1's NFT and fee, then the answers. The last answer completes the deal.
get fun `test the last minter answer executes the deal`() {
    val d = oneSigDeal("os1", 0x740000);
    acceptWithoutDiscovery(d, d.trueClaims());
    expect(
        sendNftToEscrow(d.o2, d.nft2, d.escrow.address, ton("0.2"), 1),
    ).toHaveAllSuccessfulTxs();
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
    expect(
        d.escrow.sendText(d.o1.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendNftToEscrow(d.o1, d.nft1, d.escrow.address, ton("0.3"), 0),
    ).toHaveAllSuccessfulTxs();
    payShortfalls(d.escrow, d.o1, d.o2);
    expect(d.escrow.phase()).toEqual(PHASE_SETUP);
    d.escrow.sendText(d.o2.address, "deploy_fee", d.discovery());
    expect(d.escrow.phase()).toEqual(PHASE_DONE);
}

// One minter owning the largest registry AcceptDeal still claims, every slot
// deposited provisionally: the answer walks and rewrites every slot, then
// execution sends every jetton. If the transaction runs out of gas, the
// answer and ACTIVE must survive and execute_swap settles the deal; either
// way the deal ends DONE.
get fun `test an answer at the claim limit always settles the deal`() {
    val n = largestClaimedRegistry();
    val o1 = testing.treasury("os2-o1");
    val o2 = testing.treasury("os2-o2");
    val fw = testing.treasury("os2-fw");
    val m = deployJettonMinter(o2, 0x740100);
    mintJettons(m, o2, ton("1000"));
    var cfg = makeBasicConfig(o1, o2, fw);
    var js: map<uint16, JettonCfg> = [];
    var i = 0;
    while (i < n) {
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
    cfg.jettonsCount = n;
    val escrow = prepareEscrow(cfg);
    var c: map<address, address> = [];
    c.set(m, jwAddr(m, escrow.address));
    var s: map<uint16, uint16> = [];
    s.set(0, n as uint16);
    val price = discoveryValue(n, s);
    expect(sendAcceptDeal(o2.address, escrow, c, price - 1, true)).toHaveAllSuccessfulTxs();
    expect(escrow.pendingWalletsLeft()).toEqual(1);
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    i = 0;
    while (i < 100) {
        expect(
            sendJettonTransfer2(
                o2,
                m,
                escrow.address,
                ton("1"),
                ton("0.1"),
                i,
            ),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    payShortfalls(escrow, o1, o2);
    escrow.sendText(o2.address, "deploy_fee", price);
    expect(escrow.pendingWalletsLeft()).toEqual(0);
    if (escrow.phase() == PHASE_ACTIVE) {
        expect(
            escrow.sendText(o1.address, "execute_swap", ton("0.05")),
        ).toHaveAllSuccessfulTxs();
    }
    expect(escrow.phase()).toEqual(PHASE_DONE);
}

// Over 100 assets the batch path starts from the answer; its chain limits
// itself by consumed gas and finishes.
get fun `test the last answer starts the batch chain of a large deal`() {
    val o1 = testing.treasury("os3-o1");
    val o2 = testing.treasury("os3-o2");
    val fw = testing.treasury("os3-fw");
    val m = deployJettonMinter(o2, 0x740200);
    mintJettons(m, o2, ton("10"));
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    var i = 0;
    while (i < 100) {
        a.set(i as uint16, deployNft(o1, 0x740300 + i));
        i += 1;
    }
    cfg.nfts1 = a;
    cfg.nfts1Count = 100;
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter: m,
            ownerSide: 2,
            amount: ton("1"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 1;
    val escrow = prepareEscrow(cfg);
    var c: map<address, address> = [];
    c.set(m, jwAddr(m, escrow.address));
    var s: map<uint16, uint16> = [];
    s.set(0, 1);
    val price = discoveryValue(101, s);
    expect(sendAcceptDeal(o2.address, escrow, c, price - 1, true)).toHaveAllSuccessfulTxs();
    expect(escrow.pendingWalletsLeft()).toEqual(1);
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(
        sendJettonTransfer2(
            o2,
            m,
            escrow.address,
            ton("1"),
            ton("0.2"),
            100,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    i = 0;
    while (i < 100) {
        expect(
            sendNftToEscrow(o1, a.mustGet(i as uint16), escrow.address, ton("0.05"), i),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    payShortfalls(escrow, o1, o2);
    escrow.sendText(o2.address, "deploy_fee", price);
    expect(escrow.phase()).toEqual(PHASE_DONE);
}
