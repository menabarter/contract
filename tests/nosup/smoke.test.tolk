// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "@contracts/shared/types"
import "nosup_helpers"

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

get fun `test nosup former supervisor text commands are unknown`() {
    val o1 = testing.treasury("ns-u-o1");
    val o2 = testing.treasury("ns-u-o2");
    val fw = testing.treasury("ns-u-fw");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw));
    expect(escrow.sendText(o1.address, "emergency_withdraw_ton", ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: 130,
    });
    expect(escrow.sendText(o1.address, "emergency_collect_assets", ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: 130,
    });
    expect(escrow.sendText(o1.address, "emergency_return_assets", ton("0.1"))).toHaveFailedTx({
        to: escrow.address,
        exitCode: 130,
    });
}

get fun `test nosup former supervisor binary opcodes are unknown`() {
    val o1 = testing.treasury("ns-b-o1");
    val o2 = testing.treasury("ns-b-o2");
    val fw = testing.treasury("ns-b-fw");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw));
    var op = 0x6d5f0001;
    while (op <= 0x6d5f0005) {
        if (op != 0x6d5f0004) {
            val body = beginCell()
                .storeUint(op, 32)
                .storeUint(0, 64)
                .storeUint(0, 256)
                .storeUint(
                    0,
                    11,
                )
                .endCell();
            val m = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                value: ton("0.05"),
                dest: escrow.address,
                body,
            });
            expect(net.send(o1.address, m)).toHaveFailedTx({
                to: escrow.address,
                exitCode: Errors.UnknownOp,
            });
        }
        op += 1;
    }
}
