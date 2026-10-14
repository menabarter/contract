// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// TEP-89 wallet discovery in SETUP.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/messages"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "@contracts/shared/types"
import "nosup_helpers"

// Config: 1 side-1 jetton for 100 tokens, no NFT/GRAM.
fun oneJettonCfg(
    o1: Treasury,
    o2: Treasury,
    fw: Treasury,
    minter: address,
): EscrowConfig {
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
    cfg.jettons = js;
    cfg.jettonsCount = 1;
    return cfg;
}

get fun `test discoveryResolvesAndActivates`() {
    val o1 = testing.treasury("jd-o1");
    val o2 = testing.treasury("jd-o2");
    val fw = testing.treasury("jd-fw");
    val minter = deployJettonMinter(o1, 11);
    val escrow = deployEscrow(o1, oneJettonCfg(o1, o2, fw, minter));
    // the mock minter responded within the same deploy cascade → already ACTIVE
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(escrow.pendingWalletsLeft()).toEqual(0);
    // the resolved address = the escrow's wallet at this minter
    expect(escrow.assetJettonWallet(0)!).toEqual(jwAddr(minter, escrow.address));
}

get fun `test silentMinterKeepsSetupAndCancelRefunds`() {
    val o1 = testing.treasury("jd2-o1");
    val o2 = testing.treasury("jd2-o2");
    val fw = testing.treasury("jd2-fw");
    // a "silent minter": an address with no code — provide bounces, no resolve arrives
    val dead = testing.treasury("jd2-dead-addr"); // just an address; provide goes to a treasury wallet that won't respond with take
    val escrow = deployEscrow(o1, oneJettonCfg(o1, o2, fw, dead.address));
    expect(escrow.phase()).toEqual(PHASE_SETUP);
    expect(escrow.pendingWalletsLeft()).toEqual(1);

    // a GRAM deposit in SETUP is ACCEPTED
    expect(
        escrow.sendText(o1.address, "deposit_ton1", ton("1")),
    ).toHaveAllSuccessfulTxs();

    // cancel from SETUP: GRAM is returned, phase CANCELLED
    val res = escrow.sendText(o1.address, "cancel_swap", ton("0.1"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(res).toHaveTx({
        to: o1.address,
        value: fun(v: coins): bool {
            return v >= ton("0.99");
        },
    });
}

get fun `test takeFromNonMinterIgnored`() {
    val o1 = testing.treasury("jd3-o1");
    val o2 = testing.treasury("jd3-o2");
    val fw = testing.treasury("jd3-fw");
    val dead = testing.treasury("jd3-dead");
    val mallory = testing.treasury("jd3-mallory");
    val escrow = deployEscrow(o1, oneJettonCfg(o1, o2, fw, dead.address));
    expect(escrow.phase()).toEqual(PHASE_SETUP);
    // a forged take from mallory: claiming a resolve to mallory's wallet
    val forged = createMessage({
        bounce: true,
        value: ton("0.05"),
        dest: escrow.address,
        body: TakeWalletAddress {
            queryId: 0,
            walletAddress: mallory.address,
            rest: zeroBitSlice(),
        },
    });
    expect(net.send(mallory.address, forged)).toHaveAllSuccessfulTxs(); // ignored, not a throw
    expect(escrow.phase()).toEqual(PHASE_SETUP);                        // nothing was resolved
    expect(escrow.pendingWalletsLeft()).toEqual(1);
    expect(escrow.assetJettonWallet(0)).toEqual(null);
}

get fun `test repeatedTakeIsIdempotent`() {
    val o1 = testing.treasury("jd4-o1");
    val o2 = testing.treasury("jd4-o2");
    val fw = testing.treasury("jd4-fw");
    val minter = deployJettonMinter(o1, 14);
    val escrow = deployEscrow(o1, oneJettonCfg(o1, o2, fw, minter));
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    // a repeat deploy_fee → the minter responds again → resolvedAny ==
    // false, the phase is already ACTIVE → ignored by the phase gate; does
    // not fail, pending does not go negative
    expect(
        escrow.sendText(o1.address, "deploy_fee", ton("0.1")),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(escrow.pendingWalletsLeft()).toEqual(0);
}

get fun `test sameMinterBothSidesResolvesBothAssets`() {
    val o1 = testing.treasury("jd5-o1");
    val o2 = testing.treasury("jd5-o2");
    val fw = testing.treasury("jd5-fw");
    val minter = deployJettonMinter(o1, 15);
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
            ownerSide: 2,
            amount: ton("50"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 2;
    val escrow = deployEscrow(o1, cfg);
    // one minter → pendingWallets was 1 → a single take resolved BOTH assets
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(escrow.assetJettonWallet(0)!).toEqual(jwAddr(minter, escrow.address));
    expect(escrow.assetJettonWallet(1)!).toEqual(jwAddr(minter, escrow.address));
}

get fun `test nftDepositAcceptedDuringSetup`() {
    val o1 = testing.treasury("jd6-o1");
    val o2 = testing.treasury("jd6-o2");
    val fw = testing.treasury("jd6-fw");
    val dead = testing.treasury("jd6-dead");
    val nft = deployNft(o1, 6001);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, nft);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter: dead.address,
            ownerSide: 2,
            amount: ton("5"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.phase()).toEqual(PHASE_SETUP);
    // an NFT is accepted while in SETUP (unchanged from before)
    expect(sendNftToEscrow(o1, nft, escrow.address, ton("0.05"))).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nft)).toEqual(escrow.address);
    val counts = escrow.receivedCounts();
    expect(counts.0).toEqual(1);
}

// A deploy_fee retry in SETUP sends provide_wallet_address SEND_MODE_REGULAR
// from the escrow's BALANCE. Without a value gate, a third party (not a side
// of the deal) could use cheap (0.001-0.01 TON) deploy_fee calls on a stuck
// SETUP (a silent minter) to repeatedly trigger the provide distribution at
// the escrow's expense, draining the sides' GRAM deposits toward a dead
// minter. So handleDeployFee counts unresolvedCount of unique unresolved
// minters AND gates on
// `assert (value >= perMinterProvideValue * unresolvedCount)` BEFORE
// distribution — throw 430 (InsufficientBalance), sending nothing.
get fun `test deployFeeRetryGatedByValueRejectsUnderfundedGriefing`() {
    val o1 = testing.treasury("f2-o1");
    val o2 = testing.treasury("f2-o2");
    val fw = testing.treasury("f2-fw");
    val mallory = testing.treasury("f2-mallory"); // an outsider, not a side of the deal
    val dead = testing.treasury("f2-dead");       // a "silent minter"
    val escrow = deployEscrow(o1, oneJettonCfg(o1, o2, fw, dead.address));
    expect(escrow.phase()).toEqual(PHASE_SETUP);
    expect(escrow.pendingWalletsLeft()).toEqual(1);

    // The owner deposits GRAM — this is what griefing would try to drain.
    expect(
        escrow.sendText(o1.address, "deposit_ton1", ton("1")),
    ).toHaveAllSuccessfulTxs();

    val balBefore = testing.getAccountBalance(escrow.address);

    // A griefing attempt: a cheap deploy_fee from an outsider with a value
    // BELOW the required perMinterProvideValue (~0.0206 TON for 1
    // unresolved minter at 1 total asset) — MUST fail with 430, sending
    // nothing.
    val res = escrow.sendText(mallory.address, "deploy_fee", ton("0.01"));
    expect(res).toHaveFailedTx({ to: escrow.address, exitCode: Errors.InsufficientBalance });
    expect(escrow.phase()).toEqual(PHASE_SETUP);
    expect(escrow.pendingWalletsLeft()).toEqual(1);

    // The escrow's balance could NOT have shrunk from a provide
    // distribution (the assert failed BEFORE sending) — the narrow window
    // (0.001 TON) clearly distinguishes "nothing sent" from "a provide sent
    // for ~0.02 TON" (the ungated case).
    val balAfter = testing.getAccountBalance(escrow.address);
    expect(balAfter >= balBefore - ton("0.001")).toEqual(true);

    // A legitimate retry with SUFFICIENT value still works — provide goes
    // out (the repeatedTakeIsIdempotent path is not broken by the value gate).
    expect(
        escrow.sendText(mallory.address, "deploy_fee", ton("0.1")),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_SETUP); // the minter is still silent
    expect(escrow.pendingWalletsLeft()).toEqual(1);

    // cancel returns the owner's GRAM IN FULL — proving the deposit was NOT
    // drained toward the dead minter during the griefing attempts.
    val cancelRes = escrow.sendText(o1.address, "cancel_swap", ton("0.1"));
    expect(cancelRes).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(cancelRes).toHaveTx({
        to: o1.address,
        value: fun(v: coins): bool {
            return v >= ton("0.99");
        },
    });
}
