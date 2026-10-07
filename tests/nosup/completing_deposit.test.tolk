// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// The deposit that completes a deal is recorded before execution is attempted,
// and execution runs on the gas the escrow already reserved — not on the
// forward the depositor chose for recording one asset.
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "nosup_helpers"

struct Completing {
    escrow: EscrowFixture
    o1: Treasury
    o2: Treasury
    lastNft: address
}

// n x n NFT deal, both fees paid, every deposit with 0.2 TON forward except
// side 2's LAST one, which completes the deal with `last`.
fun completing(tag: string, seed: int, n: int, last: coins): Completing {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    var b: map<uint16, address> = [];
    var i = 0;
    while (i < n) {
        a.set(i as uint16, deployNft(o1, seed + i));
        b.set(i as uint16, deployNft(o2, seed + 5000 + i));
        i += 1;
    }
    cfg.nfts1 = a;
    cfg.nfts1Count = n;
    cfg.nfts2 = b;
    cfg.nfts2Count = n;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    i = 0;
    while (i < n) {
        expect(
            sendNftToEscrow(o1, a.mustGet(i as uint16), escrow.address, ton("0.2"), i),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    i = 0;
    while (i < n - 1) {
        expect(
            sendNftToEscrow(o2, b.mustGet(i as uint16), escrow.address, ton("0.2"), n + i),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    // Pay any per-side shortfall up front — the getter already counts the
    // transfer cost of the pending last NFT — so the last deposit's forward
    // only has to record it. The extra 0.01 keeps each top-up's own
    // transaction well funded; it is an overpayment and comes back.
    val (s1, s2) = escrow.executionShortfall();
    if (s1 > 0) {
        expect(
            escrow.sendText(o1.address, "deposit_ton1", s1 + ton("0.01")),
        ).toHaveAllSuccessfulTxs();
    }
    if (s2 > 0) {
        expect(
            escrow.sendText(o2.address, "deposit_ton2", s2 + ton("0.01")),
        ).toHaveAllSuccessfulTxs();
    }
    val lastNft = b.mustGet((n - 1) as uint16);
    sendNftToEscrow(o2, lastNft, escrow.address, last, 2 * n - 1);
    return Completing { escrow, o1, o2, lastNft };
}

fun expectRecordedAndSafe(c: Completing, n: int) {
    expect(c.escrow.receivedCounts()).toEqual((n, n));
    if (c.escrow.phase() == PHASE_ACTIVE) {
        // not enough gas to execute on this deposit: the deal waits, whole
        expect(
            c.escrow.sendText(c.o1.address, "execute_swap", ton("0.5")),
        ).toHaveAllSuccessfulTxs();
    }
    expect(c.escrow.phase()).toEqual(PHASE_DONE);
    expect(readMockOwner(c.lastNft)).toEqual(c.o1.address);
}

get fun `test 10x10 completing deposit with 0.005 is kept`() {
    expectRecordedAndSafe(completing("cd-10a", 78001, 10, ton("0.005")), 10);
}

get fun `test 10x10 completing deposit with 0.001 is kept`() {
    expectRecordedAndSafe(completing("cd-10b", 78101, 10, ton("0.001")), 10);
}

get fun `test 50x50 completing deposit with 0.001 is kept`() {
    expectRecordedAndSafe(completing("cd-50a", 78201, 50, ton("0.001")), 50);
}

get fun `test 50x50 completing deposit with 0.02 is kept`() {
    expectRecordedAndSafe(completing("cd-50b", 78301, 50, ton("0.02")), 50);
}

// At the recording threshold: the deposit is recorded, but the forward's own
// gas does not stretch to an auto-execute attempt, and the deal waits for
// execute_swap. Measured on this deal size (10x10, ~4 TON already on the
// balance from the prior deposits): 0.00086 leaves the item unrecorded — the
// transaction's own gas (funded only by this deposit's forward, 12,899 units)
// runs out (compute phase exit -14) before the registry update and its
// COMMIT complete, and the NFT, already moved to the escrow, does not bounce
// back; it simply sits there untracked. 0.00087 buys just enough gas (13,049
// units) for the transaction to record the item, evaluate the auto-execute
// check to false, and finish normally — SETGASLIMIT is never reached, and the
// balance rises by only 66 nanoton. The recording threshold is set by the gas
// spent up to and including the COMMIT (`st.save();
// commitContractDataAndActions();`); `tryAutoExecute` runs only after that
// COMMIT, so its own cost cannot move the threshold either way — which is why
// 0.00086/0.00087 is the same with and without `@inline` on it. It moves if
// the recording cost itself changes.
get fun `test 10x10 completing deposit with 0.00087 is kept`() {
    expectRecordedAndSafe(completing("cd-10c", 78401, 10, ton("0.00087")), 10);
}

// The completing deposit is a jetton: 10 NFTs on side 1, one jetton on side 2.
get fun `test a completing jetton deposit with a small forward is kept`() {
    val o1 = testing.treasury("cd-j-o1");
    val o2 = testing.treasury("cd-j-o2");
    val fw = testing.treasury("cd-j-fw");
    val minter = deployJettonMinter(o2, 78501);
    mintJettons(minter, o2, ton("100"));
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    var i = 0;
    while (i < 10) {
        a.set(i as uint16, deployNft(o1, 78510 + i));
        i += 1;
    }
    cfg.nfts1 = a;
    cfg.nfts1Count = 10;
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter,
            ownerSide: 2,
            amount: ton("10"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    // side 2 pays its share up front, so the small forward only has to record
    val (_s1, s2) = escrow.executionShortfall();
    expect(escrow.sendText(o2.address, "deposit_ton2", s2)).toHaveAllSuccessfulTxs();
    i = 0;
    while (i < 10) {
        expect(
            sendNftToEscrow(o1, a.mustGet(i as uint16), escrow.address, ton("0.2"), i),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    sendJettonTransfer2(
        o2,
        minter,
        escrow.address,
        ton("10"),
        ton("0.003"),
        10,
    );
    expect(escrow.receivedCounts()).toEqual((10, 1));
    expect(escrow.phase()).toEqual(PHASE_DONE);
}

// The jetton path's COMMIT (Storage.handleJettonNotification): a forward too
// small to fund execution still records the jetton and leaves the deal
// ACTIVE, ready for a manual execute_swap. This is the jetton-path analogue
// of the NFT completing-deposit tests above, and it is the one that catches
// the COMMIT being dropped from the jetton handler specifically.
get fun `test a completing jetton deposit records before executing`() {
    val o1 = testing.treasury("cd-jc-o1");
    val o2 = testing.treasury("cd-jc-o2");
    val fw = testing.treasury("cd-jc-fw");
    val minter = deployJettonMinter(o2, 78601);
    mintJettons(minter, o2, ton("100"));
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    var i = 0;
    while (i < 10) {
        a.set(i as uint16, deployNft(o1, 78610 + i));
        i += 1;
    }
    cfg.nfts1 = a;
    cfg.nfts1Count = 10;
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter,
            ownerSide: 2,
            amount: ton("10"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    // side 2 pays its share up front, so the small forward only has to record
    val (_s1, s2) = escrow.executionShortfall();
    expect(escrow.sendText(o2.address, "deposit_ton2", s2)).toHaveAllSuccessfulTxs();
    i = 0;
    while (i < 10) {
        expect(
            sendNftToEscrow(o1, a.mustGet(i as uint16), escrow.address, ton("0.2"), i),
        ).toHaveAllSuccessfulTxs();
        i += 1;
    }
    sendJettonTransfer2(
        o2,
        minter,
        escrow.address,
        ton("10"),
        ton("0.001"),
        10,
    );
    expect(escrow.receivedCounts()).toEqual((10, 1));
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(escrow.sendText(o1.address, "execute_swap", ton("0.5"))).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_DONE);
}

// Nothing but a completing, fully funded deposit may raise the gas limit:
// these messages must not spend the escrow's balance on gas.
get fun `test an incomplete deal's deposit does not spend the balance`() {
    val o1 = testing.treasury("cd-s1-o1");
    val o2 = testing.treasury("cd-s1-o2");
    val fw = testing.treasury("cd-s1-fw");
    val n1 = deployNft(o1, 78601);
    val n2 = deployNft(o2, 78602);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, n1);
    var b: map<uint16, address> = [];
    b.set(0, n2);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = 1;
    val escrow = deployEscrow(o1, cfg);
    val before = testing.getAccountBalance(escrow.address);
    sendNftToEscrow(o1, n1, escrow.address, ton("0.002"), 0);
    expect(testing.getAccountBalance(escrow.address) >= before).toEqual(true);
}

get fun `test a stranger's bare transfer and kick do not spend the balance`() {
    val f = setup1x1("cd-s2", 78701);
    val stranger = testing.treasury("cd-s2-st");
    val before = testing.getAccountBalance(f.escrow.address);
    net.send(
        stranger.address,
        createMessage({ bounce: BounceMode.Only256BitsOfBody, value: ton("0.01"), dest: f
                .escrow
                .address }),
    );
    f.escrow.sendText(f.o1.address, "kick", ton("0.01"));
    expect(testing.getAccountBalance(f.escrow.address) >= before).toEqual(true);
}

// Per side funded, but the balance short of minBalanceForSwap: execution must
// not start (the counters include deposit gas; only the balance check sees it).
get fun `test per-side funding without the balance does not execute`() {
    val o1 = testing.treasury("cd-s3-o1");
    val o2 = testing.treasury("cd-s3-o2");
    val fw = testing.treasury("cd-s3-fw");
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    var b: map<uint16, address> = [];
    var i = 0;
    while (i < 50) {
        a.set(i as uint16, deployNft(o1, 78800 + i));
        b.set(i as uint16, deployNft(o2, 78900 + i));
        i += 1;
    }
    cfg.nfts1 = a;
    cfg.nfts1Count = 50;
    cfg.nfts2 = b;
    cfg.nfts2Count = 50;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    // each side's NFT forward is exactly its per-asset share: counters meet
    // the per-side check, the gas those 100 deposits burned leaves the balance short
    val (s1, s2) = escrow.executionShortfall();
    val f1 = s1 / 50 + 1;
    val f2 = s2 / 50 + 1;
    i = 0;
    while (i < 50) {
        sendNftToEscrow(o1, a.mustGet(i as uint16), escrow.address, f1, i);
        sendNftToEscrow(o2, b.mustGet(i as uint16), escrow.address, f2, 50 + i);
        i += 1;
    }
    // the getter names the balance deficit, split equally between the sides
    val (d1, d2) = escrow.executionShortfall();
    expect(d1 > 0).toEqual(true);
    expect(d2 - d1 >= 0 && d2 - d1 <= 1).toEqual(true);
    expect(escrow.canAutoExecuteNow()).toEqual(false);
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
}

// deploy_fee on a deal that is already ACTIVE does nothing and must not spend
// the balance.
get fun `test deploy_fee on an active deal does not spend the balance`() {
    val f = setup1x1("cd-s4", 78751);
    val stranger = testing.treasury("cd-s4-st");
    val before = testing.getAccountBalance(f.escrow.address);
    f.escrow.sendText(stranger.address, "deploy_fee", ton("0.002"));
    expect(testing.getAccountBalance(f.escrow.address) >= before).toEqual(true);
}

// A complete but underfunded deal: the last deposit is recorded and does not
// execute, so it must not raise the gas limit and spend the balance.
get fun `test an underfunded complete deal's last deposit does not spend the balance`() {
    val o1 = testing.treasury("cd-s5-o1");
    val o2 = testing.treasury("cd-s5-o2");
    val fw = testing.treasury("cd-s5-fw");
    val n1 = deployNft(o1, 78761);
    val n2 = deployNft(o2, 78762);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, n1);
    var b: map<uint16, address> = [];
    b.set(0, n2);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, n1, escrow.address, ton("2"), 0)).toHaveAllSuccessfulTxs();
    val before = testing.getAccountBalance(escrow.address);
    // side 2's forward cannot pay for its own NFT's transfer: complete, underfunded
    sendNftToEscrow(o2, n2, escrow.address, ton("0.005"), 1);
    expect(escrow.receivedCounts()).toEqual((1, 1));
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(testing.getAccountBalance(escrow.address) >= before).toEqual(true);
}

// The same as `per-side funding without the balance does not execute`, with a
// jetton as the completing deposit (the COMMIT on the jetton path). Side 1's
// NFTs come without an index hint: each deposit's linear search burns gas
// that its gross credit does not show, which leaves the balance short.
get fun `test a completing jetton deposit with per-side funding but no balance waits`() {
    val o1 = testing.treasury("cd-s6-o1");
    val o2 = testing.treasury("cd-s6-o2");
    val fw = testing.treasury("cd-s6-fw");
    val minter = deployJettonMinter(o2, 78951);
    mintJettons(minter, o2, ton("100"));
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    var i = 0;
    while (i < 50) {
        a.set(i as uint16, deployNft(o1, 78960 + i));
        i += 1;
    }
    cfg.nfts1 = a;
    cfg.nfts1Count = 50;
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter,
            ownerSide: 2,
            amount: ton("10"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    val (s1, s2) = escrow.executionShortfall();
    val f1 = s1 / 50 + 1;
    i = 0;
    while (i < 50) {
        sendNftToEscrow(o1, a.mustGet(i as uint16), escrow.address, f1);
        i += 1;
    }
    sendJettonTransfer2(
        o2,
        minter,
        escrow.address,
        ton("10"),
        s2 + 1,
        50,
    );
    expect(escrow.receivedCounts()).toEqual((50, 1));
    // the getter names the balance deficit, split equally between the sides
    val (d1, d2) = escrow.executionShortfall();
    expect(d1 > 0).toEqual(true);
    expect(d2 - d1 >= 0 && d2 - d1 <= 1).toEqual(true);
    expect(escrow.canAutoExecuteNow()).toEqual(false);
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
}

// Paying exactly the shortfall the getter names makes the deal execute: the
// execution's gas comes from the reserve, not from the paying message.
get fun `test paying exactly the named shortfall executes`() {
    val o1 = testing.treasury("cd-s7-o1");
    val o2 = testing.treasury("cd-s7-o2");
    val fw = testing.treasury("cd-s7-fw");
    val n1 = deployNft(o1, 78971);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, n1);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.gram2Amount = ton("1");
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(sendNftToEscrow(o1, n1, escrow.address, ton("0.05"), 0)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    escrow.sendText(o2.address, "deposit_ton2", ton("1"));
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    val (_s1, s2) = escrow.executionShortfall();
    escrow.sendText(o2.address, "deposit_ton2", s2);
    expect(escrow.phase()).toEqual(PHASE_DONE);
}
