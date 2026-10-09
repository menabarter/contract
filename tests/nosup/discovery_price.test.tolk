// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Discovery is priced per minter by the number of its slots, and whatever an
// owner pays for it counts as that owner's payment.
import "@stdlib/gas-payments"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "@contracts/shared/types"
import "nosup_helpers"

// Two minters, one slot each, on a 4-entry registry: each provide is priced by
// its own minter's slots, not by the whole registry.
get fun `test a provide is priced by its minter's slots`() {
    val n = 4;
    val perMinter = PROVIDE_WALLET_VALUE +
        calculateGasFee(
            BASECHAIN,
            TAKE_SCAN_BASE_UNITS + TAKE_SCAN_UNITS_PER_ENTRY * n + TAKE_SET_UNITS,
        );
    var s: map<uint16, uint16> = [];
    s.set(0, 1);
    s.set(1, 1);
    val scan = calculateGasFee(BASECHAIN, DEPLOY_BASE_GAS_UNITS + DEPLOY_GAS_UNITS_PER_ASSET * n);
    expect(discoveryValue(n, s)).toEqual(perMinter * 2 + scan);
    val d = oneSigDeal("dp1", 0x750000);
    expect(
        sendAcceptDeal(d.o2.address, d.escrow, d.trueClaims(), discoveryValue(n, s) - 1, true),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.pendingWalletsLeft()).toEqual(2);
    expect(
        d.escrow.sendText(d.o2.address, "deploy_fee", discoveryValue(n, s) - 1),
    ).toHaveFailedTx({
        to: d.escrow.address,
        exitCode: Errors.InsufficientBalance,
    });
    expect(
        d.escrow.sendText(d.o2.address, "deploy_fee", discoveryValue(n, s)),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_ACTIVE);
}

// The worst answer — every slot of the minter provisionally received from a
// false claim, all undone — completes on what the provide carried.
get fun `test the worst answer fits its reserve`() {
    val o1 = testing.treasury("dp2-o1");
    val o2 = testing.treasury("dp2-o2");
    val fw = testing.treasury("dp2-fw");
    val m = deployJettonMinter(o2, 0x750100);
    var cfg = makeBasicConfig(o1, o2, fw);
    var js: map<uint16, JettonCfg> = [];
    var i = 0;
    while (i < 40) {
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
    cfg.jettonsCount = 40;
    val escrow = prepareEscrow(cfg);
    val fake = testing.treasury("dp2-fake");
    var c: map<address, address> = [];
    c.set(m, fake.address);
    var s: map<uint16, uint16> = [];
    s.set(0, 40);
    expect(
        sendAcceptDeal(o2.address, escrow, c, discoveryValue(40, s) - 1, true),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.pendingWalletsLeft()).toEqual(1);
    i = 0;
    while (i < 40) {
        expect(
            fakeNotification(
                fake.address,
                escrow.address,
                o2.address,
                ton("1"),
                i,
                ton("0.05"),
            ),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    expect(escrow.receivedCounts().1).toEqual(40);
    expect(
        escrow.sendText(o2.address, "deploy_fee", discoveryValue(40, s)),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.receivedCounts().1).toEqual(0);
    expect(escrow.pendingWalletsLeft()).toEqual(0);
}

get fun `test deploy_fee from an owner counts as its payment`() {
    val d = oneSigDeal("dp3", 0x750200);
    acceptWithoutDiscovery(d, d.trueClaims());
    val before = d.escrow.gramState().gram2DepositReserve;
    expect(d.escrow.sendText(d.o2.address, "deploy_fee", d.discovery())).toHaveAllSuccessfulTxs();
    expect(d.escrow.gramState().gram2DepositReserve - before).toEqual(d.discovery());
}

get fun `test deploy_fee from a stranger counts for no side`() {
    val d = oneSigDeal("dp4", 0x750300);
    acceptWithoutDiscovery(d, d.trueClaims());
    val g0 = d.escrow.gramState();
    val x = testing.treasury("dp4-x");
    expect(d.escrow.sendText(x.address, "deploy_fee", d.discovery())).toHaveAllSuccessfulTxs();
    val g1 = d.escrow.gramState();
    expect(g1.gram1DepositReserve).toEqual(g0.gram1DepositReserve);
    expect(g1.gram2DepositReserve).toEqual(g0.gram2DepositReserve);
}

get fun `test the one-signature flow completes at 2x gas price`() {
    val saved = scaleGasPrice(2, 1);
    val d = oneSigDeal("dp5", 0x750400);
    expect(
        sendAcceptDeal(
            d.o2.address,
            d.escrow,
            d.trueClaims(),
            SERVICE_FEE + d.discovery(),
            true,
        ),
    ).toHaveAllSuccessfulTxs();
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
    expect(d.escrow.phase()).toEqual(PHASE_DONE);
    expect(testing.setConfig(saved)).toEqual(true);
}
