// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Supervisor emergency operations.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/storage"
import "@wrappers/SwapEscrow.gen"
import "escrow_helpers"

get fun `test emergency_return refunds both sides`() {
    val o1 = testing.treasury("er-o1");
    val o2 = testing.treasury("er-o2");
    val fw = testing.treasury("er-fw");
    val sup = testing.treasury("er-sup");

    // The same partial-state scenario as in the cancel test: side 1 must
    // deposit 2 NFTs, deposits only 1; GRAM + service fee are deposited.
    // Side 2 — nothing. The difference from cancel: the command is sent by
    // the SUPERVISOR (not an owner), and this must be allowed via the
    // emergency path regardless of the sender's role.
    val nftIn = deployNft(o1, 8001);
    val nftOut = deployNft(o1, 8002);
    var nfts1: map<uint16, address> = [];
    nfts1.set(0, nftIn);
    nfts1.set(1, nftOut);
    val empty2: map<uint16, address> = [];
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        supervisor: sup.address,
        nfts1,
        nfts1Count: 2,
        nfts2: empty2,
        nfts2Count: 0,
        gram1Amount: ton("1"),
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    expect(
        escrow.sendText(o1.address, "deposit_ton1", ton("1") + ton("0.01")),
    ).toHaveAllSuccessfulTxs();
    expect(
        escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE),
    ).toHaveAllSuccessfulTxs();
    expect(
        sendNftToEscrow(o1, nftIn, escrow.address, ton("0.05")),
    ).toHaveAllSuccessfulTxs();
    // nftOut was never deposited — should stay with o1.

    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(escrow.receivedCounts()).toEqual((1, 0));

    // The command is sent by the supervisor, with gas for distribution (by
    // design, emergency_return does not do a balance check, so no margin is
    // needed beyond covering this transaction's own outgoing messages).
    val res = escrow.sendText(sup.address, "emergency_return_assets", ton("0.5"));
    expect(res).toHaveAllSuccessfulTxs();

    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    // The deposited NFT returned to its depositor (o1); the undeposited one never left.
    expect(readMockOwner(nftIn)).toEqual(o1.address);
    expect(readMockOwner(nftOut)).toEqual(o1.address);

    // refund1 = gram1Received(1.01) + serviceFee1(0.1) + reserve1Rem(0.05-0.03=0.02)
    // = 1.13 nominally; the same formula and tolerance as in the cancel test.
    expect(res).toHaveTx({
        from: escrow.address,
        to: o1.address,
        value: fun(v: coins): bool {
            return v >= ton("1.1") && v <= ton("1.14");
        },
    });
    // owner2 deposited nothing → refund2 == 0 → no separate message to owner2.
}

// emergency_return_assets must NOT touch the isolated rescue registry
// (sup.rescueAssets) — only emergency_collect_assets sweeps it (see the
// comment on handleEmergencyReturn, "rescueAssets is NOT touched"). A negative test: register a rescue NFT via
// SupervisorAssetReceived, then send emergency_return_assets (NOT collect)
// → the rescue NFT's mock owner must stay UNCHANGED (it never transferred to
// the supervisor), unlike the deal assets, which emergency_return would
// return to their depositors.
get fun `test emergency_return does NOT touch isolated rescue registry`() {
    val o1 = testing.treasury("ri-o1");
    val o2 = testing.treasury("ri-o2");
    val fw = testing.treasury("ri-fw");
    val sup = testing.treasury("ri-sup");

    val dealNft = deployNft(o1, 8401);
    var nfts1: map<uint16, address> = [];
    nfts1.set(0, dealNft);
    val empty2: map<uint16, address> = [];
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        supervisor: sup.address,
        nfts1,
        nfts1Count: 1,
        nfts2: empty2,
        nfts2Count: 0,
        gram1Amount: 0,
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    // The deal NFT is accepted normally.
    expect(
        sendNftToEscrow(o1, dealNft, escrow.address, ton("0.05")),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.receivedCounts()).toEqual((1, 0));

    // An unrelated "stuck" NFT (a dust forward, auto-return did not fire) is
    // registered by the supervisor in the ISOLATED rescue registry.
    val rescueNft = deployNft(o1, 8402);
    expect(
        sendNftToEscrow(o1, rescueNft, escrow.address, ton("0.005")),
    ).toHaveAllSuccessfulTxs();
    expect(readMockOwner(rescueNft)).toEqual(escrow.address);
    expect(
        escrow.sendSupervisorAssetReceived(sup.address, rescueNft, { value: ton("0.1") }),
    ).toHaveAllSuccessfulTxs();

    // emergency_return_assets (NOT collect!) — finalizes, returns the deal
    // assets to their depositors, but does NOT touch the rescue registry.
    val res = escrow.sendText(sup.address, "emergency_return_assets", ton("0.5"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(escrow.phase()).toEqual(PHASE_CANCELLED);

    // The deal NFT returned to its depositor (o1) — the usual emergency_return behavior.
    expect(readMockOwner(dealNft)).toEqual(o1.address);
    // The rescue NFT — UNCHANGED: it still belongs to the escrow, nothing
    // arrived at the supervisor (the registry is isolated, swept only via collect).
    expect(readMockOwner(rescueNft)).toEqual(escrow.address);
}

get fun `test emergency_collect sends received NFTs to supervisor`() {
    val o1 = testing.treasury("ec-o1");
    val o2 = testing.treasury("ec-o2");
    val fw = testing.treasury("ec-fw");
    val sup = testing.treasury("ec-sup");

    val nft = deployNft(o1, 8101);
    var nfts1: map<uint16, address> = [];
    nfts1.set(0, nft);
    val empty2: map<uint16, address> = [];
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        supervisor: sup.address,
        nfts1,
        nfts1Count: 1,
        nfts2: empty2,
        nfts2Count: 0,
        gram1Amount: 0,
        gram2Amount: 0,
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    expect(
        sendNftToEscrow(o1, nft, escrow.address, ton("0.05")),
    ).toHaveAllSuccessfulTxs();
    expect(escrow.receivedCounts()).toEqual((1, 0));

    // Additionally: a foreign NFT gets stuck on the escrow (a dust deposit,
    // the forward is insufficient for auto-return) and is registered by the
    // supervisor in the ISOLATED rescue registry BEFORE emergency_collect —
    // checks that collect sweeps BOTH sets of assets (deal assets + the
    // rescue registry).
    val stuck = deployNft(o1, 8102);
    expect(
        sendNftToEscrow(o1, stuck, escrow.address, ton("0.005")),
    ).toHaveAllSuccessfulTxs();
    expect(readMockOwner(stuck)).toEqual(escrow.address);
    expect(
        escrow.sendSupervisorAssetReceived(sup.address, stuck, { value: ton("0.1") }),
    ).toHaveAllSuccessfulTxs();

    val res = escrow.sendText(sup.address, "emergency_collect_assets", ton("0.5"));
    expect(res).toHaveAllSuccessfulTxs();

    expect(escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(readMockOwner(nft)).toEqual(sup.address);
    expect(readMockOwner(stuck)).toEqual(sup.address);
}

get fun `test emergency ops rejected for non-supervisor 404`() {
    val o1 = testing.treasury("en-o1");
    val o2 = testing.treasury("en-o2");
    val fw = testing.treasury("en-fw");
    val sup = testing.treasury("en-sup");
    val stranger = testing.treasury("en-x");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));

    // Text entry point: emergency_collect_assets from a NON-supervisor (even owner1).
    val res1 = escrow.sendText(o1.address, "emergency_collect_assets", ton("0.5"));
    expect(res1).toHaveFailedTx({ to: escrow.address, exitCode: Errors.NotSupervisor });
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);

    // Binary entry point: RescueNft from an outsider.
    val fakeNft = deployNft(o1, 8201);
    val res2 = escrow.sendRescueNft(stranger.address, fakeNft, { value: ton("0.1") });
    expect(res2).toHaveFailedTx({ to: escrow.address, exitCode: Errors.NotSupervisor });
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
}

get fun `test rescue_nft transfers stuck NFT to supervisor`() {
    val o1 = testing.treasury("rn-o1");
    val o2 = testing.treasury("rn-o2");
    val fw = testing.treasury("rn-fw");
    val sup = testing.treasury("rn-sup");
    val escrow = deployEscrow(
        o1,
        makeBasicConfig(o1, o2, fw, sup),
    );

    // The "foreign NFT with dust" case, mirroring nft_deposits.test.tolk:
    // forward 0.005 < RETURN_TRANSFER_VALUE (0.03) — auto-return does not
    // fire, the NFT gets stuck on the escrow.
    val nft = deployNft(o1, 8301);
    expect(
        sendNftToEscrow(o1, nft, escrow.address, ton("0.005")),
    ).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nft)).toEqual(escrow.address);

    val res = escrow.sendRescueNft(sup.address, nft, { value: ton("0.1") });
    expect(res).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nft)).toEqual(sup.address);
}

get fun `test emergency_withdraw sweeps balance to supervisor`() {
    val o1 = testing.treasury("ew-o1");
    val o2 = testing.treasury("ew-o2");
    val fw = testing.treasury("ew-fw");
    val sup = testing.treasury("ew-sup");
    val escrow = deployEscrow(o1, makeBasicConfig(o1, o2, fw, sup));

    val supBalanceBefore = testing.getAccountBalance(sup.address);

    // By design there is NO phase gate — it fires even outside ACTIVE/SETUP, but here
    // it's enough to check the basic happy path (the contract is still ACTIVE).
    val res = escrow.sendText(sup.address, "emergency_withdraw_ton", ton("0.5"));
    expect(res).toHaveAllSuccessfulTxs();

    val supBalanceAfter = testing.getAccountBalance(sup.address);
    expect(supBalanceAfter).toBeGreater(supBalanceBefore);

    val escrowBalanceAfter = testing.getAccountBalance(escrow.address);
    expect(escrowBalanceAfter).toBeLessOrEqual(ton("0.01"));
}

// emergency_withdraw_ton is pinned down above only on an ACTIVE contract.
// handleEmergencyWithdraw is documented as having NO phase gate — it works
// even after DONE/CANCELLED. Here runFullSwap takes the deal to DONE the
// normal way, and the supervisor still successfully sweeps the balance
// afterward — if a phase gate were added to handleEmergencyWithdraw, this
// test would fail.
get fun `test emergency_withdraw sweeps balance after DONE (no phase gate)`() {
    val escrow = runFullSwap(1, 1, ton("1"), ton("2"));
    expect(escrow.phase()).toEqual(PHASE_DONE);

    // runFullSwap uses a fixed treasury name, "rf-sup", for the supervisor
    // (see escrow_helpers.tolk) — testing.treasury with the same name
    // WITHIN THE SAME test deterministically returns the same address (the
    // same pattern as "rf-o1" in cancel.test.tolk "cancel after done
    // rejected 410").
    val sup = testing.treasury("rf-sup");
    val supBalanceBefore = testing.getAccountBalance(sup.address);

    val res = escrow.sendText(sup.address, "emergency_withdraw_ton", ton("0.5"));
    expect(res).toHaveAllSuccessfulTxs();

    val supBalanceAfter = testing.getAccountBalance(sup.address);
    expect(supBalanceAfter).toBeGreater(supBalanceBefore);

    val escrowBalanceAfter = testing.getAccountBalance(escrow.address);
    expect(escrowBalanceAfter).toBeLessOrEqual(ton("0.01"));
}
