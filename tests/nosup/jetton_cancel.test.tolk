// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "nosup_helpers"

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

// ── ASYMMETRIC refunds ──────────────────────────────────────────────────────
// The other cancel tests run SYMMETRIC configs (both sides deposit the same
// set of assets with the same attached value) — on such a config, a mutation
// that swaps "reserve1<->reserve2" or uses "0.03 instead of 0.05" in the
// return-cost formula does not change the resulting refund amounts (the
// symmetry masks a transposition bug). Below is an ASYMMETRIC mixed config (1
// NFT + 2 jettons from one minter on side 1, 1 jetton on side 2, DIFFERENT
// attached value per deposit), WITHOUT a service fee (so auto-execute does
// not start before cancel) — the sides' numbers differ by an order of
// magnitude, so narrow windows on refund1/refund2 reliably catch a
// transposition of the reserves AND the return-cost constants.
struct AsymMixedFixture {
    o1: Treasury
    o2: Treasury
    fw: Treasury
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
    val minter = deployJettonMinter(o1, seed);
    mintJettons(minter, o1, ton("500"));
    mintJettons(minter, o2, ton("500"));
    val nft = deployNft(o1, seed);
    var cfg = makeBasicConfig(o1, o2, fw);
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

    return AsymMixedFixture { o1, o2, fw, minter, nft, escrow };
}

// reserve1 = 0.3(NFT) + 0.2(jetton100) + 0.2(jetton30) = 0.7 (SEND_MODE_
// PAY_FEES_SEPARATELY on all incoming notifications — the attached value
// reaches the escrow WITHOUT the forward fee deducted, see
// nft_item_mock.tolk/jetton_wallet_mock.tolk).
// return1Cost = NFT_TRANSFER_VALUE(0.03)*1 + JETTON_TRANSFER_VALUE(0.05)*2 = 0.13.
// Side 1's net contribution N1 = 0.7 - 0.13 = 0.57.
// reserve2 = 0.1(jetton50). return2Cost = 0.05*1 = 0.05; N2 = 0.05.
// Each refund is N_i less half the shared costs (gas, dust) plus half the
// deploy remainder, which arrived unattributed; the refunds differ by exactly
// N1 - N2 = 0.52. Measured: refund1 = 0.597652, refund2 = 0.077652.
// The sides' windows do not overlap (0.585-0.61 vs 0.065-0.09), so a
// transposition of reserve1<->reserve2 would reliably fail this test.
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
            return v >= ton("0.585") && v <= ton("0.61");
        },
    });
    expect(res).toHaveTx({
        from: f.escrow.address,
        to: f.o2.address,
        value: fun(v: coins): bool {
            return v >= ton("0.065") && v <= ton("0.09");
        },
    });
}
