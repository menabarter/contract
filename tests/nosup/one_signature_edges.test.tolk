// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Edges of the one-signature flow: cancel with provisional deposits, one
// minter on both sides, transfers that arrive after a cancel or before the
// escrow exists.
import "@stdlib/gas-payments"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "nosup_helpers"

// Cancel in SETUP with a provisional deposit under a true claim: the jettons
// go back to owner2 through the claimed (real) wallet; a late answer is
// ignored.
get fun `test cancel in SETUP returns a provisional deposit`() {
    val d = oneSigDeal("ed1", 0x780000);
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
    val (_req, attach) = d.escrow.cancelCost();
    expect(d.escrow.sendText(d.o2.address, "cancel_swap", attach)).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(readJettonBalance(d.m1, d.o2.address)).toEqual(ton("100"));
    expect(
        sendTakeWallet(d.m1, d.escrow.address, jwAddr(d.m1, d.escrow.address)),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
}

fun cancelSide1Refund(tag: string, seed: int, fakeDeposit: bool): coins {
    val d = oneSigDeal(tag, seed);
    val fake = testing.treasury(tagged(tag, "-fake"));
    var c = d.trueClaims();
    c.set(d.m1, fake.address);
    acceptWithoutDiscovery(d, c);
    expect(
        d.escrow.sendText(d.o1.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    if (fakeDeposit) {
        expect(
            fakeNotification(
                fake.address,
                d.escrow.address,
                d.o2.address,
                ton("10"),
                2,
                ton("0.2"),
            ),
        ).toHaveAllSuccessfulTxs();
    } else {
        // the same TON, attached to a plain deposit, so both deals hold equal value
        expect(
            d.escrow.sendText(d.o2.address, "deposit_ton2", ton("0.2")),
        ).toHaveAllSuccessfulTxs();
    }
    val (_req, attach) = d.escrow.cancelCost();
    val res = d.escrow.sendText(d.o2.address, "cancel_swap", attach);
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
    return valueSentTo(res, d.escrow.address, d.o1.address);
}

// Under a false claim the return goes to the false address; its transfer
// value is side 2's own cost, not a shared one. Side 1's refund moves only by
// half of the extra send's gas (shared), never by half of the transfer value.
get fun `test a false claim's return is side 2's own cost`() {
    val side1RefundWith = cancelSide1Refund("ed2", 0x780100, true);
    val side1RefundWithout = cancelSide1Refund("ed3", 0x780200, false);
    expect(side1RefundWithout - side1RefundWith >= 0).toEqual(true);
    expect(
        side1RefundWithout - side1RefundWith <= calculateGasFee(BASECHAIN, EXEC_GAS_UNITS_PER_SEND),
    ).toEqual(true);
}

// One minter on both sides: the claim fills side 2's slot only; side 1's slot
// takes the address from the answer; both end with the same confirmed wallet.
get fun `test one minter on both sides ends with one confirmed wallet`() {
    val o1 = testing.treasury("ed4-o1");
    val o2 = testing.treasury("ed4-o2");
    val fw = testing.treasury("ed4-fw");
    val m = deployJettonMinter(o1, 0x780400);
    var cfg = makeBasicConfig(o1, o2, fw);
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter: m,
            ownerSide: 1,
            amount: ton("100"),
        },
    );
    js.set(
        1,
        JettonCfg {
            minter: m,
            ownerSide: 2,
            amount: ton("50"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 2;
    val escrow = prepareEscrow(cfg);
    var c: map<address, address> = [];
    c.set(m, jwAddr(m, escrow.address));
    var s: map<uint16, uint16> = [];
    s.set(0, 2);
    expect(
        sendAcceptDeal(o2.address, escrow, c, discoveryValue(2, s) - 1, true),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.jettonWalletStatus(0)).toEqual((null, false));
    expect(escrow.jettonWalletStatus(1)).toEqual((jwAddr(m, escrow.address), false));
    expect(
        escrow.sendText(o2.address, "deploy_fee", discoveryValue(2, s)),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.jettonWalletStatus(0)).toEqual((jwAddr(m, escrow.address), true));
    expect(escrow.jettonWalletStatus(1)).toEqual((jwAddr(m, escrow.address), true));
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
}

// owner1 cancels in SETUP while owner2's batch is still arriving: what
// arrives afterwards goes back to owner2.
get fun `test assets arriving after a cancel in SETUP go back`() {
    val d = oneSigDeal("ed5", 0x780500);
    acceptWithoutDiscovery(d, d.trueClaims());
    val (_req, attach) = d.escrow.cancelCost();
    expect(d.escrow.sendText(d.o1.address, "cancel_swap", attach)).toHaveAllSuccessfulTxs();
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
    expect(readJettonBalance(d.m1, d.o2.address)).toEqual(ton("100"));
    expect(
        sendNftToEscrow(d.o2, d.nft2, d.escrow.address, ton("0.2"), 1),
    ).toHaveAllSuccessfulTxs();
    expect(readMockOwner(d.nft2)).toEqual(d.o2.address);
}

// A notification that reaches the escrow's address before AcceptDeal deployed
// it is lost (a jetton notification does not bounce). This records what
// happens to the jettons and to an NFT sent the same way.
get fun `test a deposit before the escrow exists is lost`() {
    val d = oneSigDeal("ed6", 0x780600);
    sendJettonTransfer2(
        d.o2,
        d.m1,
        d.escrow.address,
        ton("10"),
        ton("0.2"),
        2,
    );
    sendNftToEscrow(d.o2, d.nft2, d.escrow.address, ton("0.2"), 1);
    expect(
        sendAcceptDeal(
            d.o2.address,
            d.escrow,
            d.trueClaims(),
            SERVICE_FEE + d.discovery(),
            true,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.receivedCounts().1).toEqual(0);
    expect(readJettonBalance(d.m1, d.escrow.address)).toEqual(ton("10"));
    expect(readMockOwner(d.nft2)).toEqual(d.escrow.address);
}
