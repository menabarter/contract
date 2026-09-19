// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "nosup_helpers"

get fun `test cancel by owner2 returns deposits and received NFTs`() {
    val o1 = testing.treasury("cx-o1");
    val o2 = testing.treasury("cx-o2");
    val fw = testing.treasury("cx-fw");

    // Side 1: 2 NFTs (both required), but only one gets deposited — a
    // partial deposit state at the time of cancel. Side 2: no GRAM/NFT at all.
    val nftIn = deployNft(o1, 9001);
    val nftOut = deployNft(o1, 9002);
    var nfts1: map<uint16, address> = [];
    nfts1.set(0, nftIn);
    nfts1.set(1, nftOut);
    val empty2: map<uint16, address> = [];
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: 2,
        nfts2: empty2,
        nfts2Count: 0,
        gram1Amount: ton("1"),
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    // Side-1 deposits: GRAM + service fee + one of the two NFTs (the 0.05
    // forward is credited to gram1DepositReserve — it feeds into the
    // refund1 formula below).
    expect(
        escrow.sendText(o1.address, "deposit_ton1", ton("1") + ton("0.01")),
    ).toHaveAllSuccessfulTxs();
    expect(
        escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendNftToEscrow(o1, nftIn, escrow.address, ton("0.05")),
    ).toHaveAllSuccessfulTxs();
    // nftOut is NOT deposited — it should stay with o1 (it never left its owner).

    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(escrow.receivedCounts()).toEqual((1, 0));

    // Cancel is sent by owner2 (not owner1) — cancel is allowed by EITHER side.
    val res = escrow.sendText(o2.address, "cancel_swap", ton("0.1"));
    expect(res).toHaveAllSuccessfulTxs();

    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    // The deposited NFT returned to its depositor (o1); the undeposited one never left.
    expect(readMockOwner(nftIn)).toEqual(o1.address);
    expect(readMockOwner(nftOut)).toEqual(o1.address);

    // refund1 = gram1Received(1.01) + serviceFee1(0.1) + reserve1Rem(0.05-0.03=0.02)
    // = 1.13 nominally; the forward fee under SEND_MODE_REGULAR trims it a
    // bit — a tolerance band on the low side.
    expect(res).toHaveTx({
        from: escrow.address,
        to: o1.address,
        value: fun(v: coins): bool {
            return v >= ton("1.1") && v <= ton("1.14");
        },
    });
    // owner2 deposited nothing → refund2 == 0 → no separate message to owner2.
}

// The existing cancel test only covers refund1 != 0 / refund2 == 0 (side 2
// deposited nothing). Here both sides deposit GRAM + service fee + a partial
// NFT, so both refunds are nonzero: checks that cancel_swap sends OUT BOTH
// refunds within tolerance AND returns BOTH deposited NFTs to their own
// depositors at the same time.
get fun `test cancel with both refunds nonzero returns both sides`() {
    val o1 = testing.treasury("cb-o1");
    val o2 = testing.treasury("cb-o2");
    val fw = testing.treasury("cb-fw");

    // Side 1: 2 NFTs required, deposits 1. Side 2: 2 NFTs required, deposits 1.
    val nft1In = deployNft(o1, 9101);
    val nft1Out = deployNft(o1, 9102);
    val nft2In = deployNft(o2, 9201);
    val nft2Out = deployNft(o2, 9202);
    var nfts1: map<uint16, address> = [];
    nfts1.set(0, nft1In);
    nfts1.set(1, nft1Out);
    var nfts2: map<uint16, address> = [];
    nfts2.set(0, nft2In);
    nfts2.set(1, nft2Out);
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: 2,
        nfts2,
        nfts2Count: 2,
        gram1Amount: ton("1"),
        gram2Amount: ton("2"),
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    // Side-1 deposits: GRAM + service fee + one of the two NFTs.
    expect(
        escrow.sendText(o1.address, "deposit_ton1", ton("1") + ton("0.01")),
    ).toHaveAllSuccessfulTxs();
    expect(
        escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendNftToEscrow(o1, nft1In, escrow.address, ton("0.05")),
    ).toHaveAllSuccessfulTxs();
    // Side-2 deposits: GRAM + service fee + one of the two NFTs.
    expect(
        escrow.sendText(o2.address, "deposit_ton2", ton("2") + ton("0.01")),
    ).toHaveAllSuccessfulTxs();
    expect(
        escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendNftToEscrow(o2, nft2In, escrow.address, ton("0.05")),
    ).toHaveAllSuccessfulTxs();

    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(escrow.receivedCounts()).toEqual((1, 1));

    val res = escrow.sendText(o1.address, "cancel_swap", ton("0.1"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);

    // Both deposited NFTs returned to their own depositors; the undeposited
    // ones never left their owners.
    expect(readMockOwner(nft1In)).toEqual(o1.address);
    expect(readMockOwner(nft1Out)).toEqual(o1.address);
    expect(readMockOwner(nft2In)).toEqual(o2.address);
    expect(readMockOwner(nft2Out)).toEqual(o2.address);

    // refund1 = gram1Received(1.01) + serviceFee1(0.1) + reserve1Rem(0.05-0.03=0.02)
    // ≈ 1.13; refund2 = gram2Received(2.01) + serviceFee2(0.1) + reserve2Rem(0.02)
    // ≈ 2.13 — the same formula/tolerance as the one-sided cancel test above.
    expect(res).toHaveTx({
        from: escrow.address,
        to: o1.address,
        value: fun(v: coins): bool {
            return v >= ton("1.1") && v <= ton("1.14");
        },
    });
    expect(res).toHaveTx({
        from: escrow.address,
        to: o2.address,
        value: fun(v: coins): bool {
            return v >= ton("2.1") && v <= ton("2.14");
        },
    });
}

get fun `test cancel by stranger rejected 403`() {
    val o1 = testing.treasury("cst-o1");
    val o2 = testing.treasury("cst-o2");
    val fw = testing.treasury("cst-fw");
    val stranger = testing.treasury("cst-x");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw));

    val res = escrow.sendText(stranger.address, "cancel_swap", ton("0.1"));
    expect(res).toHaveFailedTx({ to: escrow.address, exitCode: Errors.NotOwners });
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
}

get fun `test cancel after done rejected 410`() {
    val escrow = runFullSwap(1, 1, ton("1"), ton("2"));
    expect(escrow.phase()).toEqual(PHASE_DONE);

    // runFullSwap uses fixed internal treasury names ("rf-o1"/"rf-o2"/...) —
    // testing.treasury with the same name WITHIN THE SAME test deterministically
    // returns the same address (see .acton/emulation/testing.tolk:151
    // "Calling this method with same name will return the same treasury"),
    // so owner1 is available without changing runFullSwap's signature beyond
    // the already-added EscrowFixture return value.
    val o1 = testing.treasury("rf-o1");
    val res = escrow.sendText(o1.address, "cancel_swap", ton("0.1"));
    expect(res).toHaveFailedTx({ to: escrow.address, exitCode: Errors.AlreadyFinalized });
}

get fun `test deposit after cancel is rejected`() {
    val o1 = testing.treasury("dac-o1");
    val o2 = testing.treasury("dac-o2");
    val fw = testing.treasury("dac-fw");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw));

    expect(
        escrow.sendText(o1.address, "cancel_swap", ton("0.1")),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);

    // A deposit AFTER cancel → AlreadyFinalized.
    val res = escrow.sendText(o1.address, "deposit_ton1", ton("0.5"));
    expect(res).toHaveFailedTx({ to: escrow.address, exitCode: Errors.AlreadyFinalized });
}

get fun `test late NFT after cancel is auto-returned`() {
    val o1 = testing.treasury("late-o1");
    val o2 = testing.treasury("late-o2");
    val fw = testing.treasury("late-fw");
    val nft = deployNft(o1, 9500);
    var nfts1: map<uint16, address> = [];
    nfts1.set(0, nft);
    val empty2: map<uint16, address> = [];
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: 1,
        nfts2: empty2,
        nfts2Count: 0,
        gram1Amount: 0,
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    // The NFT enters the escrow normally (while ACTIVE), then is returned to
    // o1 via cancel — the mock is with o1 again. It is sent AGAIN (a late/
    // duplicate arrival) AFTER cancel: phase == CANCELLED != ACTIVE/SETUP →
    // an automatic return via the returnForeignNft branch in
    // handleNftReceived, not a throw.
    expect(
        sendNftToEscrow(o1, nft, escrow.address, ton("0.05")),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.receivedCounts()).toEqual((1, 0));

    expect(
        escrow.sendText(o1.address, "cancel_swap", ton("0.1")),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(readMockOwner(nft)).toEqual(o1.address);

    // A repeat send of the same NFT to the escrow — after cancel.
    val res = sendNftToEscrow(o1, nft, escrow.address, ton("0.05"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nft)).toEqual(o1.address);
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
}

// Cancel of a 50×50 deal (the largest single-transaction deal), FULLY
// deposited (all 100 NFTs + both GRAM amounts deposited), but auto did NOT
// fire — service_fee_owner2 is deliberately omitted (canAutoExecute requires
// serviceFee2 >= SERVICE_FEE). A cancel by an owner must go through at this
// size too, not only on the small configurations covered by the other cancel
// tests.
get fun `test cancel at 50x50 fully deposited but auto not fired`() {
    val o1 = testing.treasury("cap-o1");
    val o2 = testing.treasury("cap-o2");
    val fw = testing.treasury("cap-fw");

    var nfts1: map<uint16, address> = [];
    var i = 0;
    while (i < 50) {
        nfts1.set(i as uint16, deployNft(o1, 3000 + i));
        i += 1;
    }
    var nfts2: map<uint16, address> = [];
    var j = 0;
    while (j < 50) {
        nfts2.set(j as uint16, deployNft(o2, 4000 + j));
        j += 1;
    }
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: 50,
        nfts2,
        nfts2Count: 50,
        gram1Amount: ton("1"),
        gram2Amount: ton("2"),
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    // Side 1: GRAM + service fee + all 50 NFTs — fully deposited.
    expect(
        escrow.sendText(o1.address, "deposit_ton1", ton("1") + ton("0.01")),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    var r1 = nfts1.findFirst();
    while (r1.isFound) {
        expect(
            sendNftToEscrow(o1, r1.loadValue(), escrow.address, ton("0.05")),
        ).toHaveAllSuccessfulTxs();
        r1 = nfts1.iterateNext(r1);
    }
    // Side 2: GRAM + all 50 NFTs, but service_fee_owner2 is NOT sent.
    expect(
        escrow.sendText(o2.address, "deposit_ton2", ton("2") + ton("0.01")),
    ).toHaveAllSuccessfulTxs();
    var r2 = nfts2.findFirst();
    while (r2.isFound) {
        expect(
            sendNftToEscrow(o2, r2.loadValue(), escrow.address, ton("0.05")),
        ).toHaveAllSuccessfulTxs();
        r2 = nfts2.iterateNext(r2);
    }

    expect(escrow.receivedCounts()).toEqual((50, 50));
    expect(escrow.canAutoExecuteNow()).toEqual(false);
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);

    // A cancel from owner1 with enough gas to distribute 100 NFT returns.
    val res = escrow.sendText(o1.address, "cancel_swap", ton("2"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);

    // A spot check (not all 100): the first and last NFT of each side
    // returned to their own depositors.
    expect(readMockOwner(nfts1.mustGet(0))).toEqual(o1.address);
    expect(readMockOwner(nfts1.mustGet(49))).toEqual(o1.address);
    expect(readMockOwner(nfts2.mustGet(0))).toEqual(o2.address);
    expect(readMockOwner(nfts2.mustGet(49))).toEqual(o2.address);
}

// The 430 branch (Errors.InsufficientBalance in handleCancelSwap) — the only
// explicit balance assert in the entire contract. Design: several deal
// NFTs are deposited with a MINIMAL forward (0.001 TON each) — this keeps
// the contract's balance thin (little real inflow), while the MANDATORY cost
// of returning them (`NFT_TRANSFER_VALUE * received` — a fixed per-NFT
// constant of 0.03, NOT dependent on how much was actually forwarded at
// deposit time) quickly outgrows what is physically on the balance. Cancel
// is sent with a deliberately low (but nonzero — it must not fail with
// out-of-gas before the explicit assert) attached value.
get fun `test cancel with thin balance fails 430 InsufficientBalance`() {
    val o1 = testing.treasury("thin-o1");
    val o2 = testing.treasury("thin-o2");
    val fw = testing.treasury("thin-fw");

    var nfts1: map<uint16, address> = [];
    var i = 0;
    while (i < 5) {
        nfts1.set(i as uint16, deployNft(o1, 9800 + i));
        i += 1;
    }
    val empty2: map<uint16, address> = [];
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: 5,
        nfts2: empty2,
        nfts2Count: 0,
        gram1Amount: 0,
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    // All 5 NFTs are accepted with a small forward — gram1DepositReserve
    // grows by mere fractions (5 × 0.005 = 0.025 TON), while the MANDATORY
    // cost of returning them on cancel is a fixed 5 × NFT_TRANSFER_VALUE
    // (0.03) = 0.15 TON, regardless of what actually arrived. (The forward
    // is 0.005, not 0.001: acceptance parses the asset_index hint, and a tiny
    // 0.001 forward would not cover the gas of the acceptance transaction;
    // 0.025 is still ≪ 0.15, so the 430 logic holds.)
    var r1 = nfts1.findFirst();
    while (r1.isFound) {
        expect(
            sendNftToEscrow(o1, r1.loadValue(), escrow.address, ton("0.005")),
        ).toHaveAllSuccessfulTxs();
        r1 = nfts1.iterateNext(r1);
    }
    expect(escrow.receivedCounts()).toEqual((5, 0));

    // Cancel with a small attached value (0.01 TON — enough for compute, but
    // not enough for the contract's thin balance to cover required ≈ 0.15
    // (nft1ReturnCost) + ~0.0078 (fwdReserve) ≈ 0.158 TON; the contract's
    // real balance at this point is the deploy leftover (≈0.03-0.04 TON
    // after deploy costs and 5 acceptance transactions) + ~0.025 (reserve) +
    // 0.01 (this message) ≈ 0.07-0.08 — well below required.
    val res = escrow.sendText(o1.address, "cancel_swap", ton("0.01"));
    expect(res).toHaveFailedTx({ to: escrow.address, exitCode: Errors.InsufficientBalance });
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
}
