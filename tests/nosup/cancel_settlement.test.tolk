// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Cancel settles by the same formula as execute. To cancel, the canceller
// covers any side's shortfall (its own first); anything attached above that
// comes back. A side cannot leave for free at the other side's expense.
import "@stdlib/gas-payments"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/types/big_array"
import "@acton/types/transaction"
import "@contracts/messages"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "nosup_helpers"

// Transactions in the trace that ran on `who`'s account. In a cancel's trace
// an owner's account only runs to receive a payment from the escrow (the
// cancel message itself starts at the escrow), so this counts the payments.
fun paymentsTo(res: SendResultList, who: address): int {
    var n = 0;
    var i = 0;
    while (i < res.size()) {
        if (res.at(i).tx.load().getAccountAddress() == who) {
            n += 1;
        }
        i += 1;
    }
    return n;
}

struct CancelDeal {
    escrow: EscrowFixture
    o1: Treasury
    o2: Treasury
    fw: Treasury
}

// side 1: 5 TON leg + fee, 1 NFT (forward 0.2); side 2: `n2` NFTs with forward
// `fwd2`, no fee. Nothing executes (side 2's fee is unpaid).
fun cancelDeal(tag: string, seed: int, n2: int, fwd2: coins): CancelDeal {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val a1 = deployNft(o1, seed);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, a1);
    var b: map<uint16, address> = [];
    var i = 0;
    while (i < n2) {
        b.set(i as uint16, deployNft(o2, seed + 1 + i));
        i += 1;
    }
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = n2;
    cfg.gram1Amount = ton("5");
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "deposit_ton1", ton("5"))).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, a1, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    i = 0;
    while (i < n2) {
        sendNftToEscrow(o2, b.mustGet(i as uint16), escrow.address, fwd2, 1 + i);
        i += 1;
    }
    return CancelDeal { escrow, o1, o2, fw };
}

// The underfunded side cannot cancel with a token amount.
get fun `test an underfunded side cannot cancel for free`() {
    val d = cancelDeal("cs-free", 76001, 50, ton("0.002"));
    val res = d.escrow.sendText(d.o2.address, "cancel_swap", ton("0.005"));
    expect(res).toHaveFailedTx({ to: d.escrow.address, exitCode: Errors.InsufficientBalance });
    expect(d.escrow.phase()).toEqual(PHASE_ACTIVE);
}

// Paying its own shortfall, the underfunded side leaves and side 1 gets back
// everything it paid minus half of the shared costs.
get fun `test the underfunded side cancels by paying its shortfall`() {
    val d = cancelDeal("cs-own", 76101, 50, ton("0.002"));
    val (_req, attach) = d.escrow.cancelCost();
    val o1Before = testing.getAccountBalance(d.o1.address);
    expect(d.escrow.sendText(d.o2.address, "cancel_swap", attach)).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
    // side 1 paid 5 + 0.1 + 0.2; it gets back at least 5.1 (shared costs are
    // well under the 0.2 of its NFT forward minus the 0.03 return)
    expect(testing.getAccountBalance(d.o1.address) - o1Before >= ton("5.1")).toEqual(true);
}

// The funded side leaving an underfunded counterparty pays that shortfall,
// and its own refund is not reduced by it: side 1 paid 5 + 0.1 + 0.2 and gets
// back that less its own return (0.03) and half the shared costs, in one
// message; the shortfall it covered is a separate part of its attachment.
get fun `test the funded side pays the counterparty's shortfall to leave`() {
    val d = cancelDeal("cs-other", 76201, 50, ton("0.002"));
    val cheap = d.escrow.sendText(d.o1.address, "cancel_swap", ton("0.005"));
    expect(cheap).toHaveFailedTx({ to: d.escrow.address, exitCode: Errors.InsufficientBalance });
    val (_req, attach) = d.escrow.cancelCost();
    val res = d.escrow.sendText(d.o1.address, "cancel_swap", attach);
    expect(res).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(res).toHaveTx({
        from: d.escrow.address,
        to: d.o1.address,
        value: fun(v: coins): bool {
            return v >= ton("5.2") && v <= ton("5.3");
        },
    });
}

// No shortfall: attaching exactly cancelCost() works, and a large attachment
// comes back as surplus instead of going to the fee wallet.
// With no shortfall, required equals the balance before the attachment, so the
// whole attachment is surplus (less the forwarding fee of its message).
get fun `test surplus comes back to the canceller`() {
    val d = cancelDeal("cs-sur", 76301, 1, ton("0.2"));
    val res = d.escrow.sendText(d.o1.address, "cancel_swap", ton("3"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(res).toHaveTx({
        from: d.escrow.address,
        to: d.o1.address,
        value: fun(v: coins): bool {
            return v > ton("2.99") && v <= ton("3");
        },
    });
    expect(res).toHaveTx({
        from: d.escrow.address,
        to: d.fw.address,
        value: fun(v: coins): bool {
            return v < ton("0.1");
        },
    });
}

get fun `test cancel with exactly cancelCost passes on a 1x1 deal`() {
    val f = setup1x1("cs-11", 76401);
    val (_req, attach) = f.escrow.cancelCost();
    expect(f.escrow.sendText(f.o1.address, "cancel_swap", attach)).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
}

get fun `test cancel with exactly cancelCost passes on a 100-asset deal`() {
    val d = cancelDeal("cs-100", 76501, 99, ton("0.05"));
    val (_req, attach) = d.escrow.cancelCost();
    expect(d.escrow.sendText(d.o1.address, "cancel_swap", attach)).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
}

// The cancel transaction's gas limit and its reserve cover the walk over the
// whole registry, not only the sends: a 100-entry registry (fast path) with
// no deposits cancels with exactly cancelCost().
get fun `test a 100-entry registry with no deposits cancels with exactly cancelCost`() {
    val d = deployActiveRegistry("cs-r100", 100, 0, 0x610000);
    val (_req, attach) = d.escrow.cancelCost();
    expect(d.escrow.sendText(d.o1.address, "cancel_swap", attach)).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(testing.getAccountBalance(d.escrow.address)).toEqual(d.escrow.storageFloor());
}

// A fully deposited 100-entry registry (fast path) models 45,000 + 9,000 x 104
// sends + 2,200 x 100 entries = 1,201,000 gas units, above what setGasLimit can
// grant. The reserve prices the capped units, so the fee wallet's sweep is at
// most the unused part of TX_GAS_LIMIT_CEILING plus DUST: gas the transaction
// could never use stays with the sides.
get fun `test a fast cancel does not reserve gas above the transaction ceiling`() {
    val d = deployActiveRegistry("cs-cap", 100, 100, 0x630000);
    val (_req, attach) = d.escrow.cancelCost();
    val fwBefore = testing.getAccountBalance(d.fw.address);
    val res = d.escrow.sendText(d.o1.address, "cancel_swap", attach);
    expect(res).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
    var used = 0;
    var i = 0;
    while (i < res.size()) {
        val r = res.at(i);
        if (r.tx.load().getAccountAddress() == d.escrow.address && r.gasUsed > used) {
            used = r.gasUsed;
        }
        i += 1;
    }
    val swept = testing.getAccountBalance(d.fw.address) - fwBefore;
    expect(
        swept <=
            calculateGasFee(BASECHAIN, TX_GAS_LIMIT_CEILING) - calculateGasFee(BASECHAIN, used) +
                DUST,
    ).toEqual(true);
    expect(testing.getAccountBalance(d.escrow.address)).toEqual(d.escrow.storageFloor());
}

// The same on the batch path: the first batch's walk runs in the initiating
// transaction.
get fun `test a 101-entry registry with no deposits cancels with exactly cancelCost`() {
    val d = deployActiveRegistry("cs-r101", 101, 0, 0x620000);
    val (_req, attach) = d.escrow.cancelCost();
    expect(d.escrow.sendText(d.o1.address, "cancel_swap", attach)).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(d.escrow.distributionProgress()).toEqual((DIST_IDLE, 101));
    expect(testing.getAccountBalance(d.escrow.address)).toEqual(d.escrow.storageFloor());
}

// A batch cancel whose first batch reaches the end of the registry without
// sending anything finalizes in the initiating transaction. The finale must
// count what that transaction already queued (the surplus and both refunds);
// otherwise it pays them out a second time and the action phase fails. Both
// sides paid their fee, so both refunds are non-zero.
get fun `test a batch cancel that finalizes in its own transaction pays each refund once`() {
    val d = deployActiveRegistry("cs-r101f", 101, 0, 0x6A0000);
    expect(
        d.escrow.sendText(d.o1.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(
        d.escrow.sendText(d.o2.address, "service_fee_owner2", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    val (_req, attach) = d.escrow.cancelCost();
    val res = d.escrow.sendText(d.o1.address, "cancel_swap", attach);
    expect(res).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(d.escrow.distributionProgress()).toEqual((DIST_IDLE, 101));
    // precondition: the chain finalized inside the initiating transaction
    expect(res).toNotHaveTx<ContinueDistribution>({ to: d.escrow.address });
    // each side's refund: its fee less half the shared costs plus half the
    // deploy remainder
    expect(res).toHaveTx({
        from: d.escrow.address,
        to: d.o1.address,
        value: fun(v: coins): bool {
            return v > ton("0.05") && v <= SERVICE_FEE;
        },
    });
    expect(res).toHaveTx({
        from: d.escrow.address,
        to: d.o2.address,
        value: fun(v: coins): bool {
            return v > ton("0.05") && v <= SERVICE_FEE;
        },
    });
    // exactly one refund each, plus each side's half of the unspent reserve
    // from the finale; owner 1 also gets its surplus back
    expect(paymentsTo(res, d.o2.address)).toEqual(2);
    expect(paymentsTo(res, d.o1.address)).toEqual(3);
    expect(testing.getAccountBalance(d.escrow.address)).toEqual(d.escrow.storageFloor());
}

// The first batch of a batch cancel sends the continue message in the same
// transaction as the refunds, so its value must be on the balance. One
// deposited NFT inside the first batch makes that batch send, and the chain
// continues.
get fun `test a 101-entry registry with one deposit cancels with exactly cancelCost`() {
    val d = deployActiveRegistry("cs-r101d", 101, 1, 0x630000);
    val (_req, attach) = d.escrow.cancelCost();
    val res = d.escrow.sendText(d.o1.address, "cancel_swap", attach);
    expect(res).toHaveAllSuccessfulTxs();
    // precondition: the first batch sent the item and a continue message
    expect(res).toHaveTx<ContinueDistribution>({ to: d.escrow.address });
    expect(d.escrow.distributionProgress()).toEqual((DIST_IDLE, 101));
    expect(readMockOwner(d.nfts.mustGet(0))).toEqual(d.o1.address);
    expect(testing.getAccountBalance(d.escrow.address)).toEqual(d.escrow.storageFloor());
}

// kick after a stalled cancel pays for finishing the returns for both sides:
// what the chain does not spend of it is split equally in the finale. Two
// identical stalled cancels, kicked with 1 and with 2 TON: owner 2 (who did
// not kick) receives exactly half of the difference.
fun o2ReceiptAfterCancelKick(tag: string, seed: int, kick: coins): coins {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, deployNft(o1, seed));
    a.set(1, deployNft(o1, seed + 1));
    var b: map<uint16, address> = [];
    b.set(0, deployNft(o2, seed + 2));
    b.set(1, deployNft(o2, seed + 3));
    cfg.nfts1 = a;
    cfg.nfts1Count = 2;
    cfg.nfts2 = b;
    cfg.nfts2Count = 2;
    val escrow = deployEscrowMidDistribution(o1, cfg, 2, DIST_CANCEL);
    val before = testing.getAccountBalance(o2.address);
    expect(escrow.sendText(o1.address, "kick", kick)).toHaveAllSuccessfulTxs();
    expect(escrow.distributionProgress().0).toEqual(DIST_IDLE);
    return testing.getAccountBalance(o2.address) - before;
}

get fun `test kick during a cancel is split equally`() {
    val one = o2ReceiptAfterCancelKick("cs-kc1", 76901, ton("1"));
    val two = o2ReceiptAfterCancelKick("cs-kc2", 77001, ton("2"));
    expect(two - one).toBeInRange(ton("0.499"), ton("0.501"));
}

// On cancel an overpaid fee comes back in full. Side 2 lists
// two NFTs and deposits one, so the deal cannot execute and stays cancellable.
get fun `test an overpaid fee is refunded on cancel`() {
    val o1 = testing.treasury("cs-fee-o1");
    val o2 = testing.treasury("cs-fee-o2");
    val fw = testing.treasury("cs-fee-fw");
    val a1 = deployNft(o1, 76601);
    val b1 = deployNft(o2, 76602);
    val b2 = deployNft(o2, 76603);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, a1);
    var b: map<uint16, address> = [];
    b.set(0, b1);
    b.set(1, b2);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = 2;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", ton("1"))).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, a1, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o2, b1, escrow.address, ton("0.2"), 1)).toHaveAllSuccessfulTxs();
    // 1 TON is far above any shortfall on this deal; the rest comes back as surplus
    val res = escrow.sendText(o1.address, "cancel_swap", ton("1"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(res).toHaveTx({
        from: escrow.address,
        to: o2.address,
        value: fun(v: coins): bool {
            return v >= ton("1");
        },
    });
}
