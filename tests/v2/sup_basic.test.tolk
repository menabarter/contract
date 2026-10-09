// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// SwapEscrowV2's supervisor commands that do not depend on the deal's state.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/messages"
import "@wrappers/SwapEscrowV2.gen"
import "@contracts/shared/types"
import "@contracts/v2/storage"
import "v2_helpers"

fun supAddr(): address {
    return testing.treasury("v2-sup").address;
}

get fun `test the supervisor getter names the deal's supervisor`() {
    val f = setup1x1("sb-get", 79001);
    expect(net.runGetMethod<address>(f.escrow.address, "supervisor")).toEqual(supAddr());
}

get fun `test supervisor commands from anyone else fail with 404`() {
    val f = setup1x1("sb-404", 79011);
    val r1 = f.escrow.sendText(f.o1.address, "emergency_withdraw_ton", ton("0.1"));
    expect(r1).toHaveTx({ to: f.escrow.address, exitCode: 404 });
    val r2 = f.escrow.sendText(f.o2.address, "emergency_return_assets", ton("0.1"));
    expect(r2).toHaveTx({ to: f.escrow.address, exitCode: 404 });
    val r3 = f.escrow.sendText(f.o1.address, "emergency_collect_assets", ton("0.1"));
    expect(r3).toHaveTx({ to: f.escrow.address, exitCode: 404 });
    val r4 = net.send(
        f.o1.address,
        createMessage({
            bounce: BounceMode.Only256BitsOfBody,
            value: ton("0.1"),
            dest: f.escrow.address,
            body: RescueNft { nftAddr: f.nft1 },
        }),
    );
    expect(r4).toHaveTx({ to: f.escrow.address, exitCode: 404 });
    val r5 = net.send(
        f.o2.address,
        createMessage({
            bounce: BounceMode.Only256BitsOfBody,
            value: ton("0.1"),
            dest: f.escrow.address,
            body: RescueJetton {
                queryId: 0,
                jettonWallet: f.nft2,
                amount: 1,
            },
        }),
    );
    expect(r5).toHaveTx({ to: f.escrow.address, exitCode: 404 });
    val r6 = net.send(
        f.o1.address,
        createMessage({
            bounce: BounceMode.Only256BitsOfBody,
            value: ton("0.1"),
            dest: f.escrow.address,
            body: SupervisorAssetReceived { assetAddr: f.nft1 },
        }),
    );
    expect(r6).toHaveTx({ to: f.escrow.address, exitCode: 404 });
    val r7 = net.send(
        f.o1.address,
        createMessage({
            bounce: BounceMode.Only256BitsOfBody,
            value: ton("0.1"),
            dest: f.escrow.address,
            body: ForceDeliver {
                queryId: 0,
                assetIndex: 0,
                fallback: false,
            },
        }),
    );
    expect(r7).toHaveTx({ to: f.escrow.address, exitCode: 404 });
    expect(f.escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(readMockOwner(f.nft1)).toEqual(f.escrow.address);
}

get fun `test emergency_withdraw sweeps the balance to the supervisor in any phase`() {
    val f = setup1x1("sb-wd", 79021);
    val res = f.escrow.sendText(supAddr(), "emergency_withdraw_ton", ton("0.05"));
    expect(res).toHaveTx({ from: f.escrow.address, to: supAddr() });
    expect(testing.getAccountBalance(f.escrow.address)).toEqual(0);
}

get fun `test rescue_nft sends a named NFT to the supervisor`() {
    val f = setup1x1("sb-rn", 79031);
    // nft1 was deposited by setup1x1: the escrow owns it.
    net.send(
        supAddr(),
        createMessage({
            bounce: BounceMode.Only256BitsOfBody,
            value: ton("0.1"),
            dest: f.escrow.address,
            body: RescueNft { nftAddr: f.nft1 },
        }),
    );
    expect(readMockOwner(f.nft1)).toEqual(supAddr());
}

get fun `test supervisor_asset_received registers an NFT in the rescue registry`() {
    val f = setup1x1("sb-ar", 79041);
    val foreign = deployNft(f.o1, 79042);
    val res = net.send(
        supAddr(),
        createMessage({
            bounce: BounceMode.Only256BitsOfBody,
            value: ton("0.05"),
            dest: f.escrow.address,
            body: SupervisorAssetReceived { assetAddr: foreign },
        }),
    );
    expect(res).toHaveAllSuccessfulTxs();
}
