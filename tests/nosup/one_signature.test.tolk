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
import "@contracts/shared/types"
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

// The heaviest deal AcceptDeal still claims on the single-transaction path:
// 9 NFTs on side 1 and 91 jetton slots of one minter on side 2 (100 assets,
// the ACCEPT_* model at 995,000 of 1,000,000), every slot deposited
// provisionally. The last answer walks and rewrites all 91 slots, then
// executes all 100 transfers in the same transaction (measured 956,603 gas):
// within the claim model the answer always has room to execute. The commit
// before execution stays as a safeguard for a deal that would not.
get fun `test the heaviest claimed deal executes in the answer`() {
    val o1 = testing.treasury("os2-o1");
    val o2 = testing.treasury("os2-o2");
    val fw = testing.treasury("os2-fw");
    val nfts = 9;
    val j = 91;
    val n = nfts + j;
    expect(acceptModel(n, j) <= TX_GAS_LIMIT_CEILING).toEqual(true);
    val m = deployJettonMinter(o2, 0x740100);
    mintJettons(m, o2, ton("1000"));
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    var i = 0;
    while (i < nfts) {
        a.set(i as uint16, deployNft(o1, 0x740110 + i));
        i += 1;
    }
    cfg.nfts1 = a;
    cfg.nfts1Count = nfts;
    var js: map<uint16, JettonCfg> = [];
    i = 0;
    while (i < j) {
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
    cfg.jettonsCount = j;
    val escrow = prepareEscrow(cfg);
    var c: map<address, address> = [];
    c.set(m, jwAddr(m, escrow.address));
    var s: map<uint16, uint16> = [];
    s.set(0, j as uint16);
    val price = discoveryValue(n, s);
    expect(sendAcceptDeal(o2.address, escrow, c, price - 1, true)).toHaveAllSuccessfulTxs();
    expect(escrow.pendingWalletsLeft()).toEqual(1);
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    i = 0;
    while (i < nfts) {
        expect(
            sendNftToEscrow(o1, a.mustGet(i as uint16), escrow.address, ton("0.05"), i),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    i = 0;
    while (i < j) {
        expect(
            sendJettonTransfer2(
                o2,
                m,
                escrow.address,
                ton("1"),
                ton("0.1"),
                nfts + i,
            ),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    expect(escrow.receivedCounts()).toEqual((nfts, j));
    payShortfalls(escrow, o1, o2);
    expect(escrow.phase()).toEqual(PHASE_SETUP);
    val res = escrow.sendText(o2.address, "deploy_fee", price);
    expect(escrow.pendingWalletsLeft()).toEqual(0);
    expect(escrow.phase()).toEqual(PHASE_DONE);
    expect(maxGasOn(res, escrow.address) < TX_GAS_LIMIT_CEILING).toEqual(true);
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
