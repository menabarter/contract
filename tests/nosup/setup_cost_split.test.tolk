// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// What the deal spends on deployment and wallet discovery is shared equally,
// whoever paid for it up front. The settlement formula shares it exactly as
// long as neither side's share is cut at zero; executionShortfall names
// top-ups that keep both shares there.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/accounting"
import "@contracts/nosup/storage"
import "nosup_helpers"

// ── the arithmetic ──

// A top-up raises both R and the payer's net, so the payer's share grows by
// the full top-up and the other share does not move.
get fun `test top-ups bring a negative share to zero and leave the other`() {
    val (a1, a2) = noClampTopUps(100, 0, 300);
    expect((a1, a2)).toEqual((100, 0));
    val (r1, r2) = splitRefunds(100 + a1, 0 + a1, 300);
    expect(r1).toEqual(0);
    expect(r2).toEqual(200);
    expect(noClampTopUps(100, 60, 40)).toEqual((0, 0));
    val (b1, b2) = noClampTopUps(10, 301, 0);
    expect((b1, b2)).toEqual((0, 146));
    // odd differences round the top-up up
    expect(noClampTopUps(0, 0, 3)).toEqual((2, 0));
}

// ── on a real deal ──

// Side 1 holds jettons of three minters, side 2 one NFT, everyone pays
// minimal forwards: owner2's AcceptDeal pays for asking three minters, more
// than side 2's own share, so side 1's formula share would be negative.
// owner1 pays what executionShortfall names plus 0.0035 TON: above
// refundMinimum (so its refund is sent, not swept, and can be measured) and
// below the part of side 1's half that a figure without the no-cut condition
// leaves to owner2 (about 0.0043 TON on this deal).
//
// Outlay = paid - refund - service fee - own transfers. With neither share
// cut, the settlement formula gives both sides the same outlay: half of what
// the deal spent on deployment, discovery, gas and storage.
get fun `test both sides bear the discovery cost equally`() {
    val o1 = testing.treasury("sc1-o1");
    val o2 = testing.treasury("sc1-o2");
    val fw = testing.treasury("sc1-fw");
    val ma = deployJettonMinter(o1, 0x770000);
    val mb = deployJettonMinter(o1, 0x770001);
    val mc = deployJettonMinter(o1, 0x770002);
    mintJettons(ma, o1, ton("10"));
    mintJettons(mb, o1, ton("10"));
    mintJettons(mc, o1, ton("10"));
    val nft2 = deployNft(o2, 0x770003);
    var cfg = makeBasicConfig(o1, o2, fw);
    var b: map<uint16, address> = [];
    b.set(0, nft2);
    cfg.nfts2 = b;
    cfg.nfts2Count = 1;
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter: ma,
            ownerSide: 1,
            amount: ton("1"),
        },
    );
    js.set(
        1,
        JettonCfg {
            minter: mb,
            ownerSide: 1,
            amount: ton("1"),
        },
    );
    js.set(
        2,
        JettonCfg {
            minter: mc,
            ownerSide: 1,
            amount: ton("1"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 3;
    val escrow = prepareEscrow(cfg);
    var s: map<uint16, uint16> = [];
    s.set(0, 1);
    s.set(1, 1);
    s.set(2, 1);
    expect(
        sendAcceptDeal(o2.address, escrow, [], SERVICE_FEE + discoveryValue(4, s), true),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(sendNftToEscrow(o2, nft2, escrow.address, ton("0.05"), 0)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(
        sendJettonTransfer2(
            o1,
            ma,
            escrow.address,
            ton("1"),
            ton("0.01"),
            1,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendJettonTransfer2(
            o1,
            mb,
            escrow.address,
            ton("1"),
            ton("0.01"),
            2,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendJettonTransfer2(
            o1,
            mc,
            escrow.address,
            ton("1"),
            ton("0.01"),
            3,
        ),
    ).toHaveAllSuccessfulTxs();
    val (s1, s2) = escrow.executionShortfall();
    expect(s1 > 0).toEqual(true);
    expect(s2).toEqual(0);
    val g = escrow.gramState();
    val pay1 = s1 + ton("0.0035");
    val res = escrow.sendText(o1.address, "deposit_ton1", pay1);
    expect(escrow.phase()).toEqual(PHASE_DONE);
    val paid1 = g.gram1Received + g.serviceFee1 + g.gram1DepositReserve + pay1;
    val paid2 = g.gram2Received + g.serviceFee2 + g.gram2DepositReserve;
    val refund1 = valueSentTo(res, escrow.address, o1.address);
    val refund2 = valueSentTo(res, escrow.address, o2.address);
    expect(refund1 > 0).toEqual(true);
    val outlay1 = paid1 - refund1 - SERVICE_FEE - JETTON_TRANSFER_VALUE * 3;
    val outlay2 = paid2 - refund2 - SERVICE_FEE - NFT_TRANSFER_VALUE;
    expect(outlay1 - outlay2).toBeInRange(-1, 1);
}
