// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "@contracts/shared/types"
import "nosup_helpers"

get fun `test deploy sets phase ACTIVE and stores swap params`() {
    val deployer = testing.treasury("deployer");
    val o2 = testing.treasury("owner2");
    val fw = testing.treasury("fee");

    val cfg = makeBasicConfig(deployer, o2, fw);
    val escrow = deployEscrow(deployer, cfg);

    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(escrow.swapId()).toEqual(1);
}

get fun `test unknown text command bounces with 130`() {
    val deployer = testing.treasury("deployer-2");
    val o2 = testing.treasury("owner2-2");
    val fw = testing.treasury("fee-2");
    val escrow = deployEscrow(
        deployer,
        makeBasicConfig(deployer, o2, fw),
    );

    val res = escrow.sendText(deployer.address, "bogus_command", ton("0.1"));
    expect(res).toHaveFailedTx({ to: escrow.address, exitCode: 130 });
}

// A routing regression check: a KNOWN command must reach ITS OWN handler,
// NOT fall through to the generic throw 130. Catches breakage in text
// command encoding/comparison (e.g. storeString-as-ref), which would give a
// false green on the "unknown -> 130" test.
// handleExecuteSwap is a real handler (not a stub) — with an empty deal
// config (makeBasicConfig: 0 NFT on each side, but gram1Amount=1
// TON/gram2Amount=2 TON), the very first require inside it —
// `g.gram1Received >= g.gram1Amount` — fails with Errors.NotEnoughTon1
// (420), since deployer (=owner1) deposited nothing.
get fun `test known command routes to its handler stub not 130`() {
    val deployer = testing.treasury("deployer-3");
    val o2 = testing.treasury("owner2-3");
    val fw = testing.treasury("fee-3");
    // The shared makeBasicConfig doesn't set GRAM (0/0) — a NONZERO
    // gram1Amount is needed here, so execute_swap fails specifically on
    // NotEnoughTon1 (420), rather than falling through further down the
    // chain of gates (see handleExecuteSwap).
    var cfg = makeBasicConfig(deployer, o2, fw);
    cfg.gram1Amount = ton("1");
    cfg.gram2Amount = ton("2");
    val escrow = deployEscrow(deployer, cfg);

    val res = escrow.sendText(deployer.address, "execute_swap", ton("0.1"));
    expect(res).toHaveFailedTx({ to: escrow.address, exitCode: Errors.NotEnoughTon1 });
}
