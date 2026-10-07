// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// A settled escrow keeps a year of storage fees, so it does not freeze while
// its pull path (claim_asset) may still be needed.
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/tlb/maybe"
import "@acton/types/big_array"
import "@acton/types/message"
import "@acton/types/out_actions"
import "@acton/types/transaction"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "nosup_helpers"

const YEAR = 31536000

fun isFrozen(a: address): bool {
    val st = testing.getAccountState(a);
    if (st == null) {
        return false;
    }
    return st.storage.state is TlbAccountStateFrozen;
}

// Makes the account run its storage phase without adding value to it: for a
// bounceable message the storage phase runs before the credit phase, and one
// nanoton buys no gas.
fun pingStorage(a: address) {
    val ping = testing.treasury("sf-ping");
    net.send(
        ping.address,
        createMessage({ bounce: BounceMode.Only256BitsOfBody, value: 1, dest: a }),
    );
}

// An 800-entry registry: a year of storage costs more than the 0.1 TON freeze
// limit, so a swept-to-zero escrow freezes within the year.
get fun `test a settled large registry does not freeze within a year`() {
    // Distinct skip entries: with one shared address the registry's cells
    // deduplicate and the state is far smaller than a real one.
    val f = deploySparseCancelMidState("sf-800", 799, 1, true);
    // Precondition: a year of this state's storage exceeds the 0.1 TON freeze
    // limit, so without a floor the escrow WOULD freeze. Without it the test
    // proves nothing.
    expect(testing.getAccountStorageFee(f.escrow.address, YEAR)! > ton("0.1")).toEqual(true);
    expect(f.escrow.sendText(f.o1.address, "kick", ton("1"))).toHaveAllSuccessfulTxs();
    expect(f.escrow.distributionProgress()).toEqual((DIST_IDLE, 800));
    testing.setNow(testing.getNow() + YEAR + 86400);
    pingStorage(f.escrow.address);
    expect(isFrozen(f.escrow.address)).toEqual(false);
}

// A year after settling, the escrow owes nothing for storage: the floor paid
// for the year.
get fun `test a year after settling the escrow owes no storage`() {
    val escrow = runFullSwap(1, 1, 0, 0, ton("0.20"));
    testing.setNow(testing.getNow() + YEAR);
    pingStorage(escrow.address);
    val st = testing.getAccountState(escrow.address)!;
    expect(st.storageStat.duePayment.unwrapOr(0)).toEqual(0);
}

// The floor holds after a jetton deal too (the registry's entries are wider).
get fun `test the balance after a jetton deal settles is the floor`() {
    val f = jdSetup("sf-jd", 77301);
    expect(
        f.escrow.sendText(f.o1.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(
        f.escrow.sendText(f.o2.address, "service_fee_owner2", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
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
    expect(f.escrow.phase()).toEqual(PHASE_DONE);
    expect(testing.getAccountBalance(f.escrow.address)).toEqual(f.escrow.storageFloor());
}

// After settling, the balance is exactly the floor — on the fast path (100
// assets) and the batch path (101), for execute and cancel.
get fun `test the balance after a fast execute is the floor`() {
    val escrow = runFullSwap(50, 50, 0, 0, ton("0.20"));
    expect(testing.getAccountBalance(escrow.address)).toEqual(escrow.storageFloor());
}

get fun `test the balance after a batch execute is the floor`() {
    val escrow = runFullSwap(51, 50, 0, 0, ton("0.20"));
    expect(escrow.distributionProgress()).toEqual((DIST_IDLE, 101));
    expect(testing.getAccountBalance(escrow.address)).toEqual(escrow.storageFloor());
}

get fun `test the balance after a fast cancel is the floor`() {
    val f = setup1x1("sf-fc", 77001);
    val (_req, attach) = f.escrow.cancelCost();
    expect(f.escrow.sendText(f.o1.address, "cancel_swap", attach)).toHaveAllSuccessfulTxs();
    expect(testing.getAccountBalance(f.escrow.address)).toEqual(f.escrow.storageFloor());
}

get fun `test the balance after a batch cancel is the floor`() {
    val f = deploySparseCancelMidState("sf-bc", 150, 5);
    expect(f.escrow.sendText(f.o1.address, "kick", ton("1"))).toHaveAllSuccessfulTxs();
    expect(testing.getAccountBalance(f.escrow.address)).toEqual(f.escrow.storageFloor());
}

// cancel_swap itself, with exactly cancelCost(), on registries of 100 (fast
// path) and 101 (batch path) entries with some of the items deposited. The
// no-deposit and one-deposit cases are in cancel_settlement.test.tolk.
fun cancelsToFloor(d: ActiveRegistry) {
    val (_req, attach) = d.escrow.cancelCost();
    expect(d.escrow.sendText(d.o1.address, "cancel_swap", attach)).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(d.escrow.distributionProgress().0).toEqual(DIST_IDLE);
    expect(testing.getAccountBalance(d.escrow.address)).toEqual(d.escrow.storageFloor());
}

get fun `test a fast cancel with partial deposits leaves the floor`() {
    cancelsToFloor(deployActiveRegistry("sf-p100", 100, 2, 0x640000));
}

get fun `test a batch cancel with partial deposits leaves the floor`() {
    cancelsToFloor(deployActiveRegistry("sf-p101", 101, 2, 0x650000));
}

// The model must not undershoot the real fee and must not overshoot it by more
// than 1.5x (NFT registries and a jetton registry).
fun checkModel(label: string, escrow: EscrowFixture) {
    val measured = testing.getAccountStorageFee(escrow.address, YEAR)!;
    val model = escrow.storageFloor();
    println("{}: measured {} model {}", label, measured, model);
    expect(model >= measured).toEqual(true);
    expect(model * 2 <= measured * 3).toEqual(true);
}

get fun `test the floor model brackets the measured fee`() {
    checkModel("1x1", setup1x1("sf-m1", 77101).escrow);
    checkModel("sparse 300", deploySparseCancelMidState("sf-m300", 299, 1, true).escrow);
    checkModel("sparse 1000", deploySparseCancelMidState("sf-m1000", 999, 1, true).escrow);
    checkModel("jettons", jdSetup("sf-mj", 77201).escrow);
}

// ── The cancel finale splits only a leftover worth two messages ──
// Each half of the finale's split pays its own forwarding (mode 0), so a small
// leftover cannot be split; it goes to the sweep with the dust margin. The
// kick value sets the leftover: a probe finale on an identical fixture
// measures it once, then each case aims the leftover at a target amount.

const SPLIT_PROBE_DEPLOY = ton("0.01")
const SPLIT_PROBE_KICK = ton("0.1")

// A 101-entry cancelled registry with nothing to return: a kick walks it and
// finalizes in the same transaction.
fun splitFixture(tag: string): SparseCancelFixture {
    return deploySparseCancelMidState(tag, 101, 0, false, SPLIT_PROBE_DEPLOY);
}

// The value `from`'s transaction queued for `who`, read from its out actions,
// before the forwarding fee is taken out of it; 0 when it queued nothing.
fun queuedTo(res: SendResultList, from: address, who: address): coins {
    var i = 0;
    while (i < res.size()) {
        val r = res.at(i);
        if (r.tx.load().getAccountAddress() == from) {
            val actions = r.allOutActions();
            var j = 0;
            while (j < actions.size()) {
                val m = actions.getSendMessageAt(j);
                if (m != null) {
                    val info = m.loadGenericMessage().info;
                    if (info.dest == who) {
                        return info.value.grams;
                    }
                }
                j += 1;
            }
        }
        i += 1;
    }
    return 0;
}

// The value `who` received, after the forwarding fee; 0 when nothing arrived.
fun deliveredTo(res: SendResultList, who: address): coins {
    var i = 0;
    while (i < res.size()) {
        val tx = res.at(i).tx.load();
        if (tx.getAccountAddress() == who) {
            val info = tx.loadInMsg<RemainingBitsAndRefs>().info;
            if (info is TlbInternalMessage) {
                return info.value.grams;
            }
        }
        i += 1;
    }
    return 0;
}

get fun `test the cancel finale splits only a leftover worth two messages`() {
    val probe = splitFixture("sf-sp0");
    val probeRes = probe.escrow.sendText(probe.o1.address, "kick", SPLIT_PROBE_KICK);
    expect(probeRes).toHaveAllSuccessfulTxs();
    val e = probe.escrow.address;
    val half1 = queuedTo(probeRes, e, probe.o1.address);
    val half2 = queuedTo(probeRes, e, probe.o2.address);
    // precondition: the probe did split, so its leftover is known exactly
    expect(half1 > 0 && half2 > 0).toEqual(true);
    val probeLeftover = half1 + half2;
    // a plain message's whole forwarding fee, taken out of its value
    val plainFwd = half2 - deliveredTo(probeRes, probe.o2.address);
    println("probe leftover {}, plain forward fee {}", probeLeftover, plainFwd);
    // two forward fees are below DUST, so DUST is the split threshold today
    expect(plainFwd * 2 < DUST).toEqual(true);

    finaleWithLeftover("sf-sp1", probeLeftover, 1);
    finaleWithLeftover("sf-sp2", probeLeftover, plainFwd);
    finaleWithLeftover("sf-sp3", probeLeftover, plainFwd * 2);
    finaleWithLeftover("sf-sp4", probeLeftover, plainFwd * 2 + 1);
    finaleWithLeftover("sf-sp5", probeLeftover, DUST);
    finaleWithLeftover("sf-sp6", probeLeftover, DUST + 1);
    finaleWithLeftover("sf-sp7", probeLeftover, DUST * 2);
}

// A kick aimed so that the finale's leftover is `target`: the finale
// completes, keeps the floor, and splits only above DUST.
fun finaleWithLeftover(tag: string, probeLeftover: coins, target: coins) {
    val f = splitFixture(tag);
    val res = f.escrow.sendText(f.o1.address, "kick", SPLIT_PROBE_KICK - probeLeftover + target);
    val half1 = queuedTo(res, f.escrow.address, f.o1.address);
    val half2 = queuedTo(res, f.escrow.address, f.o2.address);
    println("target {}: split {} + {}", target, half1, half2);
    expect(res).toHaveAllSuccessfulTxs();
    expect(f.escrow.distributionProgress()).toEqual((DIST_IDLE, 101));
    expect(testing.getAccountBalance(f.escrow.address)).toEqual(f.escrow.storageFloor());
    if (target > DUST) {
        expect(half1 + half2).toEqual(target);
    } else {
        expect(half1 + half2).toEqual(0);
    }
}
