// GENERATED from tests/nosup/accept_deal.test.tolk by ts-tests/gen-v2-tests.ts — edit the source, then run npm run gen:v2.
// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// AcceptDeal: side 2 deploys the escrow, pays its share up front and starts
// jetton wallet discovery in one message. It never fails for lack of value,
// so the transfers that follow it in the same batch always find a deployed
// escrow.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowV2.gen"
import "@contracts/shared/types"
import "@contracts/v2/storage"
import "v2_helpers"

// A deal with one NFT on side 1 and a jetton of a real mock minter on side 2,
// prepared but not deployed. gram2 is side 2's TON leg.
struct AcceptFixture {
    escrow: EscrowFixture
    o1: Treasury
    o2: Treasury
    minter: address
    nft1: address
}

fun acceptFixture(tag: string, seed: int, gram2: coins): AcceptFixture {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val minter = deployJettonMinter(o2, seed);
    val nft1 = deployNft(o1, seed + 1);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, nft1);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.gram2Amount = gram2;
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter,
            ownerSide: 2,
            amount: ton("5"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 1;
    return AcceptFixture {
        escrow: prepareEscrow(cfg),
        o1,
        o2,
        minter,
        nft1,
    };
}

fun oneMinter(): map<uint16, uint16> {
    var s: map<uint16, uint16> = [];
    s.set(0, 1);
    return s;
}

get fun `test AcceptDeal from owner2 deploys and starts discovery`() {
    val f = acceptFixture("ad1", 0x720000, 0);
    val value = SERVICE_FEE + discoveryValue(2, oneMinter());
    expect(sendAcceptDeal(f.o2.address, f.escrow, [], value, true)).toHaveAllSuccessfulTxs();
    expect(testing.isDeployed(f.escrow.address)).toEqual(true);
    expect(f.escrow.pendingWalletsLeft()).toEqual(0);
    expect(f.escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(f.escrow.assetJettonWallet(1)).toEqual(jwAddr(f.minter, f.escrow.address));
}

// Below the discovery price AcceptDeal is still accepted: the escrow is
// deployed (so the batch's notifications land) and the value is side 2's.
get fun `test AcceptDeal below the discovery price deploys without discovery`() {
    val f = acceptFixture("ad2", 0x720100, 0);
    val value = discoveryValue(2, oneMinter()) - 1;
    expect(sendAcceptDeal(f.o2.address, f.escrow, [], value, true)).toHaveAllSuccessfulTxs();
    expect(testing.isDeployed(f.escrow.address)).toEqual(true);
    expect(f.escrow.phase()).toEqual(PHASE_SETUP);
    expect(f.escrow.pendingWalletsLeft()).toEqual(1);
    expect(f.escrow.assetJettonWallet(1)).toEqual(null);
    val g = f.escrow.gramState();
    expect(g.serviceFee2 + g.gram2Received + g.gram2DepositReserve).toEqual(value);
    // deploy_fee starts discovery later
    expect(
        f.escrow.sendText(f.o2.address, "deploy_fee", discoveryValue(2, oneMinter())),
    ).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_ACTIVE);
}

// Fee first, then the TON leg, then the reserve.
get fun `test AcceptDeal credits the fee, then the leg, then the reserve`() {
    val f = acceptFixture("ad3", 0x720200, ton("1"));
    val reserve = ton("0.3") + discoveryValue(2, oneMinter());
    expect(
        sendAcceptDeal(f.o2.address, f.escrow, [], SERVICE_FEE + ton("1") + reserve, true),
    ).toHaveAllSuccessfulTxs();
    val g = f.escrow.gramState();
    expect(g.serviceFee2).toEqual(SERVICE_FEE);
    expect(g.gram2Received).toEqual(ton("1"));
    expect(g.gram2DepositReserve).toEqual(reserve);
}

get fun `test AcceptDeal smaller than the fee goes to the fee`() {
    val f = acceptFixture("ad4", 0x720300, ton("1"));
    expect(sendAcceptDeal(f.o2.address, f.escrow, [], ton("0.05"), true)).toHaveAllSuccessfulTxs();
    val g = f.escrow.gramState();
    expect(g.serviceFee2).toEqual(ton("0.05"));
    expect(g.gram2Received).toEqual(0);
    expect(g.gram2DepositReserve).toEqual(0);
}

get fun `test AcceptDeal from anyone but owner2 is rejected`() {
    val f = acceptFixture("ad5", 0x720400, 0);
    expect(
        sendAcceptDeal(
            f.o2.address,
            f.escrow,
            [],
            SERVICE_FEE + discoveryValue(2, oneMinter()),
            true,
        ),
    ).toHaveAllSuccessfulTxs();
    val stranger = testing.treasury("ad5-x");
    expect(sendAcceptDeal(f.o1.address, f.escrow, [], ton("0.5"), false)).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.NotOwner2,
    });
    expect(sendAcceptDeal(stranger.address, f.escrow, [], ton("0.5"), false)).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.NotOwner2,
    });
}

get fun `test AcceptDeal after cancel is rejected`() {
    val f = acceptFixture("ad6", 0x720500, 0);
    expect(
        sendAcceptDeal(
            f.o2.address,
            f.escrow,
            [],
            SERVICE_FEE + discoveryValue(2, oneMinter()),
            true,
        ),
    ).toHaveAllSuccessfulTxs();
    val (_req, attach) = f.escrow.cancelCost();
    expect(f.escrow.sendText(f.o1.address, "cancel_swap", attach)).toHaveAllSuccessfulTxs();
    expect(sendAcceptDeal(f.o2.address, f.escrow, [], ton("0.5"), false)).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.AlreadyFinalized,
    });
}

// The first message of a batch carries the StateInit. Even when its handler
// fails (here: the wrong sender), the account is deployed with its initial
// state, so the transfers that follow in the same batch still reach the
// escrow's code.
get fun `test a failed first AcceptDeal still deploys the account`() {
    val f = acceptFixture("ad7", 0x720600, 0);
    expect(sendAcceptDeal(f.o1.address, f.escrow, [], ton("0.5"), true)).toHaveFailedTx({
        to: f.escrow.address,
        exitCode: Errors.NotOwner2,
    });
    expect(testing.isDeployed(f.escrow.address)).toEqual(true);
    expect(f.escrow.phase()).toEqual(PHASE_SETUP);
}

// In ACTIVE AcceptDeal only credits; when it completes the funding the deal
// executes in the same transaction.
get fun `test AcceptDeal in ACTIVE can complete the deal`() {
    val o1 = testing.treasury("ad8-o1");
    val o2 = testing.treasury("ad8-o2");
    val fw = testing.treasury("ad8-fw");
    val n1 = deployNft(o1, 0x720700);
    val n2 = deployNft(o2, 0x720701);
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
    expect(sendNftToEscrow(o1, n1, escrow.address, ton("0.5"), 0)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o2, n2, escrow.address, ton("0.5"), 1)).toHaveAllSuccessfulTxs();
    expect(sendAcceptDeal(o2.address, escrow, [], SERVICE_FEE, false)).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_DONE);
}
