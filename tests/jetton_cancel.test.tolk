// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/SwapEscrow.gen"
import "escrow_helpers"

get fun `test cancelReturnsReceivedJettons`() {
    val f = jdSetup("jc1", 51);
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
    expect(f.escrow.receivedCounts().0).toEqual(1);
    val res = f.escrow.sendText(f.o2.address, "cancel_swap", ton("0.3"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(readJettonBalance(f.minter, f.o1.address)).toEqual(
        ton("500"),
    ); // returned to the depositor
    expect(readJettonBalance(f.minter, f.escrow.address)).toEqual(0);
}

get fun `test emergencyCollectSendsJettonsToSupervisor`() {
    val f = jdSetup("jc2", 52);
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
    val res = f.escrow.sendText(f.sup.address, "emergency_collect_assets", ton("0.5"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(readJettonBalance(f.minter, f.sup.address)).toEqual(ton("100"));
}

get fun `test emergencyReturnSendsJettonsToContributor`() {
    val f = jdSetup("jc3", 53);
    expect(
        sendJettonTransfer2(
            f.o2,
            f.minter,
            f.escrow.address,
            ton("50"),
            ton("0.2"),
            1,
        ),
    ).toHaveAllSuccessfulTxs();
    val res = f.escrow.sendText(f.sup.address, "emergency_return_assets", ton("0.5"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(readJettonBalance(f.minter, f.o2.address)).toEqual(
        ton("500"),
    ); // returned to the depositor
}

get fun `test rescueJettonBySupervisor`() {
    // "Stuck" jettons: insufficient gas → the return did not go out, the
    // tokens sit on the escrow's wallet; the supervisor retrieves them via RescueJetton
    val f = jdSetup("jc4", 54);
    expect(
        sendJettonTransfer2(
            f.o1,
            f.minter,
            f.escrow.address,
            ton("40"),
            ton("0.001"),
            0,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(readJettonBalance(f.minter, f.escrow.address)).toEqual(ton("40")); // stuck
    val m = createMessage({
        bounce: true,
        value: ton("0.2"),
        dest: f.escrow.address,
        body: RescueJetton {
            queryId: 0,
            jettonWallet: jwAddr(f.minter, f.escrow.address),
            amount: ton("40"),
        },
    });
    expect(net.send(f.sup.address, m)).toHaveAllSuccessfulTxs();
    expect(readJettonBalance(f.minter, f.sup.address)).toEqual(ton("40"));
}

get fun `test rescueJettonFromNonSupervisorRejected`() {
    val f = jdSetup("jc5", 55);
    val m = createMessage({
        bounce: true,
        value: ton("0.2"),
        dest: f.escrow.address,
        body: RescueJetton {
            queryId: 0,
            jettonWallet: jwAddr(f.minter, f.escrow.address),
            amount: ton("1"),
        },
    });
    expect(net.send(f.o1.address, m)).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.NotSupervisor,
    });
}

// ── ASYMMETRIC refunds ──────────────────────────────────────────────────────
// The other cancel/emergency_return tests run SYMMETRIC configs (both
// sides deposit the same set of assets with the same attached value) — on
// such a config, a mutation that swaps "reserve1<->reserve2" or uses "0.03
// instead of 0.05" in the return-cost formula does not change the resulting
// refund amounts (the symmetry masks a transposition bug). Below is an
// ASYMMETRIC mixed config (1 NFT + 2 jettons from one minter on side 1, 1
// jetton on side 2, DIFFERENT attached value per deposit), WITHOUT a service
// fee (so auto-execute does not start before cancel/emergency_return) — the
// sides' numbers differ by an order of magnitude, so narrow windows on
// refund1/refund2 reliably catch a transposition of the reserves AND the
// return-cost constants.
struct AsymMixedFixture {
    o1: Treasury
    o2: Treasury
    fw: Treasury
    sup: Treasury
    minter: address
    nft: address
    escrow: EscrowFixture
}

// asset indices (assembly order in buildInitialStorage: nfts1, nfts2, then
// jettons by map key): 0=NFT(o1), 1=jetton100(o1), 2=jetton30(o1),
// 3=jetton50(o2). One minter on both sides → pendingWallets=1, resolves
// within the same deploy cascade → PHASE_ACTIVE right away (no explicit
// discovery step).
fun setupAsymMixedFixture(tag: string, seed: int): AsymMixedFixture {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val sup = testing.treasury(tagged(tag, "-sup"));
    val minter = deployJettonMinter(o1, seed);
    mintJettons(minter, o1, ton("500"));
    mintJettons(minter, o2, ton("500"));
    val nft = deployNft(o1, seed);
    var cfg = makeBasicConfig(o1, o2, fw, sup);
    var n1: map<uint16, address> = [];
    n1.set(0, nft);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
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
            ownerSide: 1,
            amount: ton("30"),
        },
    );
    js.set(
        2,
        JettonCfg {
            minter,
            ownerSide: 2,
            amount: ton("50"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 3;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);

    // Deposits with DIFFERENT attached value; no service fee is deposited.
    expect(sendNftToEscrow(o1, nft, escrow.address, ton("0.3"))).toHaveAllSuccessfulTxs();
    expect(
        sendJettonTransfer2(
            o1,
            minter,
            escrow.address,
            ton("100"),
            ton("0.2"),
            1,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendJettonTransfer2(
            o1,
            minter,
            escrow.address,
            ton("30"),
            ton("0.2"),
            2,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendJettonTransfer2(
            o2,
            minter,
            escrow.address,
            ton("50"),
            ton("0.1"),
            3,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.receivedCounts()).toEqual((3, 1));

    return AsymMixedFixture { o1, o2, fw, sup, minter, nft, escrow };
}

// reserve1 = 0.3(NFT) + 0.2(jetton100) + 0.2(jetton30) = 0.7 (SEND_MODE_
// PAY_FEES_SEPARATELY on all incoming notifications — the attached value
// reaches the escrow WITHOUT the forward fee deducted, see
// nft_item_mock.tolk/jetton_wallet_mock.tolk).
// return1Cost = NFT_TRANSFER_VALUE(0.03)*1 + JETTON_TRANSFER_VALUE(0.05)*2 = 0.13.
// refund1 = gram1Received(0) + serviceFee1(0) + max(0, 0.7-0.13) = 0.57 nominally.
// reserve2 = 0.1(jetton50). return2Cost = 0.05*1 = 0.05.
// refund2 = gram2Received(0) + serviceFee2(0) + max(0, 0.1-0.05) = 0.05 nominally.
// Windows: a tolerance of ~5% on the low side (the forward fee of the
// outgoing SEND_MODE_REGULAR refund message), the upper bound slightly
// above nominal — but the sides' windows do not overlap (0.54-0.571 vs
// 0.047-0.051), so a transposition of reserve1<->reserve2 (which would
// give refund1≈0.05, refund2≈0.57) would reliably fail this test.
get fun `test asymmetricMixedCancelPinsPerSideRefundWindows`() {
    val f = setupAsymMixedFixture("f1c", 71);
    val res = f.escrow.sendText(f.o1.address, "cancel_swap", ton("0.3"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);

    // Assets returned to their own depositors.
    expect(readMockOwner(f.nft)).toEqual(f.o1.address);
    expect(readJettonBalance(f.minter, f.o1.address)).toEqual(ton("500"));
    expect(readJettonBalance(f.minter, f.o2.address)).toEqual(ton("500"));
    expect(readJettonBalance(f.minter, f.escrow.address)).toEqual(0);

    expect(res).toHaveTx({
        from: f.escrow.address,
        to: f.o1.address,
        value: fun(v: coins): bool {
            return v >= ton("0.54") && v <= ton("0.571");
        },
    });
    expect(res).toHaveTx({
        from: f.escrow.address,
        to: f.o2.address,
        value: fun(v: coins): bool {
            return v >= ton("0.047") && v <= ton("0.051");
        },
    });
}

// The same config/deposits — emergency_return_assets (the supervisor path,
// the same refund formula as in handleCancelSwap, see the comment there).
get fun `test asymmetricMixedEmergencyReturnPinsPerSideRefundWindows`() {
    val f = setupAsymMixedFixture("f1e", 72);
    val res = f.escrow.sendText(f.sup.address, "emergency_return_assets", ton("0.5"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);

    expect(readMockOwner(f.nft)).toEqual(f.o1.address);
    expect(readJettonBalance(f.minter, f.o1.address)).toEqual(ton("500"));
    expect(readJettonBalance(f.minter, f.o2.address)).toEqual(ton("500"));
    expect(readJettonBalance(f.minter, f.escrow.address)).toEqual(0);

    expect(res).toHaveTx({
        from: f.escrow.address,
        to: f.o1.address,
        value: fun(v: coins): bool {
            return v >= ton("0.54") && v <= ton("0.571");
        },
    });
    expect(res).toHaveTx({
        from: f.escrow.address,
        to: f.o2.address,
        value: fun(v: coins): bool {
            return v >= ton("0.047") && v <= ton("0.051");
        },
    });
}
