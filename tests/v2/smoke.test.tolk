// GENERATED from tests/nosup/smoke.test.tolk by ts-tests/gen-v2-tests.ts — edit the source, then run npm run gen:v2.
// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowV2.gen"
import "@contracts/shared/types"
import "@contracts/v2/storage"
import "v2_helpers"

get fun `test nosup 1x1 NFT swap completes`() {
    runFullSwap(1, 1, 0, 0, ton("0.20"));
}

get fun `test nosup 60x60 batched swap completes`() {
    val escrow = runFullSwap(60, 60, ton("1"), 0, ton("0.20"));
    expect(escrow.distributionProgress()).toEqual((DIST_IDLE, 120));
}

get fun `test nosup cancel returns deposits`() {
    val o1 = testing.treasury("ns-c-o1");
    val o2 = testing.treasury("ns-c-o2");
    val fw = testing.treasury("ns-c-fw");
    var cfg = makeBasicConfig(o1, o2, fw);
    val nft = deployNft(o1, 51001);
    var n1: map<uint16, address> = [];
    n1.set(0, nft);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(sendNftToEscrow(o1, nft, escrow.address, ton("0.2"), 0)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "cancel_swap", ton("0.1"))).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(readMockOwner(nft)).toEqual(o1.address);
}

get fun `test supervisor text commands from an owner fail with 404`() {
    val o1 = testing.treasury("ns-u-o1");
    val o2 = testing.treasury("ns-u-o2");
    val fw = testing.treasury("ns-u-fw");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw));
    expect(escrow.sendText(o1.address, "emergency_withdraw_ton", ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: Errors.NotSupervisor,
    });
    expect(escrow.sendText(o1.address, "emergency_collect_assets", ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: Errors.NotSupervisor,
    });
    expect(escrow.sendText(o1.address, "emergency_return_assets", ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: Errors.NotSupervisor,
    });
}
// The nosup check that the supervisor opcodes are unknown has no V2 form:
// SwapEscrowV2 parses them. sup_basic.test.tolk checks that each, with a
// real body, fails with 404 from anyone but the supervisor.
