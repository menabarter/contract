// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// execute_swap: either owner may call it; it executes only a fully funded deal;
// what it carries counts as the caller's own payment.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "@contracts/shared/types"
import "nosup_helpers"

struct Pending {
    escrow: EscrowFixture
    o1: Treasury
    o2: Treasury
    nfts1: map<uint16, address>
}

// n x n NFT deal, fees paid, every NFT deposited with `forward`; with a small
// forward the sides cannot cover their own transfers, so nothing executes.
fun pending(
    tag: string,
    seed: int,
    n: int,
    forward: coins,
    gram2: coins,
    gram1: coins = 0,
): Pending {
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
    cfg.gram1Amount = gram1;
    cfg.gram2Amount = gram2;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    i = 0;
    while (i < n) {
        sendNftToEscrow(o1, a.mustGet(i as uint16), escrow.address, forward, i);
        sendNftToEscrow(o2, b.mustGet(i as uint16), escrow.address, forward, n + i);
        i += 1;
    }
    return Pending {
        escrow,
        o1,
        o2,
        nfts1: a,
    };
}

// What each side adds to its executionShortfall() figure when both sides pay
// figures read at the same time: the first payment's own processing gas comes
// off the balance before the second payment arrives. A deposit_ton1/2 that
// does not execute costs 758,401 nanoton at today's gas price with Tolk 1.5.0
// (824,601 with Tolk 1.4.2; measured below in `paying the getter figures
// exactly ...`); 0.001 covers it with a 32% margin even when only one side
// adds it.
const GETTER_PAYMENT_HEADROOM = ton("0.001")

// Deposit processing gas comes off the shared balance, not off the per-side
// counters, so on an n x n deal with small NFT forwards the sides can be
// funded per side while the balance is still short of what execution needs.
// Both sides read executionShortfall() once, then each pays its figure plus
// the headroom: the deal must execute.
fun payGetterFiguresTogether(p: Pending, headroom: coins) {
    val (s1, s2) = p.escrow.executionShortfall();
    expect(p.escrow.sendText(p.o1.address, "deposit_ton1", s1 + headroom)).toHaveAllSuccessfulTxs();
    expect(p.escrow.sendText(p.o2.address, "deposit_ton2", s2 + headroom)).toHaveAllSuccessfulTxs();
}

get fun `test paying the getter figures executes a 30x30 deal with small forwards`() {
    val p = pending("es-g30", 79601, 30, ton("0.003"), 0);
    expect(p.escrow.phase()).toEqual(PHASE_ACTIVE);
    payGetterFiguresTogether(p, GETTER_PAYMENT_HEADROOM);
    expect(p.escrow.phase()).toEqual(PHASE_DONE);
}

get fun `test paying the getter figures executes a 50x50 deal with small forwards`() {
    val p = pending("es-g50", 79701, 50, ton("0.003"), 0);
    expect(p.escrow.phase()).toEqual(PHASE_ACTIVE);
    payGetterFiguresTogether(p, GETTER_PAYMENT_HEADROOM);
    expect(p.escrow.phase()).toEqual(PHASE_DONE);
}

// Without the headroom the balance ends short by exactly the two payments'
// processing gas, and the getter names that amount, split equally. The first
// payment's cost is what the headroom has to cover.
get fun `test paying the getter figures exactly falls short by the payments' own gas`() {
    val p = pending("es-g50x", 79801, 50, ton("0.003"), 0);
    val (s1, s2) = p.escrow.executionShortfall();
    val b0 = testing.getAccountBalance(p.escrow.address);
    p.escrow.sendText(p.o1.address, "deposit_ton1", s1);
    val b1 = testing.getAccountBalance(p.escrow.address);
    val cost1 = b0 + s1 - b1;
    p.escrow.sendText(p.o2.address, "deposit_ton2", s2);
    val cost2 = b1 + s2 - testing.getAccountBalance(p.escrow.address);
    expect(p.escrow.phase()).toEqual(PHASE_ACTIVE);
    val (u1, u2) = p.escrow.executionShortfall();
    // the top-ups that keep both shares non-negative round up: at most 1
    // nanoton above the payments' gas
    expect(u1 + u2 - (cost1 + cost2)).toBeInRange(0, 1);
    expect(u2 - u1).toBeInRange(-1, 1);
    expect(cost1 < GETTER_PAYMENT_HEADROOM).toEqual(true);
}

// After both sides have paid their figures exactly, each side is funded on its
// own counters, but the balance is short by the two payments' gas. An
// execute_swap carrying less than that shortfall passes every per-side check
// and must still stop at the balance check (430), leaving the deal untouched.
get fun `test execute_swap on a short balance fails with 430 and changes nothing`() {
    val p = pending("es-430", 79951, 50, ton("0.003"), 0);
    val (s1, s2) = p.escrow.executionShortfall();
    p.escrow.sendText(p.o1.address, "deposit_ton1", s1);
    p.escrow.sendText(p.o2.address, "deposit_ton2", s2);
    expect(p.escrow.phase()).toEqual(PHASE_ACTIVE);
    val (u1, u2) = p.escrow.executionShortfall();
    val carried = ton("0.001");
    expect(u1 + u2 > carried).toEqual(true);
    val res = p.escrow.sendText(p.o1.address, "execute_swap", carried);
    expect(res).toHaveFailedTx({ to: p.escrow.address, exitCode: Errors.InsufficientBalance });
    expect(p.escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(readMockOwner(p.nfts1.mustGet(0))).toEqual(p.escrow.address);
}

// Once side 1's payment has landed, side 1's figure is only its half of the
// balance deficit that payment's gas left; side 2 can pay both figures and
// the deal executes with no headroom at all.
get fun `test after one side has paid the other can pay both figures`() {
    val p = pending("es-g50s", 79901, 50, ton("0.003"), 0);
    val (s1, _s2) = p.escrow.executionShortfall();
    p.escrow.sendText(p.o1.address, "deposit_ton1", s1);
    val (t1, t2) = p.escrow.executionShortfall();
    expect(t1 > 0).toEqual(true);
    expect(p.escrow.sendText(p.o2.address, "deposit_ton2", t1 + t2)).toHaveAllSuccessfulTxs();
    expect(p.escrow.phase()).toEqual(PHASE_DONE);
}

// A 60x60 batch deal with a 3 TON leg and NFT forwards of 0.005: the forwards
// cannot cover the leg, so calling execute_swap by hand must not move NFTs
// while the leg is unpaid.
get fun `test an underfunded batch deal is not executed by hand`() {
    val p = pending("es-uf", 79001, 60, ton("0.005"), ton("3"));
    p.escrow.sendText(p.o2.address, "deposit_ton2", ton("3"));
    val res = p.escrow.sendText(p.o1.address, "execute_swap", ton("0.3"));
    expect(res).toHaveFailedTx({ to: p.escrow.address, exitCode: Errors.SideUnderfunded1 });
    expect(p.escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(readMockOwner(p.nfts1.mustGet(0))).toEqual(p.escrow.address);
}

get fun `test owner 2 can execute a funded deal`() {
    val p = pending("es-o2", 79101, 2, ton("0.005"), 0);
    val (s1, s2) = p.escrow.executionShortfall();
    p.escrow.sendText(p.o1.address, "deposit_ton1", s1);
    expect(p.escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(
        p.escrow.sendText(p.o2.address, "execute_swap", s2 + ton("0.05")),
    ).toHaveAllSuccessfulTxs();
    expect(p.escrow.phase()).toEqual(PHASE_DONE);
}

// The 0.2 TON forward on each NFT deposit funds side 2's overall share
// through gram2DepositReserve while its TON leg (gram2Received) stays at 0:
// executionShortfall() must still name an amount whose payment closes the
// leg (gramNReceived >= gramNAmount, 420/421), not just the netted share
// (sideFunded, 433/434), because a real payment raises both counters by the
// same amount. Paying the netted share alone would still leave the leg
// short and fail with 421 (NotEnoughTon2); this executes on the getter's
// own number plus gas headroom instead.
get fun `test executionShortfall accounts for the unpaid leg`() {
    val p = pending("es-leg", 79151, 2, ton("0.2"), ton("1"));
    expect(p.escrow.phase()).toEqual(PHASE_ACTIVE);
    val g = p.escrow.gramState();
    expect(g.gram2Received).toEqual(0); // the leg is unpaid
    val (_s1, s2) = p.escrow.executionShortfall();
    expect(s2 >= g.gram2Amount - g.gram2Received).toEqual(true);
    expect(
        p.escrow.sendText(p.o2.address, "execute_swap", s2 + ton("0.05")),
    ).toHaveAllSuccessfulTxs();
    expect(p.escrow.phase()).toEqual(PHASE_DONE);
}

// The same for side 1: its forwards fund its share, its TON leg is unpaid, and
// the figure must cover the leg.
get fun `test executionShortfall accounts for side 1's unpaid leg`() {
    val p = pending(
        "es-leg1",
        79161,
        2,
        ton("0.2"),
        0,
        ton("1"),
    );
    expect(p.escrow.phase()).toEqual(PHASE_ACTIVE);
    val g = p.escrow.gramState();
    expect(g.gram1Received).toEqual(0); // the leg is unpaid
    val (s1, _s2) = p.escrow.executionShortfall();
    expect(s1 >= g.gram1Amount - g.gram1Received).toEqual(true);
    expect(
        p.escrow.sendText(p.o1.address, "execute_swap", s1 + ton("0.05")),
    ).toHaveAllSuccessfulTxs();
    expect(p.escrow.phase()).toEqual(PHASE_DONE);
}

// A settled deal has no balance check left to pass: once it has executed,
// neither side owes anything, whatever its balance now holds.
get fun `test executionShortfall is zero once the deal has executed`() {
    val p = pending("es-done", 79171, 2, ton("0.2"), 0);
    expect(p.escrow.phase()).toEqual(PHASE_DONE);
    expect(p.escrow.executionShortfall()).toEqual((0, 0));
}

// What execute_swap carries is credited to the caller before the checks, so a
// side can pay its TON leg and its share and execute with one message.
get fun `test pay and execute in one message`() {
    val p = pending("es-one", 79201, 2, ton("0.2"), ton("1"));
    expect(p.escrow.phase()).toEqual(PHASE_ACTIVE);
    val (_s1, s2) = p.escrow.executionShortfall();
    expect(
        p.escrow.sendText(p.o2.address, "execute_swap", s2 + ton("0.05")),
    ).toHaveAllSuccessfulTxs();
    expect(p.escrow.phase()).toEqual(PHASE_DONE);
}

get fun `test a stranger cannot call execute_swap`() {
    val f = setup1x1("es-st", 79301);
    val stranger = testing.treasury("es-st-x");
    val res = f.escrow.sendText(stranger.address, "execute_swap", ton("0.1"));
    expect(res).toHaveFailedTx({ to: f.escrow.address, exitCode: Errors.NotOwners });
}

// side 1's NFT forward comfortably covers its own transfer cost and half the
// shared costs; side 2's forward (0.005) does not. No GRAM legs, both service
// fees paid, both NFTs received, so 420-424 all pass and the deal fails
// specifically on side 2's per-side check.
get fun `test only side 2 underfunded yields 434`() {
    val o1 = testing.treasury("s434-o1");
    val o2 = testing.treasury("s434-o2");
    val fw = testing.treasury("s434-fw");
    val nft1 = deployNft(o1, 79401);
    val nft2 = deployNft(o2, 79402);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, nft1);
    var n2: map<uint16, address> = [];
    n2.set(0, nft2);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    cfg.nfts2 = n2;
    cfg.nfts2Count = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, nft1, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o2, nft2, escrow.address, ton("0.005"), 1)).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    val res = escrow.sendText(o1.address, "execute_swap", ton("0.1"));
    expect(res).toHaveFailedTx({ to: escrow.address, exitCode: Errors.SideUnderfunded2 });
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
}

// A symmetric 1x1 GRAM deal (side 1 and side 2 configured identically). NFT
// forwards below NFT_TRANSFER_VALUE leave BOTH sides short by the same
// amount, so the deal needs one side topped up by a plain deposit and the
// other by execute_swap to finish — letting the test choose which owner is
// the one that calls execute_swap.
struct SymmetricDeal {
    escrow: EscrowFixture
    o1: Treasury
    o2: Treasury
    fw: Treasury
    nft1: address
    nft2: address
}

fun symmetricDeal(tag: string, seed: int): SymmetricDeal {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val nft1 = deployNft(o1, seed);
    val nft2 = deployNft(o2, seed + 1);
    var n1: map<uint16, address> = [];
    n1.set(0, nft1);
    var n2: map<uint16, address> = [];
    n2.set(0, nft2);
    var cfg = makeBasicConfig(o1, o2, fw);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    cfg.nfts2 = n2;
    cfg.nfts2Count = 1;
    cfg.gram1Amount = ton("1");
    cfg.gram2Amount = ton("1");
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "deposit_ton1", ton("1"))).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, nft1, escrow.address, ton("0.005"), 0)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "deposit_ton2", ton("1"))).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o2, nft2, escrow.address, ton("0.005"), 1)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.canAutoExecuteNow()).toEqual(false);
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    return SymmetricDeal { escrow, o1, o2, fw, nft1, nft2 };
}

// execute_swap is open to both owners, and whichever one calls it
// must not change the outcome. Two identical deals, one finished by owner 1
// calling execute_swap (owner 2's side topped up by a plain deposit first),
// the other finished by owner 2 (owner 1's side topped up by a plain deposit
// first) must land on the same NFT owners and, for each role (o1, o2, fee
// wallet), the same balance change — up to the caller's own extra cost of
// being the one whose message carries the execution (both the deposit and
// the execute_swap message here carry the same 0.05 TON margin above their
// shortfall, so that margin cancels out; what is left is the real gas
// difference between a plain deposit and a message that also runs the
// execution: measured at ~42000 nanoTON for o1/o2 and ~7000 nanoTON for the
// fee wallet, so the tolerance below (0.001 TON) has over an order of
// magnitude of headroom).
get fun `test execute_swap gives the same result regardless of which owner calls it`() {
    val a = symmetricDeal("es-sym-a", 79501);
    val b = symmetricDeal("es-sym-b", 79511);

    val balA1 = testing.getAccountBalance(a.o1.address);
    val balA2 = testing.getAccountBalance(a.o2.address);
    val balAf = testing.getAccountBalance(a.fw.address);
    val balB1 = testing.getAccountBalance(b.o1.address);
    val balB2 = testing.getAccountBalance(b.o2.address);
    val balBf = testing.getAccountBalance(b.fw.address);

    // Deal A: owner 2's side is topped up by a plain deposit, owner 1 calls
    // execute_swap to close its own side and run the execution.
    val (sA1, sA2) = a.escrow.executionShortfall();
    expect(
        a.escrow.sendText(a.o2.address, "deposit_ton2", sA2 + ton("0.05")),
    ).toHaveAllSuccessfulTxs();
    expect(
        a.escrow.sendText(a.o1.address, "execute_swap", sA1 + ton("0.05")),
    ).toHaveAllSuccessfulTxs();
    expect(a.escrow.phase()).toEqual(PHASE_DONE);

    // Deal B: the mirror image — owner 1's side topped up by deposit, owner 2
    // calls execute_swap.
    val (sB1, sB2) = b.escrow.executionShortfall();
    expect(
        b.escrow.sendText(b.o1.address, "deposit_ton1", sB1 + ton("0.05")),
    ).toHaveAllSuccessfulTxs();
    expect(
        b.escrow.sendText(b.o2.address, "execute_swap", sB2 + ton("0.05")),
    ).toHaveAllSuccessfulTxs();
    expect(b.escrow.phase()).toEqual(PHASE_DONE);

    // Same NFT destinations regardless of who executed.
    expect(readMockOwner(a.nft1)).toEqual(a.o2.address);
    expect(readMockOwner(a.nft2)).toEqual(a.o1.address);
    expect(readMockOwner(b.nft1)).toEqual(b.o2.address);
    expect(readMockOwner(b.nft2)).toEqual(b.o1.address);

    // Same balance change per role, within the caller's-own-message tolerance.
    val deltaA1 = testing.getAccountBalance(a.o1.address) - balA1;
    val deltaA2 = testing.getAccountBalance(a.o2.address) - balA2;
    val deltaAf = testing.getAccountBalance(a.fw.address) - balAf;
    val deltaB1 = testing.getAccountBalance(b.o1.address) - balB1;
    val deltaB2 = testing.getAccountBalance(b.o2.address) - balB2;
    val deltaBf = testing.getAccountBalance(b.fw.address) - balBf;
    val tolerance = ton("0.001");
    expect(deltaA1 - deltaB1 > -tolerance && deltaA1 - deltaB1 < tolerance).toEqual(true);
    expect(deltaA2 - deltaB2 > -tolerance && deltaA2 - deltaB2 < tolerance).toEqual(true);
    expect(deltaAf - deltaBf > -tolerance && deltaAf - deltaBf < tolerance).toEqual(true);
}
