// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/messages"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "@contracts/shared/types"
import "nosup_helpers"

// JdFixture/tagged/jdSetup live in nosup_helpers.tolk — reused by
// tests/nosup/jetton_cancel.test.tolk without duplicating the fixture.

get fun `test depositWithHintAccepted`() {
    val f = jdSetup("jt1", 21);
    val res = sendJettonTransfer2(
        f.o1,
        f.minter,
        f.escrow.address,
        ton("100"),
        ton("0.05"),
        0,
    );
    expect(res).toHaveAllSuccessfulTxs();
    val counts = f.escrow.receivedCounts();
    expect(counts.0).toEqual(1);
    expect(counts.1).toEqual(0);
    // the tokens reached the escrow's wallet
    expect(readJettonBalance(f.minter, f.escrow.address)).toEqual(ton("100"));
}

get fun `test depositWithoutHintFallbackMatches`() {
    val f = jdSetup("jt2", 22);
    val res = sendJettonTransfer2(
        f.o1,
        f.minter,
        f.escrow.address,
        ton("100"),
        ton("0.05"),
        -1,
    );
    expect(res).toHaveAllSuccessfulTxs();
    expect(f.escrow.receivedCounts().0).toEqual(1);
}

get fun `test forgedHintCaughtBySenderCheck`() {
    // Index spoofing: owner2 deposits THEIR OWN 50, pointing at index 0
    // (owner1's asset of 100). The depositor check catches this → fallback
    // finds the CORRECT asset (index 1) → that is the one marked.
    val f = jdSetup("jt3", 23);
    val res = sendJettonTransfer2(
        f.o2,
        f.minter,
        f.escrow.address,
        ton("50"),
        ton("0.05"),
        0,
    );
    expect(res).toHaveAllSuccessfulTxs();
    val counts = f.escrow.receivedCounts();
    expect(counts.0).toEqual(0); // side-1 asset NOT marked
    expect(counts.1).toEqual(1); // side-2 asset marked
}

get fun `test hintAtNftAssetFallsBack`() {
    // The hint points at an NFT asset → the kind check rejects it → fallback finds the jetton.
    val o1 = testing.treasury("jt4-o1");
    val o2 = testing.treasury("jt4-o2");
    val fw = testing.treasury("jt4-fw");
    val minter = deployJettonMinter(o1, 24);
    mintJettons(minter, o1, ton("500"));
    val nft = deployNft(o1, 2401);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, nft);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter,
            ownerSide: 1,
            amount: ton("100"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 1;
    val escrow = deployEscrow(o1, cfg);
    // the jetton has index 1 in assets (after the NFT); hint 0 → that's the NFT → fallback
    val res = sendJettonTransfer2(
        o1,
        minter,
        escrow.address,
        ton("100"),
        ton("0.05"),
        0,
    );
    expect(res).toHaveAllSuccessfulTxs();
    expect(escrow.receivedCounts().0).toEqual(1);
}

get fun `test underpaymentFullyReturned`() {
    val f = jdSetup("jt5", 25);
    val res = sendJettonTransfer2(
        f.o1,
        f.minter,
        f.escrow.address,
        ton("40"),
        ton("0.05"),
        0,
    );
    expect(res).toHaveAllSuccessfulTxs();                                  // graceful, no throw
    expect(f.escrow.receivedCounts().0).toEqual(0);                        // not accepted
    expect(readJettonBalance(f.minter, f.o1.address)).toEqual(ton("500")); // everything returned
    expect(readJettonBalance(f.minter, f.escrow.address)).toEqual(0);
}

get fun `test overpaymentAcceptedExcessReturned`() {
    val f = jdSetup("jt6", 26);
    val res = sendJettonTransfer2(
        f.o1,
        f.minter,
        f.escrow.address,
        ton("130"),
        ton("0.08"),
        0,
    );
    expect(res).toHaveAllSuccessfulTxs();
    expect(f.escrow.receivedCounts().0).toEqual(1);                            // accepted
    expect(readJettonBalance(f.minter, f.escrow.address)).toEqual(ton("100")); // exactly amount
    expect(readJettonBalance(f.minter, f.o1.address)).toEqual(
        ton("400"),
    );                                                                         // 500-130+30, the excess was returned
}

// Without a hint, no slot matches the overpaid amount exactly, so the second
// pass of the fallback (any slot of this wallet and depositor) must find the
// slot: the deposit is accepted and only the excess comes back, rather than
// the whole transfer being returned as a foreign jetton.
get fun `test overpaymentWithoutHintAcceptedExcessReturned`() {
    val f = jdSetup("jt6u", 97);
    val res = sendJettonTransfer2(
        f.o1,
        f.minter,
        f.escrow.address,
        ton("130"),
        ton("0.08"),
        -1,
    );
    expect(res).toHaveAllSuccessfulTxs();
    expect(f.escrow.receivedCounts().0).toEqual(1);
    expect(readJettonBalance(f.minter, f.escrow.address)).toEqual(ton("100"));
    expect(readJettonBalance(f.minter, f.o1.address)).toEqual(ton("400"));
}

// The excess refund must carry a NON-ASSET queryId. It is sent with
// BounceMode.Only256BitsOfBody, so a refund built with queryId 0 would, if it
// bounced, be read by onBouncedMessage as a bounce of asset index 0 —
// marking that asset claimable even though it was already delivered.
get fun `test overpayment refund carries a non-asset sentinel queryId`() {
    val f = jdSetup("jt6s", 96);
    val res = sendJettonTransfer2(
        f.o1,
        f.minter,
        f.escrow.address,
        ton("130"),
        ton("0.08"),
        0,
    );
    expect(res).toHaveAllSuccessfulTxs();
    expect(f.escrow.receivedCounts().0).toEqual(1);

    // The only JettonTransfer the escrow emits here is the excess refund.
    expect(res).toHaveTx({
        from: f.escrow.address,
        body: fun(b: cell): bool {
            val m = JettonTransfer.fromCell(b);
            return m.queryId == QUERY_ID_NON_ASSET;
        },
    });
}

get fun `test overpaymentWithTinyGasKeepsExcessForRescue`() {
    // value < RETURN_TRANSFER_VALUE: the asset is accepted, the excess stays
    // on the escrow's wallet (a documented fallback)
    val f = jdSetup("jt7", 27);
    val res = sendJettonTransfer2(
        f.o1,
        f.minter,
        f.escrow.address,
        ton("130"),
        ton("0.02"),
        0,
    );
    expect(res).toHaveAllSuccessfulTxs();
    expect(f.escrow.receivedCounts().0).toEqual(1);
    expect(readJettonBalance(f.minter, f.escrow.address)).toEqual(ton("130")); // the excess stayed
}

get fun `test duplicateDepositReturned`() {
    val f = jdSetup("jt8", 28);
    expect(
        sendJettonTransfer2(
            f.o1,
            f.minter,
            f.escrow.address,
            ton("100"),
            ton("0.05"),
            0,
        ),
    ).toHaveAllSuccessfulTxs();
    // a repeat "deposit" from the same side — the asset is already received → returned in full
    val res = sendJettonTransfer2(
        f.o1,
        f.minter,
        f.escrow.address,
        ton("100"),
        ton("0.05"),
        0,
    );
    expect(res).toHaveAllSuccessfulTxs();
    // The arithmetic "500-100-100+100" itself works out to 400
    // (500-100=400; 400-100=300; 300+100=400). Duplicate deposit: the first
    // transfer (100) is debited from o1's balance and stays at the escrow
    // (accepted); the second (100, a duplicate) is also debited from o1, but
    // is returned in full back to the escrow → net 0 for the second
    // transfer. Result: 500-100=400.
    expect(readJettonBalance(f.minter, f.o1.address)).toEqual(ton("400"));
    expect(readJettonBalance(f.minter, f.escrow.address)).toEqual(ton("100"));
    expect(f.escrow.receivedCounts().0).toEqual(1); // the counter did not double-count
}

get fun `test foreignJettonReturned`() {
    // a jetton from a FOREIGN minter, not part of the deal → returned
    val f = jdSetup("jt9", 29);
    val alien = deployJettonMinter(f.o1, 291);
    mintJettons(alien, f.o1, ton("77"));
    val res = sendJettonTransfer2(
        f.o1,
        alien,
        f.escrow.address,
        ton("77"),
        ton("0.05"),
        0,
    );
    expect(res).toHaveAllSuccessfulTxs();
    expect(readJettonBalance(alien, f.o1.address)).toEqual(ton("77")); // returned
    expect(f.escrow.receivedCounts().0).toEqual(0);
}

get fun `test fakeNotificationHarmless`() {
    // A fake notification sent directly by an outsider (not from a jetton
    // wallet): matchJettonAsset won't find a match (jettonWallet != sender)
    // → the "return" is a transfer to the sender's address, where there are
    // no real tokens; state is untouched
    val f = jdSetup("jt10", 30);
    val mallory = testing.treasury("jt10-mallory");
    val fake = createMessage({
        bounce: true,
        value: ton("0.1"),
        dest: f.escrow.address,
        body: JettonTransferNotification {
            queryId: 1,
            amount: ton("100"),
            sender: f.o1.address, // masquerading as the side-1 depositor
            forwardPayload: zeroBitSlice(),
        },
    });
    expect(net.send(mallory.address, fake)).toHaveAllSuccessfulTxs();
    expect(f.escrow.receivedCounts().0).toEqual(0); // nothing was credited
}

get fun `test lateDepositAfterCancelReturned`() {
    // A "late transfer": after cancel (a terminal phase) the deposit is returned
    val f = jdSetup("jt11", 31);
    expect(
        f.escrow.sendText(f.o1.address, "cancel_swap", ton("0.1")),
    ).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
    val res = sendJettonTransfer2(
        f.o1,
        f.minter,
        f.escrow.address,
        ton("100"),
        ton("0.05"),
        0,
    );
    expect(res).toHaveAllSuccessfulTxs();
    expect(readJettonBalance(f.minter, f.o1.address)).toEqual(ton("500"));
    expect(readJettonBalance(f.minter, f.escrow.address)).toEqual(0);
}

get fun `test unresolvedMinterDepositReturned`() {
    // A per-asset gate: a deposit of a jetton whose minter has NOT resolved
    // yet is returned. A two-minter deal: A (a mock, resolves), B (stays
    // silent). Sending B's jetton is not possible without B's wallet;
    // instead, we send a jetton of the RESOLVING minter A, but that would
    // require the escrow to be deployed with the A-asset still null: forcing
    // that via a fake notification from the future wallet's address is not
    // possible. The real reachable case: a deal with a silent minter B and a
    // jetton A: asset A resolves, B does not → phase SETUP; a deposit of A
    // is accepted already in SETUP (the per-asset gate), which is what is
    // checked here — the positive half of the rule.
    val o1 = testing.treasury("jt12-o1");
    val o2 = testing.treasury("jt12-o2");
    val fw = testing.treasury("jt12-fw");
    val minterA = deployJettonMinter(o1, 321);
    val dead = testing.treasury("jt12-dead");
    mintJettons(minterA, o1, ton("500"));
    var cfg = makeBasicConfig(o1, o2, fw);
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter: minterA,
            ownerSide: 1,
            amount: ton("100"),
        },
    );
    js.set(
        1,
        JettonCfg {
            minter: dead.address,
            ownerSide: 2,
            amount: ton("5"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 2;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.phase()).toEqual(PHASE_SETUP); // dead never responded
    val res = sendJettonTransfer2(
        o1,
        minterA,
        escrow.address,
        ton("100"),
        ton("0.05"),
        0,
    );
    expect(res).toHaveAllSuccessfulTxs();
    expect(
        escrow.receivedCounts().0,
    ).toEqual(1);                                // accepted while still in SETUP, per the per-asset gate
    expect(escrow.phase()).toEqual(PHASE_SETUP); // auto-execution has not started
}

get fun `test overpaymentOnFinalDepositStillExecutes`() {
    // The excess refund (mode 0, 0.03 from the
    // balance) is queued BEFORE tryAutoExecute; if this same deposit
    // COMPLETES the deal, executeSwap must subtract the already-committed
    // 0.03 (committedOut), otherwise the sum of mode-0 sends would exceed
    // the balance → an action failure → the deposit would roll back.
    val f = jdSetup("jt13", 33);
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
    // the deal-completing side-2 deposit — with an OVERPAYMENT of 10 (60 for an asset of 50)
    val last = sendJettonTransfer2(
        f.o2,
        f.minter,
        f.escrow.address,
        ton("60"),
        ton("0.2"),
        1,
    );
    expect(last).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_DONE);
    // money: o1 = 500-100+50 = 450; o2 = 500-60+10(excess)+100 = 550; escrow is empty
    expect(readJettonBalance(f.minter, f.o1.address)).toEqual(ton("450"));
    expect(readJettonBalance(f.minter, f.o2.address)).toEqual(ton("550"));
    expect(readJettonBalance(f.minter, f.escrow.address)).toEqual(0);
}

get fun `test fallbackPrefersExactAmountSlot`() {
    // ONE side has two assets from the same
    // minter with different amounts (100 and 30). A deposit of 30 WITHOUT a
    // hint must mark the 30 slot (an exact amount match), not be rejected as
    // "underpayment" of the 100 slot.
    val o1 = testing.treasury("jt14-o1");
    val o2 = testing.treasury("jt14-o2");
    val fw = testing.treasury("jt14-fw");
    val minter = deployJettonMinter(o1, 34);
    mintJettons(minter, o1, ton("500"));
    var cfg = makeBasicConfig(o1, o2, fw);
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter,
            ownerSide: 1,
            amount: ton("100"),
        },
    );
    js.set(
        1,
        JettonCfg {
            minter,
            ownerSide: 1,
            amount: ton("30"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 2;
    val escrow = deployEscrow(o1, cfg);
    expect(
        sendJettonTransfer2(
            o1,
            minter,
            escrow.address,
            ton("30"),
            ton("0.05"),
            -1,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.receivedCounts().0).toEqual(1); // accepted, not returned
    expect(readJettonBalance(minter, escrow.address)).toEqual(ton("30"));
    expect(
        sendJettonTransfer2(
            o1,
            minter,
            escrow.address,
            ton("100"),
            ton("0.05"),
            -1,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.receivedCounts().0).toEqual(2);
    expect(readJettonBalance(minter, escrow.address)).toEqual(ton("130"));
}

// A jetton transfer carrying an arbitrary forward payload.
fun sendJettonWithPayload(
    owner: Treasury,
    minter: address,
    destOwner: address,
    amount: coins,
    forwardTon: coins,
    payload: slice,
): SendResultList {
    val m = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        value: forwardTon + ton("0.08"),
        dest: jwAddr(minter, owner.address),
        body: JettonTransfer {
            queryId: 7,
            amount,
            destination: destOwner,
            responseDestination: owner.address,
            customPayload: null,
            forwardTonAmount: forwardTon,
            forwardPayload: payload,
        },
    });
    return net.send(owner.address, m);
}

// A minter's take_wallet_address that arrives after the deal was cancelled in
// SETUP must be ignored: resolving the last pending minter would otherwise
// switch the cancelled deal back to ACTIVE.
get fun `test a late wallet address after cancel leaves the deal cancelled`() {
    val d = setupWithSilentMinter("jt15", 35, false);
    val (_req, attach) = d.escrow.cancelCost();
    expect(d.escrow.sendText(d.o1.address, "cancel_swap", attach)).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
    val late = createMessage({
        bounce: BounceMode.NoBounce,
        value: ton("0.05"),
        dest: d.escrow.address,
        body: TakeWalletAddress {
            queryId: 0,
            walletAddress: d.silent.address,
            rest: beginCell().storeUint(0, 1).endCell().beginParse(),
        },
    });
    net.send(d.silent.address, late);
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(d.escrow.pendingWalletsLeft()).toEqual(1);
}

// An unhinted deposit walks the registry past a slot whose minter has not
// answered yet; that slot must simply not match, and the deposit must land
// in its own slot.
get fun `test an unhinted deposit walks past an unresolved slot`() {
    val d = setupWithSilentMinter("jt16", 36, true);
    expect(
        sendJettonTransfer2(
            d.o1,
            d.minter,
            d.escrow.address,
            ton("100"),
            ton("0.05"),
            -1,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.receivedCounts().0).toEqual(1);
    expect(readJettonBalance(d.minter, d.escrow.address)).toEqual(ton("100"));
}

// A payload whose either-bit says "in a reference" carries no hint, even when
// 16 more bits follow inline. Read as a hint here, those bits would point the
// 30-jetton deposit at the 100-jetton slot and return it as an underpayment;
// without a hint the exact-amount pass finds the 30 slot.
get fun `test a reference payload carries no hint`() {
    val o1 = testing.treasury("jt17-o1");
    val o2 = testing.treasury("jt17-o2");
    val fw = testing.treasury("jt17-fw");
    val minter = deployJettonMinter(o1, 37);
    mintJettons(minter, o1, ton("500"));
    var cfg = makeBasicConfig(o1, o2, fw);
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter,
            ownerSide: 1,
            amount: ton("100"),
        },
    );
    js.set(
        1,
        JettonCfg {
            minter,
            ownerSide: 1,
            amount: ton("30"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 2;
    val escrow = deployEscrow(o1, cfg);
    val payload = beginCell().storeUint(1, 1).storeUint(0, 16).endCell().beginParse();
    expect(
        sendJettonWithPayload(
            o1,
            minter,
            escrow.address,
            ton("30"),
            ton("0.05"),
            payload,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.receivedCounts().0).toEqual(1);
    expect(readJettonBalance(minter, escrow.address)).toEqual(ton("30"));
}

// A return costs RETURN_TRANSFER_VALUE; with less attached it is not
// attempted, and an underpaid deposit's tokens stay in the escrow's wallet
// (the documented risk) instead of being sent back on too little value.
get fun `test an underpaid deposit with too little value is not returned`() {
    val f = jdSetup("jt18", 38);
    expect(
        sendJettonTransfer2(
            f.o1,
            f.minter,
            f.escrow.address,
            ton("40"),
            ton("0.02"),
            0,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(f.escrow.receivedCounts().0).toEqual(0);
    expect(readJettonBalance(f.minter, f.escrow.address)).toEqual(ton("40"));
}
