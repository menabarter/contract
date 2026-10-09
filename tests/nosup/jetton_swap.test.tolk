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

// A full swap: NFT(o1) + 100 jettons(o1) ↔ 50 jettons(o2) + 1 GRAM(o2).
get fun `test mixed NFT+jetton swap auto-executes`() {
    val o1 = testing.treasury("js1-o1");
    val o2 = testing.treasury("js1-o2");
    val fw = testing.treasury("js1-fw");
    val minter = deployJettonMinter(o1, 41);
    mintJettons(minter, o1, ton("500"));
    mintJettons(minter, o2, ton("500"));
    val nft = deployNft(o1, 4101);
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
    // GRAM on BOTH sides, asymmetric amounts (pins the direction — a
    // transposed exchange would not pass the asserts with an upper bound)
    cfg.gram1Amount = ton("2");
    cfg.gram2Amount = ton("1");
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);

    // side-1 deposits: GRAM, fee, NFT, jetton
    expect(escrow.sendText(o1.address, "deposit_ton1", ton("2.01"))).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, nft, escrow.address, ton("0.2"))).toHaveAllSuccessfulTxs();
    expect(
        sendJettonTransfer2(
            o1,
            minter,
            escrow.address,
            ton("100"),
            ton("0.2"),
            1,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_ACTIVE); // side 2 has not deposited yet

    // side-2 deposits: GRAM, fee, jetton (the last one triggers auto-execution)
    expect(escrow.sendText(o2.address, "deposit_ton2", ton("1.01"))).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    val last = sendJettonTransfer2(
        o2,
        minter,
        escrow.address,
        ton("50"),
        ton("0.2"),
        2,
    );
    expect(last).toHaveAllSuccessfulTxs();

    // outcome
    expect(escrow.phase()).toEqual(PHASE_DONE);
    expect(readMockOwner(nft)).toEqual(o2.address);               // NFT — to the opposite side
    // jettons: o1 gave up 100, received 50; o2 the reverse
    expect(readJettonBalance(minter, o1.address)).toEqual(ton("450"));
    expect(readJettonBalance(minter, o2.address)).toEqual(ton("550"));
    expect(readJettonBalance(minter, escrow.address)).toEqual(0); // the escrow is empty
    // GRAM directions with an UPPER bound: o1 receives
    // EXACTLY gram2 = 1 (not 2 — a transposition would not pass), o2
    // receives exactly gram1 = 2. The tolerance is on the low side — the
    // forward fee under SEND_MODE_REGULAR; the refund transfers don't fall
    // into these ranges (the total available in this config is < 0.99).
    expect(last).toHaveTx({
        to: o1.address,
        value: fun(v: coins): bool {
            return v >= ton("0.99") && v <= ton("1");
        },
    });
    expect(last).toHaveTx({
        to: o2.address,
        value: fun(v: coins): bool {
            return v >= ton("1.99") && v <= ton("2");
        },
    });
    // the service fee arrived
    expect(last).toHaveTx({
        to: fw.address,
        value: fun(v: coins): bool {
            return v >= ton("0.19");
        },
    });
}

get fun `test jetton-only swap on both sides settles balances`() {
    // a jetton-only deal, one minter on both sides, a full E2E run
    val o1 = testing.treasury("js2-o1");
    val o2 = testing.treasury("js2-o2");
    val fw = testing.treasury("js2-fw");
    val minter = deployJettonMinter(o1, 42);
    mintJettons(minter, o1, ton("500"));
    mintJettons(minter, o2, ton("500"));
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

    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(
        sendJettonTransfer2(
            o1,
            minter,
            escrow.address,
            ton("100"),
            ton("0.2"),
            0,
        ),
    ).toHaveAllSuccessfulTxs();
    val last = sendJettonTransfer2(
        o2,
        minter,
        escrow.address,
        ton("50"),
        ton("0.2"),
        1,
    );
    expect(last).toHaveAllSuccessfulTxs();

    expect(escrow.phase()).toEqual(PHASE_DONE);
    expect(readJettonBalance(minter, o1.address)).toEqual(ton("450"));
    expect(readJettonBalance(minter, o2.address)).toEqual(ton("550"));
    expect(readJettonBalance(minter, escrow.address)).toEqual(0);

    // jetton_wallet_mock sends a TEP-74 Excesses to msg.responseAddress after
    // internal_transfer — this makes the escrow send's responseDest
    // FALSIFIABLE. The escrow always sets responseDestination = the jetton
    // recipient (newOwner, see Storage.assetRecipient)
    // — excesses MUST arrive at the new owner of each leg (o1 received o2's
    // jetton, o2 received o1's jetton).
    expect(last).toHaveTx<Excesses>({ to: o1.address });
    expect(last).toHaveTx<Excesses>({ to: o2.address });
}

// The E2E jetton tests above run a SINGLE minter on both sides (the jdSetup
// family / "jetton-only swap on both sides"). This one checks minter dedup,
// matchJettonAsset resolution by (jettonWallet, depositor), and per-minter
// balances with TWO DIFFERENT minters through to DONE. Here — minter A
// on side 1 (100), minter B on side 2 (40); asserts are laid out PER MINTER
// separately, to catch any possible mix-up between minters/wallets in the
// per-asset resolution.
get fun `test jetton swap with two different minters settles per-minter balances`() {
    val o1 = testing.treasury("js4-o1");
    val o2 = testing.treasury("js4-o2");
    val fw = testing.treasury("js4-fw");
    val minterA = deployJettonMinter(o1, 441);
    val minterB = deployJettonMinter(o1, 442);
    mintJettons(minterA, o1, ton("500"));
    mintJettons(minterB, o2, ton("500"));
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
            minter: minterB,
            ownerSide: 2,
            amount: ton("40"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 2;
    val escrow = deployEscrow(o1, cfg);
    // 2 unique minters — both resolve within the same deploy cascade (the
    // mock responds synchronously within the transaction chain of a single
    // net.send).
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);

    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(
        sendJettonTransfer2(
            o1,
            minterA,
            escrow.address,
            ton("100"),
            ton("0.2"),
            0,
        ),
    ).toHaveAllSuccessfulTxs();
    val last = sendJettonTransfer2(
        o2,
        minterB,
        escrow.address,
        ton("40"),
        ton("0.2"),
        1,
    );
    expect(last).toHaveAllSuccessfulTxs();

    expect(escrow.phase()).toEqual(PHASE_DONE);
    // Per minter, separately: o1 gave up 100 A, received 40 B; o2 the reverse.
    expect(readJettonBalance(minterA, o2.address)).toEqual(ton("100"));
    expect(readJettonBalance(minterB, o1.address)).toEqual(ton("40"));
    expect(readJettonBalance(minterA, o1.address)).toEqual(ton("400")); // 500 - 100
    expect(readJettonBalance(minterB, o2.address)).toEqual(ton("460")); // 500 - 40
    expect(readJettonBalance(minterA, escrow.address)).toEqual(0);
    expect(readJettonBalance(minterB, escrow.address)).toEqual(0);
}

get fun `test manual execute_swap with jettons: fails 424 before deposit, then auto-executes`() {
    // Manual execute_swap by owner1 (not about avoiding auto — auto would
    // fire anyway here; checking that the manual path is not broken by
    // jettons: execute_swap is sent BEFORE the last deposit → asserted at 424)
    val o1 = testing.treasury("js3-o1");
    val o2 = testing.treasury("js3-o2");
    val fw = testing.treasury("js3-fw");
    val minter = deployJettonMinter(o1, 43);
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
    cfg.jettons = js;
    cfg.jettonsCount = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    // Side 2 has no assets: it pays its half of the shared costs as TON.
    val (_s1, s2) = escrow.executionShortfall();
    expect(escrow.sendText(o2.address, "deposit_ton2", s2)).toHaveAllSuccessfulTxs();
    // the jetton has not been deposited yet → execute_swap fails with 424 (NftsNotReceived — the general "assets not collected" code)
    expect(escrow.sendText(o1.address, "execute_swap", ton("0.1"))).toHaveTx({
        to: escrow.address,
        exitCode: 424,
    });
    // deposit the jetton → auto-execution
    val last = sendJettonTransfer2(
        o1,
        minter,
        escrow.address,
        ton("100"),
        ton("0.2"),
        0,
    );
    expect(last).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_DONE);
    expect(readJettonBalance(minter, o2.address)).toEqual(ton("100"));

    // The single jetton leg is ONE-DIRECTIONAL (only o1 → o2, no jetton going the other way)
    // — unlike "jetton-only swap on both sides" (2 legs mask a responseDest
    // transposition, since both sides get an excesses transaction anyway,
    // just "from the wrong" asset), here a responseDest transposition is
    // caught unambiguously: excesses MUST arrive at the jetton's recipient
    // (o2), NOT at the original depositor (o1).
    expect(last).toHaveTx<Excesses>({ to: o2.address });
    expect(last).toNotHaveTx<Excesses>({ to: o1.address });
}
