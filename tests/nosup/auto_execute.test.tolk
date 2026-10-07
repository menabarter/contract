// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "nosup_helpers"

get fun `test auto-execute fires on last deposit 1x1 with GRAM both sides`() {
    runFullSwap(1, 1, ton("1"), ton("2"));
}

get fun `test auto-execute fires 2x2 without GRAM`() {
    runFullSwap(2, 2, 0, 0);
}

get fun `test manual execute_swap by owner1 works when everything is in`() {
    val o1 = testing.treasury("me-o1");
    val o2 = testing.treasury("me-o2");
    val fw = testing.treasury("me-fw");
    val nft1 = deployNft(o1, 7000);
    val nft2 = deployNft(o2, 8000);
    var nfts1: map<uint16, address> = [];
    nfts1.set(0, nft1);
    var nfts2: map<uint16, address> = [];
    nfts2.set(0, nft2);

    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: 1,
        nfts2,
        nfts2Count: 1,
        gram1Amount: ton("1"),
        gram2Amount: ton("2"),
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    // Deposits WITHOUT a margin (unlike runFullSwap): GRAM at exactly face
    // value, NFT forwardValue deliberately below NFT_TRANSFER_VALUE — the
    // contract's resulting real balance ends up below minBalanceForSwap (the
    // threshold is computed from the deal's PARAMETERS, not from how much
    // actually arrived on top), so auto-execution does not fire on any
    // deposit, including the last one — service_fee_owner2, deliberately
    // sent last.
    expect(escrow.sendText(o1.address, "deposit_ton1", ton("1"))).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, nft1, escrow.address, ton("0.005"))).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "deposit_ton2", ton("2"))).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o2, nft2, escrow.address, ton("0.005"))).toHaveAllSuccessfulTxs();
    val lastDepositRes = escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE);
    expect(lastDepositRes).toHaveAllSuccessfulTxs();

    // All six require() checks for canAutoExecute pass (received/gram/fee),
    // but the balance is insufficient → auto did NOT fire, the phase is
    // still ACTIVE.
    expect(escrow.canAutoExecuteNow()).toEqual(false);
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);

    // execute_swap runs the same funding checks as auto-execution, so getting
    // past them needs both sides actually funded: side 2's shortfall is
    // topped up first (it does not on its own make side 1 funded, so this
    // does not auto-execute), then owner1 calls execute_swap carrying its own
    // shortfall plus gas — which is credited to side 1 before the checks run.
    val (s1, s2) = escrow.executionShortfall();
    expect(escrow.sendText(o2.address, "deposit_ton2", s2 + ton("0.05"))).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    val res = escrow.sendText(o1.address, "execute_swap", s1 + ton("0.05"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_DONE);
    expect(readMockOwner(nft1)).toEqual(o2.address);
    expect(readMockOwner(nft2)).toEqual(o1.address);
}

get fun `test execute_swap by stranger rejected with 403`() {
    val o1 = testing.treasury("st-o1");
    val o2 = testing.treasury("st-o2");
    val fw = testing.treasury("st-fw");
    val stranger = testing.treasury("st-x");
    val empty1: map<uint16, address> = [];
    val empty2: map<uint16, address> = [];
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1: empty1,
        nfts1Count: 0,
        nfts2: empty2,
        nfts2Count: 0,
        gram1Amount: ton("1"),
        gram2Amount: ton("2"),
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    // execute_swap from neither owner → exit Errors.NotOwners, regardless of
    // deposit state (the sender check is the first assert in the handler).
    val res = escrow.sendText(stranger.address, "execute_swap", ton("0.1"));
    expect(res).toHaveFailedTx({ to: escrow.address, exitCode: Errors.NotOwners });
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
}

get fun `test no auto-execute while NFTs missing`() {
    val o1 = testing.treasury("nm-o1");
    val o2 = testing.treasury("nm-o2");
    val fw = testing.treasury("nm-fw");

    var nfts1: map<uint16, address> = [];
    nfts1.set(0, deployNft(o1, 5000));
    nfts1.set(1, deployNft(o1, 5001));
    var nfts2: map<uint16, address> = [];
    nfts2.set(0, deployNft(o2, 6000));

    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: 2,
        nfts2,
        nfts2Count: 1,
        gram1Amount: ton("1"),
        gram2Amount: ton("2"),
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    // all canAutoExecute conditions are met, EXCEPT one side-1 NFT
    // (received1Count will be 1 < required1Count=2).
    expect(
        escrow.sendText(o1.address, "deposit_ton1", ton("1") + ton("0.01")),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(
        sendNftToEscrow(o1, nfts1.mustGet(0), escrow.address, ton("0.05")),
    ).toHaveAllSuccessfulTxs();
    // NFT #1 of side 1 is NOT sent.
    expect(
        escrow.sendText(o2.address, "deposit_ton2", ton("2") + ton("0.01")),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(
        sendNftToEscrow(o2, nfts2.mustGet(0), escrow.address, ton("0.05")),
    ).toHaveAllSuccessfulTxs();

    expect(escrow.canAutoExecuteNow()).toEqual(false);
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
}

// GRAM exchange direction: executeSwap sends each side the amount deposited
// by the OPPOSITE side (see Storage.executeSwapSingleTx, "GRAM exchange").
// Checking phase and NFT owners alone would not catch a transposition of
// owner1/owner2 (or gram1Amount/gram2Amount) inside executeSwap — this test
// pins the GRAM transfer amounts and their direction.
//
// Design: gram1Amount=1, gram2Amount=2 (asymmetric, so 1/2 cannot be
// confused), 1×1 NFT. Asymmetric SURPLUSES (owner1 deposits 10 above
// gram1Amount, owner2 2 above gram2Amount) additionally check the refunds:
// each side gets back its own surplus minus half the shared costs, so the
// LARGER surplus (owner1, despite the SMALLER nominal gram1Amount) must come
// back as the LARGER refund. If refund1/refund2 were transposed in the code,
// or a refund were computed from a side's nominal amount (gram2Amount=2 >
// gram1Amount=1) rather than from what it actually paid, the refund bands
// below would not match.
get fun `test GRAM cross-payment direction and refund sanity`() {
    val o1 = testing.treasury("gx-o1");
    val o2 = testing.treasury("gx-o2");
    val fw = testing.treasury("gx-fw");
    val nft1 = deployNft(o1, 9700);
    val nft2 = deployNft(o2, 9701);
    var nfts1: map<uint16, address> = [];
    nfts1.set(0, nft1);
    var nfts2: map<uint16, address> = [];
    nfts2.set(0, nft2);

    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: 1,
        nfts2,
        nfts2Count: 1,
        gram1Amount: ton("1"),
        gram2Amount: ton("2"),
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    // owner1: gram1Amount(1) + a LARGE surplus (10).
    expect(
        escrow.sendText(o1.address, "deposit_ton1", ton("1") + ton("10")),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, nft1, escrow.address, ton("0.05"))).toHaveAllSuccessfulTxs();
    // owner2: gram2Amount(2) + a smaller surplus (2).
    expect(
        escrow.sendText(o2.address, "deposit_ton2", ton("2") + ton("2")),
    ).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o2, nft2, escrow.address, ton("0.05"))).toHaveAllSuccessfulTxs();
    val res = escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE);
    expect(res).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_DONE);

    // 1. DIRECTION of the GRAM exchange: owner1 receives gram2Amount (2 TON —
    // owner2's contribution), NOT gram1Amount (1 TON, its own contribution
    // back). The (1.9, 2.0] tolerance deliberately excludes 1 TON.
    expect(res).toHaveTx({
        from: escrow.address,
        to: o1.address,
        value: fun(v: coins): bool {
            return v > ton("1.9") && v <= ton("2");
        },
    });
    // owner2 receives gram1Amount (1 TON — owner1's contribution), NOT
    // gram2Amount (2 TON, its own contribution back). The (0.95, 1.0]
    // tolerance excludes 2 TON.
    expect(res).toHaveTx({
        from: escrow.address,
        to: o2.address,
        value: fun(v: coins): bool {
            return v > ton("0.95") && v <= ton("1");
        },
    });

    // 2. Refund sanity: owner1's surplus (10 + its NFT forward's excess over
    // the transfer) comes back as refund1 ≈ 10.04, owner2's (2 + the same
    // excess) as refund2 ≈ 2.04. The ranges below do NOT overlap with the
    // GRAM-exchange ranges above (refund1 > 4 TON, well above owner1's
    // GRAM-tx zone (<= 2 TON); refund2 is in (1.2, 4] TON — above owner2's
    // GRAM-tx zone (<= 1 TON) but below the refund1 zone, so both toHaveTx
    // calls match THEIR OWN transfer, not the other one's).
    expect(res).toHaveTx({
        from: escrow.address,
        to: o1.address,
        value: fun(v: coins): bool {
            return v > ton("4");
        },
    });
    expect(res).toHaveTx({
        from: escrow.address,
        to: o2.address,
        value: fun(v: coins): bool {
            return v > ton("1.2") && v <= ton("4");
        },
    });
}

// Manual execute_swap — coverage of the serviceFee1(422)/serviceFee2(423)/
// NftsNotReceived(424) gates. execute_swap is open to both owners and closed
// to everyone else: 420 (NotEnoughTon1) is pinned down by deploy.test.tolk
// "test known command routes to its handler stub not 130", and 403
// (NotOwners) by "test execute_swap by stranger rejected with 403" above.
get fun `test execute_swap gate: missing service fee 1 yields 422`() {
    val o1 = testing.treasury("eg1-o1");
    val o2 = testing.treasury("eg1-o2");
    val fw = testing.treasury("eg1-fw");
    val empty1: map<uint16, address> = [];
    val empty2: map<uint16, address> = [];
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1: empty1,
        nfts1Count: 0,
        nfts2: empty2,
        nfts2Count: 0,
        gram1Amount: ton("1"),
        gram2Amount: ton("2"),
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    // Both GRAM amounts are deposited in full (otherwise it would have
    // failed earlier on 420/421), but service_fee_owner1 is NOT sent —
    // handleExecuteSwap checks gram1/gram2 BEFORE serviceFee1, so it fails
    // specifically on 422.
    expect(escrow.sendText(o1.address, "deposit_ton1", ton("1"))).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "deposit_ton2", ton("2"))).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);

    val res = escrow.sendText(o1.address, "execute_swap", ton("0.1"));
    expect(res).toHaveFailedTx({ to: escrow.address, exitCode: Errors.ServiceFee1 });
}

get fun `test execute_swap gate: missing service fee 2 yields 423`() {
    val o1 = testing.treasury("eg2-o1");
    val o2 = testing.treasury("eg2-o2");
    val fw = testing.treasury("eg2-fw");
    val empty1: map<uint16, address> = [];
    val empty2: map<uint16, address> = [];
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1: empty1,
        nfts1Count: 0,
        nfts2: empty2,
        nfts2Count: 0,
        gram1Amount: ton("1"),
        gram2Amount: ton("2"),
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    // GRAM for both sides + serviceFee1 are deposited, service_fee_owner2 is not.
    expect(escrow.sendText(o1.address, "deposit_ton1", ton("1"))).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "deposit_ton2", ton("2"))).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);

    val res = escrow.sendText(o1.address, "execute_swap", ton("0.1"));
    expect(res).toHaveFailedTx({ to: escrow.address, exitCode: Errors.ServiceFee2 });
}

get fun `test execute_swap gate: missing NFT yields 424`() {
    val o1 = testing.treasury("eg3-o1");
    val o2 = testing.treasury("eg3-o2");
    val fw = testing.treasury("eg3-fw");
    val nft1 = deployNft(o1, 9750);
    var nfts1: map<uint16, address> = [];
    nfts1.set(0, nft1);
    val empty2: map<uint16, address> = [];
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: 1,
        nfts2: empty2,
        nfts2Count: 0,
        gram1Amount: ton("1"),
        gram2Amount: ton("2"),
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    // GRAM + both service fees are deposited, but the required side-1 NFT is not.
    expect(escrow.sendText(o1.address, "deposit_ton1", ton("1"))).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "deposit_ton2", ton("2"))).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);

    val res = escrow.sendText(o1.address, "execute_swap", ton("0.1"));
    expect(res).toHaveFailedTx({ to: escrow.address, exitCode: Errors.NftsNotReceived });
}

// A late in-deal NFT AFTER DONE.
// "test late NFT after cancel is auto-returned" (cancel.test.tolk) already
// pins down the CANCELLED branch of handleNftReceived; this test covers the
// DONE branch (the same `if (st.phase != PHASE_ACTIVE && st.phase !=
// PHASE_SETUP)`, but a different phase value). The NEW owner (who received
// the NFT via the swap itself) sends it BACK to the escrow after
// completion — it must go to returnForeignNft (not throw), rather than
// being accepted again.
get fun `test late in-deal NFT after DONE is auto-returned`() {
    val o1 = testing.treasury("ld-o1");
    val o2 = testing.treasury("ld-o2");
    val fw = testing.treasury("ld-fw");
    val nft1 = deployNft(o1, 9600);
    val nft2 = deployNft(o2, 9601);
    var nfts1: map<uint16, address> = [];
    nfts1.set(0, nft1);
    var nfts2: map<uint16, address> = [];
    nfts2.set(0, nft2);
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: 1,
        nfts2,
        nfts2Count: 1,
        gram1Amount: ton("1"),
        gram2Amount: ton("2"),
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    expect(
        escrow.sendText(o1.address, "deposit_ton1", ton("1") + ton("0.01")),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, nft1, escrow.address, ton("0.05"))).toHaveAllSuccessfulTxs();
    expect(
        escrow.sendText(o2.address, "deposit_ton2", ton("2") + ton("0.01")),
    ).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o2, nft2, escrow.address, ton("0.05"))).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();

    expect(escrow.phase()).toEqual(PHASE_DONE);
    expect(readMockOwner(nft1)).toEqual(o2.address); // nft1 (side 1) went to owner2
    expect(readMockOwner(nft2)).toEqual(o1.address);

    // nft1's new owner (o2) sends it BACK to the escrow after DONE —
    // handleNftReceived sees phase == DONE (not ACTIVE/SETUP) → the
    // returnForeignNft branch, not a throw. The transaction must stay
    // successful, and the NFT must return to its sender (o2) rather than
    // being "accepted" again.
    val res = sendNftToEscrow(o2, nft1, escrow.address, ton("0.05"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nft1)).toEqual(o2.address);
    expect(escrow.phase()).toEqual(PHASE_DONE);
}

// A side with no assets and no TON leg pays its fee and its half of the shared
// costs; anything it pays above that comes back to it on execute, together
// with its half of what the deal received from nobody in particular (the
// deploy remainder).
get fun `test a side with no assets gets back its overpayment`() {
    val o1 = testing.treasury("nr2-o1");
    val o2 = testing.treasury("nr2-o2");
    val fw = testing.treasury("nr2-fw");
    val nft1 = deployNft(o1, 7001);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, nft1);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    // nfts2Count == 0, gram1 == gram2 == 0
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    val (_s1, s2) = escrow.executionShortfall();
    // side 2 pays its share and 0.5 TON more
    expect(escrow.sendText(o2.address, "deposit_ton2", s2 + ton("0.5"))).toHaveAllSuccessfulTxs();
    val last = sendNftToEscrow(o1, nft1, escrow.address, ton("0.3"));
    expect(last).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_DONE);
    expect(readMockOwner(nft1)).toEqual(o2.address); // the NFT reached side 2
    // 0.5 plus half the deploy remainder (about 0.024 TON)
    expect(last).toHaveTx({
        from: escrow.address,
        to: o2.address,
        value: fun(v: coins): bool {
            return v >= ton("0.5") && v <= ton("0.55");
        },
    });
}
