// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Cancel sends a side's refund, and the canceller's surplus, only when it
// reaches sendableMinimum (two plain forward fees). An amount below one
// forward fee cannot pay its own forwarding in mode 0: the action phase would
// fail with result code 37 and the cancel would abort. Anyone can move the
// refunds with an unattributed inflow (an Excesses is credited without checks
// and split equally), so a stranger could otherwise keep a deal from being
// cancelled. A smaller amount stays on the balance and the sweep carries it.
import "@stdlib/gas-payments"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/messages"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "nosup_helpers"

struct TinyCancel {
    escrow: EscrowFixture
    o1: Treasury
    o2: Treasury
    fw: Treasury
}

// Side 1: 5 TON leg + fee, 1 NFT (forward 0.2); side 2: 50 NFTs with a 0.002
// forward and no fee, so side 2 falls short of its share of the cancel costs.
fun shortSide2Deal(tag: string, seed: int): TinyCancel {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val a1 = deployNft(o1, seed);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, a1);
    var b: map<uint16, address> = [];
    var i = 0;
    while (i < 50) {
        b.set(i as uint16, deployNft(o2, seed + 1 + i));
        i += 1;
    }
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = 50;
    cfg.gram1Amount = ton("5");
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "deposit_ton1", ton("5"))).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, a1, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    i = 0;
    while (i < 50) {
        expect(
            sendNftToEscrow(o2, b.mustGet(i as uint16), escrow.address, ton("0.002"), 1 + i),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    return TinyCancel { escrow, o1, o2, fw };
}

// A stranger's Excesses of `value`, credited without checks.
fun strangerInflow(tag: string, escrow: address, value: coins) {
    val stranger = testing.treasury(tagged(tag, "-x"));
    val m = createMessage({
        bounce: BounceMode.NoBounce,
        value,
        dest: escrow,
        body: Excesses { queryId: 0 },
    });
    expect(net.send(stranger.address, m)).toHaveAllSuccessfulTxs();
}

// Side 2's shortfall, while side 1 has none: required minus the balance is
// exactly side 2's negative share.
fun side2Short(escrow: EscrowFixture): coins {
    val (req, _attach) = escrow.cancelCost();
    return req - testing.getAccountBalance(escrow.address);
}

// Lifts side 2's share of a cancel to `target` with two stranger inflows. An
// inflow is split equally, less the gas of the transaction that receives it:
// the first inflow, of twice the shortfall, measures that gas; the second
// covers what is still short plus 2 x `target` and the same gas.
fun liftSide2To(tag: string, escrow: EscrowFixture, target: coins) {
    val short = side2Short(escrow);
    expect(short > 0).toEqual(true);
    strangerInflow(tagged(tag, "-a"), escrow.address, short * 2);
    val left = side2Short(escrow);
    expect(left > 0).toEqual(true);
    val lost = short * 2 - (short - left) * 2;
    // +2 nanoton: an inflow is halved, so an odd remainder would otherwise
    // leave side 2 one nanoton short.
    strangerInflow(tagged(tag, "-b"), escrow.address, left * 2 + target * 2 + lost + 2);
    // nobody is short any more
    expect(side2Short(escrow)).toEqual(0);
}

// ── fast path ──
// The fee wallet comparisons use a baseline fixture where the amount held
// back is 0: the cancel then runs the same code path, and the difference in
// what the sweep carries is exactly the amount held back.

fun cancelLiftedTo(tag: string, seed: int, target: coins): (TinyCancel, SendResultList, coins) {
    val d = shortSide2Deal(tag, seed);
    liftSide2To(tag, d.escrow, target);
    val (_req, attach) = d.escrow.cancelCost();
    val fw0 = testing.getAccountBalance(d.fw.address);
    val res = d.escrow.sendText(d.o1.address, "cancel_swap", attach);
    return (d, res, testing.getAccountBalance(d.fw.address) - fw0);
}

// A settled cancel: side 1's refund went out, side 2's did not, and the
// escrow kept exactly the storage floor.
fun expectCancelledWithoutSide2(res: SendResultList, d: TinyCancel) {
    expect(res).toNotHaveTx({ to: d.escrow.address, actionExitCode: 37 });
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(res).toNotHaveTx({ from: d.escrow.address, to: d.o2.address });
    expect(res).toHaveTx({
        from: d.escrow.address,
        to: d.o1.address,
        value: fun(v: coins): bool {
            return v > ton("5");
        },
    });
    expect(testing.getAccountBalance(d.escrow.address)).toEqual(d.escrow.storageFloor());
}

get fun `test a stranger's inflow leaving a refund below one forward fee does not block cancel`() {
    expect(30000 < calculateForwardFee(BASECHAIN, 0, 0)).toEqual(true);
    val (z, zres, fwBase) = cancelLiftedTo("crm-f0", 88001, 0);
    expectCancelledWithoutSide2(zres, z);
    val (d, res, fwGot) = cancelLiftedTo("crm-f1", 88101, 30000);
    expectCancelledWithoutSide2(res, d);
    // the unsent refund reaches the fee wallet with the sweep. The lift lands
    // within a few thousand nanoton of its target, on the baseline too.
    expect(fwGot - fwBase).toBeInRange(25000, 35000);
}

// The canceller attaches a few nanoton above its shortfall: the surplus is
// below one forward fee and stays for the sweep.
fun cancelWithSurplus(tag: string, seed: int, extra: coins): (TinyCancel, SendResultList, coins) {
    val d = shortSide2Deal(tag, seed);
    val short = side2Short(d.escrow);
    expect(short > 0).toEqual(true);
    val fw0 = testing.getAccountBalance(d.fw.address);
    val res = d.escrow.sendText(d.o1.address, "cancel_swap", short + extra);
    return (d, res, testing.getAccountBalance(d.fw.address) - fw0);
}

get fun `test a surplus below one forward fee does not block cancel`() {
    val (z, zres, fwBase) = cancelWithSurplus("crm-s0", 88201, 0);
    expectCancelledWithoutSide2(zres, z);
    val (d, res, fwGot) = cancelWithSurplus("crm-s1", 88301, 5);
    expectCancelledWithoutSide2(res, d);
    // side 1 gets its refund only, no surplus message
    expect(res).toNotHaveTx({
        from: d.escrow.address,
        to: d.o1.address,
        value: fun(v: coins): bool {
            return v < ton("5");
        },
    });
    expect(fwGot - fwBase).toEqual(5);
}

// ── batch path ──
// A 101-entry registry with no deposits: side 1 pays its fee, side 2 pays
// nothing and is short. The first batch reaches the end of the registry
// without sending, so the chain finalizes in the initiating transaction; the
// amount held back is not counted as queued there.

get fun `test a batch cancel with a refund below one forward fee completes`() {
    val d = deployActiveRegistry("crm-b", 101, 0, 0x6B0000);
    expect(
        d.escrow.sendText(d.o1.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    liftSide2To("crm-b", d.escrow, 30000);
    val (_req, attach) = d.escrow.cancelCost();
    val res = d.escrow.sendText(d.o1.address, "cancel_swap", attach);
    expect(res).toNotHaveTx({ to: d.escrow.address, actionExitCode: 37 });
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(d.escrow.distributionProgress()).toEqual((DIST_IDLE, 101));
    // precondition: the chain finalized inside the initiating transaction
    expect(res).toNotHaveTx<ContinueDistribution>({ to: d.escrow.address });
    // no message to side 2 below one forward fee (66,667 nanoton)
    expect(res).toNotHaveTx({
        from: d.escrow.address,
        to: d.o2.address,
        value: fun(v: coins): bool {
            return v < 66667;
        },
    });
    expect(testing.getAccountBalance(d.escrow.address)).toEqual(d.escrow.storageFloor());
}
