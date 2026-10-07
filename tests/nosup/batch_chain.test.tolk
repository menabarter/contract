// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// The self-addressed continue message buys the same gas at any gas price, and
// the batch reserve covers a chain that is limited by skipping, not sending.
import "@acton/io"
import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "nosup_helpers"

// Multiplies the basechain gas price by num/den and returns the previous
// config, which the caller restores with testing.setConfig.
fun scaleGasPrice(num: int, den: int): BlockchainConfigMap {
    val original = testing.getConfig();
    var cfg = testing.getConfig();
    var gp = cfg.getGasPrices(BASECHAIN);
    gp.flatGasPrice = (gp.flatGasPrice * num / den) as uint64;
    gp.other.gasPrice = (gp.other.gasPrice * num / den) as uint64;
    cfg.setGasPrices(gp, BASECHAIN);
    expect(testing.setConfig(cfg)).toEqual(true);
    return original;
}

fun sparseCancelCompletesAt(tag: string, num: int, den: int) {
    val f = deploySparseCancelMidState(tag, 2000, 50);
    val saved = scaleGasPrice(num, den);
    expect(f.escrow.sendText(f.o1.address, "kick", ton("1"))).toHaveAllSuccessfulTxs();
    expect(f.escrow.distributionProgress()).toEqual((DIST_IDLE, 2050));
    expect(testing.setConfig(saved)).toEqual(true);
}

get fun `test a skip-limited chain completes at 1.5x gas price`() {
    sparseCancelCompletesAt("bc-15", 3, 2);
}

get fun `test a skip-limited chain completes at 2x gas price`() {
    sparseCancelCompletesAt("bc-20", 2, 1);
}

// SKIP_GAS_UNITS_PER_ENTRY and CONTINUE_GAS_UNITS were derived from a fixture
// where every skip entry shares one address (deduplicated cells, possibly
// cheaper to load than a real registry's). With a distinct address per skip
// entry the chain still completes, at today's gas price and at 2x: measured
// worst batch 605,286 gas (the shared-address fixture measures 605,088 on the
// same code), and per-entry walk gas about 1,352 — both comfortably inside
// SKIP_GAS_UNITS_PER_ENTRY (2,200) and CONTINUE_GAS_UNITS (730,000; margin
// stays about 1.21x).
get fun `test a skip-limited chain with distinct entries completes`() {
    val f = deploySparseCancelMidState("bc-distinct-1x", 2000, 50, true);
    expect(f.escrow.sendText(f.o1.address, "kick", ton("1"))).toHaveAllSuccessfulTxs();
    expect(f.escrow.distributionProgress()).toEqual((DIST_IDLE, 2050));
}

get fun `test a skip-limited chain with distinct entries completes at 2x gas price`() {
    val f = deploySparseCancelMidState("bc-distinct-2x", 2000, 50, true);
    val saved = scaleGasPrice(2, 1);
    expect(f.escrow.sendText(f.o1.address, "kick", ton("1"))).toHaveAllSuccessfulTxs();
    expect(f.escrow.distributionProgress()).toEqual((DIST_IDLE, 2050));
    expect(testing.setConfig(saved)).toEqual(true);
}

// An ordinary 10x10 deal at 2x gas price still auto-executes, and cancel with
// exactly cancelCost() still passes.
get fun `test an ordinary deal works at 2x gas price`() {
    val saved = scaleGasPrice(2, 1);
    val escrow = runFullSwap(10, 10, 0, 0, ton("0.20"));
    expect(escrow.phase()).toEqual(PHASE_DONE);
    val f = setup1x1("bc-2x", 80001);
    val (_req, attach) = f.escrow.cancelCost();
    expect(f.escrow.sendText(f.o1.address, "cancel_swap", attach)).toHaveAllSuccessfulTxs();
    expect(testing.setConfig(saved)).toEqual(true);
}

// A batch cancel whose first batch sends an item and the continue message, at
// twice today's gas price, with exactly cancelCost() attached.
get fun `test a batch cancel with one deposit completes at 2x gas price`() {
    val d = deployActiveRegistry("bc-live", 101, 1, 0x690000);
    val saved = scaleGasPrice(2, 1);
    val (_req, attach) = d.escrow.cancelCost();
    val res = d.escrow.sendText(d.o1.address, "cancel_swap", attach);
    expect(res).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(d.escrow.distributionProgress()).toEqual((DIST_IDLE, 101));
    expect(testing.getAccountBalance(d.escrow.address)).toEqual(d.escrow.storageFloor());
    expect(testing.setConfig(saved)).toEqual(true);
}
