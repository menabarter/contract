// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Execution sends a side's refund only when it reaches refundMinimum (DUST
// today). A refund below one forward fee cannot pay its own forwarding in mode
// 0: the action phase fails with result code 37 and the whole transaction
// aborts — on a completing NFT or jetton deposit that also loses the deposit's
// record, since COMMIT does not survive an action-phase failure. A smaller
// refund stays on the balance and the sweep carries it to the fee wallet.
import "@stdlib/gas-payments"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/types/message"
import "@acton/types/transaction"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "nosup_helpers"

// The value of the first message `from` sent `to` in this trace, as it
// arrived (net of its forward fee); -1 when there is none.
fun valueSent(res: SendResultList, from: address, to: address): coins {
    val tx = res.findTransaction({ from, to });
    if (tx == null) {
        return -1;
    }
    val info = tx.loadInMsg<RemainingBitsAndRefs>().info;
    if (info is TlbInternalMessage) {
        return info.value.grams;
    }
    return -1;
}

struct TinyDeal {
    escrow: EscrowFixture
    o1: Treasury
    o2: Treasury
    fw: Treasury
    lastNft: address
}

// n x n NFT deal with both fees paid. Side 1's NFTs, and side 2's unless
// `unhinted2`, are deposited with an index hint and a 0.003 forward, which
// leaves the balance short of what execution needs. With `unhinted2`, side
// 2's NFTs come without a hint and with a 0.04 forward: the linear search
// burns gas that the gross credit does not show, so side 2's counter runs far
// ahead of side 1's. `holdLast` keeps side 2's last NFT back. With pay1 >= 0,
// side 1 then pays its figure plus pay1.
fun tinyDeal(
    tag: string,
    seed: int,
    n: int,
    holdLast: bool,
    pay1: coins,
    unhinted2: bool,
): TinyDeal {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    var b: map<uint16, address> = [];
    var i = 0;
    while (i < n) {
        a.set(i as uint16, deployNft(o1, seed + i));
        b.set(i as uint16, deployNft(o2, seed + 5000 + i));
        i += 1;
    }
    cfg.nfts1 = a;
    cfg.nfts1Count = n;
    cfg.nfts2 = b;
    cfg.nfts2Count = n;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    i = 0;
    while (i < n) {
        expect(
            sendNftToEscrow(o1, a.mustGet(i as uint16), escrow.address, ton("0.003"), i),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    val last = holdLast ? n - 1 : n;
    i = 0;
    while (i < last) {
        if (unhinted2) {
            expect(
                sendNftToEscrow(o2, b.mustGet(i as uint16), escrow.address, ton("0.04")),
            ).toHaveAllSuccessfulTxs();
        } else {
            expect(
                sendNftToEscrow(o2, b.mustGet(i as uint16), escrow.address, ton("0.003"), n + i),
            ).toHaveAllSuccessfulTxs();
        }
        i += 1;
    }
    if (pay1 >= 0) {
        val (s1, _s2) = escrow.executionShortfall();
        expect(escrow.sendText(o1.address, "deposit_ton1", s1 + pay1)).toHaveAllSuccessfulTxs();
    }
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    return TinyDeal {
        escrow,
        o1,
        o2,
        fw,
        lastNft: b.mustGet((n - 1) as uint16),
    };
}

// A settled deal sent no refund to either side and kept exactly the storage
// floor.
fun expectNoRefundsAndFloor(
    res: SendResultList,
    escrow: EscrowFixture,
    o1: Treasury,
    o2: Treasury,
) {
    expect(escrow.phase()).toEqual(PHASE_DONE);
    expect(res).toNotHaveTx({ from: escrow.address, to: o1.address });
    expect(res).toNotHaveTx({ from: escrow.address, to: o2.address });
    expect(testing.getAccountBalance(escrow.address)).toEqual(escrow.storageFloor());
}

// ── fast path ──
// 50x50: side 1 pays its figure plus 0.0005 TON, side 2 then pays both
// figures plus `extra`. At extra = 0 the balance is exactly what execution
// needs and nothing is refunded; `extra` then lands in the refunds, below one
// forward fee at 50,000. The fee wallet comparison uses a 10,000 baseline
// rather than 0: with nothing to split, execution skips the split arithmetic
// and uses a few gas units less, which the sweep would show.

fun executeWithExtra(tag: string, seed: int, extra: coins): (TinyDeal, SendResultList, coins) {
    val d = tinyDeal(
        tag,
        seed,
        50,
        false,
        ton("0.0005"),
        false,
    );
    val (t1, t2) = d.escrow.executionShortfall();
    val fw0 = testing.getAccountBalance(d.fw.address);
    val res = d.escrow.sendText(d.o2.address, "execute_swap", t1 + t2 + extra);
    return (d, res, testing.getAccountBalance(d.fw.address) - fw0);
}

get fun `test execute_swap with refunds below one forward fee settles and sweeps them`() {
    expect(50000 < calculateForwardFee(BASECHAIN, 0, 0)).toEqual(true);
    val (_d0, _res0, fwBase) = executeWithExtra("erm-e0", 86001, 10000);
    val (d, res, fwGot) = executeWithExtra("erm-e1", 86201, 50000);
    expect(res).toNotHaveTx({ to: d.escrow.address, actionExitCode: 37 });
    expectNoRefundsAndFloor(res, d.escrow, d.o1, d.o2);
    // the unsent refunds reach the fee wallet with the sweep, to the nanoton
    expect(fwGot - fwBase).toEqual(40000);
}

get fun `test a completing NFT deposit with refunds below one forward fee is recorded and settles`() {
    val d = tinyDeal(
        "erm-n",
        86401,
        50,
        true,
        ton("0.0005"),
        false,
    );
    val (t1, t2) = d.escrow.executionShortfall();
    val res = sendNftToEscrow(d.o2, d.lastNft, d.escrow.address, t1 + t2 + 50000, 99);
    expect(res).toNotHaveTx({ to: d.escrow.address, actionExitCode: 37 });
    expect(d.escrow.receivedCounts()).toEqual((50, 50));
    expect(readMockOwner(d.lastNft)).toEqual(d.o1.address);
    expectNoRefundsAndFloor(res, d.escrow, d.o1, d.o2);
}

// 50 NFTs on side 1, deposited without a hint (the linear search burns gas
// that leaves the balance short), one jetton on side 2 that completes the
// deal with a forward of both figures plus 50,000.
get fun `test a completing jetton deposit with refunds below one forward fee is recorded and settles`() {
    val o1 = testing.treasury("erm-j-o1");
    val o2 = testing.treasury("erm-j-o2");
    val fw = testing.treasury("erm-j-fw");
    val minter = deployJettonMinter(o2, 86601);
    mintJettons(minter, o2, ton("100"));
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    var i = 0;
    while (i < 50) {
        a.set(i as uint16, deployNft(o1, 86610 + i));
        i += 1;
    }
    cfg.nfts1 = a;
    cfg.nfts1Count = 50;
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter,
            ownerSide: 2,
            amount: ton("10"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    val (s0, _s0) = escrow.executionShortfall();
    val f1 = s0 / 50 + 1;
    i = 0;
    while (i < 50) {
        expect(
            sendNftToEscrow(o1, a.mustGet(i as uint16), escrow.address, f1),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    val (s1, _s2) = escrow.executionShortfall();
    expect(
        escrow.sendText(o1.address, "deposit_ton1", s1 + ton("0.0005")),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    val (t1, t2) = escrow.executionShortfall();
    val res = sendJettonTransfer2(
        o2,
        minter,
        escrow.address,
        ton("10"),
        t1 + t2 + 50000,
        50,
    );
    expect(res).toNotHaveTx({ to: escrow.address, actionExitCode: 37 });
    expect(escrow.receivedCounts()).toEqual((50, 1));
    expect(readJettonBalance(minter, o1.address)).toEqual(ton("10"));
    expect(readJettonBalance(minter, escrow.address)).toEqual(0);
    expectNoRefundsAndFloor(res, escrow, o1, o2);
}

// ── batch finale ──
// 51x51 (102 assets, the batch path). Side 2's unhinted deposits run its
// counter far ahead of side 1's, so side 1's refund stays at zero until side
// 1 pays well over both figures; above that point every extra nanoton side 1
// pays lands in its own refund one for one. Side 1 completes the deal with a
// deposit of both figures plus `extra`; the refunds go out in the finale.

fun batchWithExtra(tag: string, seed: int, extra: coins): (TinyDeal, SendResultList, coins) {
    val d = tinyDeal(
        tag,
        seed,
        51,
        false,
        -1,
        true,
    );
    val (s1, s2) = d.escrow.executionShortfall();
    val fw0 = testing.getAccountBalance(d.fw.address);
    val res = d.escrow.sendText(d.o1.address, "deposit_ton1", s1 + s2 + extra);
    return (d, res, testing.getAccountBalance(d.fw.address) - fw0);
}

get fun `test a batch finale with a refund below one forward fee settles and sweeps it`() {
    val plainFwd = calculateForwardFee(BASECHAIN, 0, 0);
    // a probe on an identical fixture measures where side 1's refund starts:
    // 0.5 TON over both figures yields a refund well above the minimum. Where
    // the refund starts depends on the unhinted deposits' gas, i.e. on the
    // compiler: 0.072 over both figures on Tolk 1.4.2, 0.166 on Tolk 1.5.0.
    val probeExtra = ton("0.5");
    val (p, pres, _pfw) = batchWithExtra("erm-bp", 86801, probeExtra);
    expect(p.escrow.phase()).toEqual(PHASE_DONE);
    val probeRefund1 = valueSent(pres, p.escrow.address, p.o1.address) + plainFwd;
    expect(probeRefund1 > DUST).toEqual(true);
    val zeroAt = probeExtra - probeRefund1; // side 1's refund is exactly 0 here
    // side 1's refund of 0: nothing to send
    val (z, zres, fwZero) = batchWithExtra("erm-bz", 87001, zeroAt);
    expect(zres).toNotHaveTx({ to: z.escrow.address, actionExitCode: 37 });
    expect(z.escrow.phase()).toEqual(PHASE_DONE);
    // side 1's refund of 30,000, below one forward fee
    val (d, res, fwTiny) = batchWithExtra("erm-bt", 87201, zeroAt + 30000);
    expect(res).toNotHaveTx({ to: d.escrow.address, actionExitCode: 37 });
    expect(d.escrow.phase()).toEqual(PHASE_DONE);
    expect(res).toNotHaveTx({ from: d.escrow.address, to: d.o1.address });
    // side 2's refund is large and still goes out
    expect(res).toHaveTx({
        from: d.escrow.address,
        to: d.o2.address,
        value: fun(v: coins): bool {
            return v > DUST;
        },
    });
    expect(testing.getAccountBalance(d.escrow.address)).toEqual(d.escrow.storageFloor());
    // the unsent refund reaches the fee wallet with the sweep, to the nanoton
    expect(fwTiny - fwZero).toEqual(30000);
}
