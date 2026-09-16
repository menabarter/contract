// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/storage"
import "@wrappers/SwapEscrow.gen"
import "escrow_helpers"

get fun `test deposit_ton1 from owner1 is credited`() {
    val o1 = testing.treasury("o1");
    val o2 = testing.treasury("o2");
    val fw = testing.treasury("fw");
    val sup = testing.treasury("sup");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));

    val res = escrow.sendText(o1.address, "deposit_ton1", ton("1.5"));
    expect(res).toHaveAllSuccessfulTxs();
    // The FULL attached value is credited, with no gas deducted.
    expect(escrow.gramState().gram1Received).toEqual(ton("1.5"));
}

get fun `test deposit_ton1 from stranger is rejected`() {
    val o1 = testing.treasury("o1-2");
    val o2 = testing.treasury("o2-2");
    val fw = testing.treasury("fw-2");
    val sup = testing.treasury("sup-2");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));

    // owner2 sends deposit_ton1 (a side-1 command) — not their command → 401,
    // the money bounces back to the sender (sendText sends with bounce: true).
    val res = escrow.sendText(o2.address, "deposit_ton1", ton("0.5"));
    expect(res).toHaveFailedTx({ to: escrow.address, exitCode: Errors.NotOwner1 });
    expect(res).toHaveBouncedTx({ from: escrow.address, to: o2.address });
    expect(escrow.gramState().gram1Received).toEqual(0);
}

// The mirror of "deposit_ton1 from stranger" above, but for side 2 — owner1
// sends the SIDE-2 COMMAND, which must also be rejected (402), not silently
// accepted.
get fun `test deposit_ton2 from owner1 is rejected`() {
    val o1 = testing.treasury("dt2-o1");
    val o2 = testing.treasury("dt2-o2");
    val fw = testing.treasury("dt2-fw");
    val sup = testing.treasury("dt2-sup");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));

    val res = escrow.sendText(o1.address, "deposit_ton2", ton("0.5"));
    expect(res).toHaveFailedTx({ to: escrow.address, exitCode: Errors.NotOwner2 });
    expect(res).toHaveBouncedTx({ from: escrow.address, to: o1.address });
    expect(escrow.gramState().gram2Received).toEqual(0);
}

get fun `test service_fee_owner2 accumulates`() {
    val o1 = testing.treasury("o1-3");
    val o2 = testing.treasury("o2-3");
    val fw = testing.treasury("fw-3");
    val sup = testing.treasury("sup-3");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));

    val res = escrow.sendText(o2.address, "service_fee_owner2", ton("0.1"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(escrow.gramState().serviceFee2).toEqual(ton("0.1"));
}

get fun `test plain transfer from owner2 credits gram2Received`() {
    val o1 = testing.treasury("o1-4");
    val o2 = testing.treasury("o2-4");
    val fw = testing.treasury("fw-4");
    val sup = testing.treasury("sup-4");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));

    // An empty body (a plain TON transfer) — the router goes straight to
    // handlePlainTransfer, bypassing handleTextCommand (see
    // onInternalMessage: in.body.isEmpty() check).
    val res = escrow.sendAny(o2.address, beginCell().endCell(), { value: ton("2"), bounce: true });
    expect(res).toHaveAllSuccessfulTxs();
    expect(escrow.gramState().gram2Received).toEqual(ton("2"));
}

get fun `test plain transfer from stranger is forwarded to fee wallet`() {
    val o1 = testing.treasury("o1-5");
    val o2 = testing.treasury("o2-5");
    val fw = testing.treasury("fw-5");
    val sup = testing.treasury("sup-5");
    val stranger = testing.treasury("stranger-5");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));

    val res = escrow.sendAny(
        stranger.address,
        beginCell().endCell(),
        { value: ton("0.7"), bounce: true },
    );
    // Fallback: a foreign transfer is forwarded to feeWallet, rather than
    // staying on the escrow's balance or being credited to either gram
    // counter. It is checked with a tolerance rather than equality to
    // ton(0.7): the forward is sent with mode 64, which carries the inbound
    // value minus this transaction's gas and the forward fee, so feeWallet
    // receives slightly less than the attached 0.7 TON.
    expect(res).toHaveAllSuccessfulTxs();
    expect(res).toHaveTx({
        from: escrow.address,
        to: fw.address,
        value: fun(v: coins): bool {
            return v > ton("0.699") && v <= ton("0.7");
        },
    });
    expect(escrow.gramState().gram1Received).toEqual(0);
    expect(escrow.gramState().gram2Received).toEqual(0);
}

// Forwarding a stranger's transfer must not cost the escrow anything. If the
// handler passed on the FULL incoming value while paying this transaction's
// compute gas from the contract's own balance, each such message would be a
// net loss — enough of them would grind the reserve below minBalanceForSwap
// (auto-execution stops firing) or below cancel_swap's `required` (throw
// 430). Mode 64 carries what is left of the inbound value after gas instead.
get fun `test stranger transfers do not drain the escrow balance`() {
    val o1 = testing.treasury("o1-5b");
    val o2 = testing.treasury("o2-5b");
    val fw = testing.treasury("fw-5b");
    val sup = testing.treasury("sup-5b");
    val stranger = testing.treasury("stranger-5b");
    var cfg = makeBasicConfig(o1, o2, fw, sup);
    cfg.gram1Amount = ton("1");
    val escrow = deployEscrow(o1, cfg);

    expect(escrow.sendText(o1.address, "deposit_ton1", ton("1"))).toHaveAllSuccessfulTxs();
    expect(
        escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();

    val before = testing.getAccountBalance(escrow.address);
    var i = 0;
    while (i < 20) {
        expect(
            escrow.sendAny(
                stranger.address,
                beginCell().endCell(),
                { value: ton("0.01"), bounce: false },
            ),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    val after = testing.getAccountBalance(escrow.address);

    // Everything the stranger sent still reaches feeWallet, and the escrow's
    // own reserve is left exactly as it was.
    expect(after).toEqual(before);
    expect(escrow.gramState().gram1Received).toEqual(ton("1"));
    expect(escrow.gramState().gram2Received).toEqual(0);
}

get fun `test plain transfer as last missing piece triggers auto-execute`() {
    val o1 = testing.treasury("o1-6");
    val o2 = testing.treasury("o2-6");
    val fw = testing.treasury("fw-6");
    val sup = testing.treasury("sup-6");
    // The shared makeBasicConfig doesn't set GRAM (0/0) — this test
    // deliberately builds the scenario "side-2 GRAM is the last missing
    // piece," so it needs the same nonzero amounts (1/2) as before.
    var cfg = makeBasicConfig(o1, o2, fw, sup);
    cfg.gram1Amount = ton("1");
    cfg.gram2Amount = ton("2");
    val escrow = deployEscrow(o1, cfg);

    // handlePlainTransfer calls tryAutoExecute itself (see the comment above
    // handlePlainTransfer). Checked here:
    // everything except side-2 GRAM is deposited via ordinary text
    // commands; the last missing piece — gram2 — arrives as an EMPTY body
    // (an ordinary TON transfer) from owner2.
    expect(
        escrow.sendText(o1.address, "deposit_ton1", ton("1") + ton("0.05")),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();

    // While side-2 GRAM has not arrived yet — auto-execution has not fired.
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);

    // An empty body from owner2 — the router goes to handlePlainTransfer,
    // bypassing handleTextCommand (see onInternalMessage: in.body.isEmpty() check).
    val res = escrow.sendAny(
        o2.address,
        beginCell().endCell(),
        { value: ton("2") + ton("0.05"), bounce: true },
    );
    expect(res).toHaveAllSuccessfulTxs();
    // The auto-cascade fired DIRECTLY on the plain transfer, with no
    // separate execute_swap command.
    expect(escrow.phase()).toEqual(PHASE_DONE);
}
