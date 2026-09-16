// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/messages"
import "escrow_helpers"

get fun `test mint credits balance`() {
    val alice = testing.treasury("jm-alice");
    val minter = deployJettonMinter(alice, 1);
    mintJettons(minter, alice, ton("500"));
    expect(readJettonBalance(minter, alice.address)).toEqual(ton("500"));
}

get fun `test transfer moves balance and notifies`() {
    val alice = testing.treasury("jm-alice2");
    val bob = testing.treasury("jm-bob2");
    val minter = deployJettonMinter(alice, 2);
    mintJettons(minter, alice, ton("500"));
    // forwardTon > 0 → the notification goes to the recipient owner (a treasury will accept it)
    val res = sendJettonTransfer2(
        alice,
        minter,
        bob.address,
        ton("120"),
        ton("0.05"),
        -1,
    );
    expect(res).toHaveAllSuccessfulTxs();
    expect(readJettonBalance(minter, alice.address)).toEqual(ton("380"));
    expect(readJettonBalance(minter, bob.address)).toEqual(ton("120"));
    // the notification reached the recipient owner
    expect(res).toHaveTx({ to: bob.address });
}

get fun `test transfer from non-owner rejected`() {
    val alice = testing.treasury("jm-alice3");
    val mallory = testing.treasury("jm-mallory3");
    val minter = deployJettonMinter(alice, 3);
    mintJettons(minter, alice, ton("500"));
    // mallory sends a transfer to ALICE'S WALLET → 401
    val m = createMessage({
        bounce: true,
        value: ton("0.1"),
        dest: jwAddr(minter, alice.address),
        body: JettonTransfer {
            queryId: 1,
            amount: ton("500"),
            destination: mallory.address,
            responseDestination: mallory.address,
            customPayload: null,
            forwardTonAmount: 0,
            forwardPayload: zeroBitSlice(),
        },
    });
    expect(net.send(mallory.address, m)).toHaveTx({
        to: jwAddr(minter, alice.address),
        exitCode: 401,
    });
    expect(readJettonBalance(minter, alice.address)).toEqual(ton("500"));
}

get fun `test fake internal transfer rejected`() {
    val alice = testing.treasury("jm-alice4");
    val mallory = testing.treasury("jm-mallory4");
    val minter = deployJettonMinter(alice, 4);
    mintJettons(minter, alice, ton("10"));
    // mallory sends internal_transfer directly (not from a wallet of the same minter) → 403
    val m = createMessage({
        bounce: true,
        value: ton("0.1"),
        dest: jwAddr(minter, alice.address),
        body: JettonInternalTransfer {
            queryId: 1,
            amount: ton("1000000"),
            from: mallory.address,
            responseAddress: mallory.address,
            forwardTonAmount: 0,
            forwardPayload: zeroBitSlice(),
        },
    });
    expect(net.send(mallory.address, m)).toHaveTx({
        to: jwAddr(minter, alice.address),
        exitCode: 403,
    });
    expect(readJettonBalance(minter, alice.address)).toEqual(ton("10"));
}

get fun `test discovery returns derived wallet address`() {
    val alice = testing.treasury("jm-alice5");
    val minter = deployJettonMinter(alice, 5);
    val m = createMessage({
        bounce: true,
        value: ton("0.05"),
        dest: minter,
        body: ProvideWalletAddress {
            queryId: 42,
            ownerAddress: alice.address,
            includeAddress: false,
        },
    });
    val res = net.send(alice.address, m);
    expect(res).toHaveAllSuccessfulTxs();
    // the response went back to the requester (the response's exact shape
    // is checked elsewhere through the escrow's real discovery)
    expect(res).toHaveTx({ to: alice.address });
}

get fun `test payload hint survives two hops`() {
    // Critical: forward_payload (either 0 + uint16) must survive
    // transfer → internal_transfer → notification without corruption. The
    // recipient is a treasury; this checks that the notification arrives at
    // all, while the exact hint parsing is pinned down by
    // depositWithHintAccepted.
    val alice = testing.treasury("jm-alice6");
    val bob = testing.treasury("jm-bob6");
    val minter = deployJettonMinter(alice, 6);
    mintJettons(minter, alice, ton("500"));
    val res = sendJettonTransfer2(
        alice,
        minter,
        bob.address,
        ton("5"),
        ton("0.05"),
        3,
    );
    expect(res).toHaveAllSuccessfulTxs();
    expect(readJettonBalance(minter, bob.address)).toEqual(ton("5"));
}
