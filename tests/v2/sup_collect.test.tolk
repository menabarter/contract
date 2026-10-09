// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// emergency_collect_assets: every received asset and the rescue registry to
// the supervisor; a jetton slot whose wallet the minter never confirmed stays.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/messages"
import "@wrappers/SwapEscrowV2.gen"
import "@contracts/shared/types"
import "@contracts/v2/storage"
import "sup_helpers"
import "v2_helpers"

get fun `test emergency_collect sends received assets and the rescue registry to the supervisor`() {
    val f = setup1x1("sc-1", 79301);
    // A foreign NFT stuck on the escrow (its forward is too small for the
    // auto-return), registered by the supervisor.
    val stuck = deployNft(f.o1, 79303);
    expect(sendNftToEscrow(f.o1, stuck, f.escrow.address, ton("0.005"))).toHaveAllSuccessfulTxs();
    expect(readMockOwner(stuck)).toEqual(f.escrow.address);
    expect(
        net.send(
            supAddr(),
            createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                value: ton("0.05"),
                dest: f.escrow.address,
                body: SupervisorAssetReceived { assetAddr: stuck },
            }),
        ),
    ).toHaveAllSuccessfulTxs();
    val res = f.escrow.sendText(supAddr(), "emergency_collect_assets", ton("0.3"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(readMockOwner(f.nft1)).toEqual(supAddr());
    expect(readMockOwner(f.nft2)).toEqual(supAddr());
    expect(readMockOwner(stuck)).toEqual(supAddr());
    expect(valueSentTo(res, f.escrow.address, f.o1.address)).toEqual(0);
    expect(valueSentTo(res, f.escrow.address, f.o2.address)).toEqual(0);
}

// The claimed address may not be the escrow's wallet: a slot the minter has
// not confirmed is not sent anywhere.
get fun `test emergency_collect leaves an unconfirmed jetton slot`() {
    val d = oneSigDeal("sc-2", 79311);
    acceptWithoutDiscovery(d, d.trueClaims());
    expect(
        sendJettonTransfer2(
            d.o2,
            d.m1,
            d.escrow.address,
            ton("10"),
            ton("0.05"),
            2,
        ),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendNftToEscrow(d.o2, d.nft2, d.escrow.address, ton("0.05"), 1),
    ).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_SETUP);
    val res = d.escrow.sendText(supAddr(), "emergency_collect_assets", ton("0.3"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(readMockOwner(d.nft2)).toEqual(supAddr());
    expect(readJettonBalance(d.m1, d.escrow.address)).toEqual(ton("10"));
    expect(res).toNotHaveTx({ from: d.escrow.address, to: jwAddr(d.m1, d.escrow.address) });
}

// The same on the batch path: the unconfirmed slot is the last registry entry,
// walked by the chain after the NFTs in front of it.
get fun `test batch collect skips an unconfirmed slot behind the cursor`() {
    val o1 = testing.treasury("sc-3-o1");
    val o2 = testing.treasury("sc-3-o2");
    val fw = testing.treasury("sc-3-fw");
    // A minter that never answers, so the deal stays in SETUP.
    val silent = testing.treasury("sc-3-silent");
    val claimed = testing.treasury("sc-3-claimed").address;
    var entries: map<uint16, address> = [];
    var nfts: map<uint16, address> = [];
    var i = 0;
    while (i < 100) {
        if (i < 2) {
            val nft = deployNft(o1, 79321 + i);
            nfts.set(i as uint16, nft);
            entries.set(i as uint16, nft);
        } else {
            entries.set(i as uint16, address.fromWorkchainAndHash(0, 79321 + i));
        }
        i += 1;
    }
    var cfg = makeBasicConfig(o1, o2, fw);
    cfg.nfts1 = entries;
    cfg.nfts1Count = 100;
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter: silent.address,
            ownerSide: 2,
            amount: ton("10"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 1;
    var st = buildInitialStorage(cfg);
    // Slot 100: side 2's jetton, recorded against a wallet it claimed and the
    // minter never confirmed.
    var j = st.assets.mustGet(100);
    j.jettonWallet = claimed;
    j.walletUnverified = true;
    j.received = true;
    st.assets.set(100, j);
    st.received2Count = 1;
    st.receivedJettons2 = 1;
    val escrow: EscrowFixture = SwapEscrowV2.fromStorage(st);
    expect(
        net.send(
            o1.address,
            createMessage({ bounce: BounceMode.NoBounce, value: ton("1"), dest: {
                    stateInit: escrow.stateInit!,
                } }),
        ),
    ).toHaveSuccessfulDeploy({ to: escrow.address });
    expect(escrow.phase()).toEqual(PHASE_SETUP);
    expect(
        sendNftToEscrow(o1, nfts.mustGet(0), escrow.address, ton("0.05"), 0),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendNftToEscrow(o1, nfts.mustGet(1), escrow.address, ton("0.05"), 1),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.receivedCounts()).toEqual((2, 1));
    val res = escrow.sendText(supAddr(), "emergency_collect_assets", chainReserve(101, 3));
    expect(res).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(escrow.distributionProgress()).toEqual((0, 101));
    expect(readMockOwner(nfts.mustGet(0))).toEqual(supAddr());
    expect(readMockOwner(nfts.mustGet(1))).toEqual(supAddr());
    expect(res).toNotHaveTx({ from: escrow.address, to: claimed });
}

get fun `test batch collect needs the chain reserve`() {
    val f = deployActiveRegistry("sc-4", 101, 2, 79341);
    val need = chainReserve(101, 2);
    val low = f.escrow.sendText(supAddr(), "emergency_collect_assets", need - 1);
    expect(low).toHaveFailedTx({ to: f.escrow.address, exitCode: Errors.InsufficientBalance });
    expect(f.escrow.phase()).toEqual(PHASE_ACTIVE);
    val ok = f.escrow.sendText(supAddr(), "emergency_collect_assets", need);
    expect(ok).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(readMockOwner(f.nfts.mustGet(0))).toEqual(supAddr());
    expect(readMockOwner(f.nfts.mustGet(1))).toEqual(supAddr());
}

get fun `test a second emergency_collect fails with 410`() {
    val f = setup1x1("sc-5", 79351);
    f.escrow.sendText(supAddr(), "emergency_collect_assets", ton("0.3"));
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
    val res = f.escrow.sendText(supAddr(), "emergency_collect_assets", ton("0.3"));
    expect(res).toHaveFailedTx({ to: f.escrow.address, exitCode: Errors.AlreadyFinalized });
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
}
