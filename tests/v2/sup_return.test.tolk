// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// emergency_return_assets: every received asset back to its depositor and the
// TON split by the settlement rules, with the supervisor paying for the
// operation itself.
import "@stdlib/gas-payments"
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

// Mirrors Storage.emergencyChainReserve: the later batches of a supervisor's
// chain run on the escrow's balance, so the attachment pays for them.
fun chainReserve(registrySize: int, received: int): coins {
    val walkUnits = SKIP_GAS_UNITS_PER_ENTRY * (registrySize - received);
    val batches = (received + BATCH_MAX_SENDS - 1) / BATCH_MAX_SENDS +
        (walkUnits + BATCH_GAS_SOFT_CAP - 1) / BATCH_GAS_SOFT_CAP;
    return calculateGasFee(BASECHAIN, EXEC_GAS_UNITS_PER_SEND * received) +
        calculateGasFee(BASECHAIN, BATCH_EXTRA_GAS_UNITS * batches + walkUnits) +
        calculateGasFee(BASECHAIN, CONTINUE_GAS_UNITS) +
        calculateForwardFee(BASECHAIN, 1023, 1);
}

// Both NFTs and side 1's fee are in. The refunds split what was on the
// balance before the supervisor's message, less the returns, DUST and the
// storage floor: the attachment pays this transaction and stays out.
get fun `test emergency_return refunds by the settlement rules and keeps the supervisor's attachment out of the split`() {
    val f = setup1x1("sr-1", 79201);
    val g = f.escrow.gramState();
    val before = testing.getAccountBalance(f.escrow.address);
    val floor = f.escrow.storageFloor();
    val res = f.escrow.sendText(supAddr(), "emergency_return_assets", ton("0.5"));
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(readMockOwner(f.nft1)).toEqual(f.o1.address);
    expect(readMockOwner(f.nft2)).toEqual(f.o2.address);
    expect(res).toNotHaveTx({ from: f.escrow.address, to: f.fw.address });
    val refund1 = valueSentTo(res, f.escrow.address, f.o1.address);
    val refund2 = valueSentTo(res, f.escrow.address, f.o2.address);
    expect(refund1 > 0).toEqual(true);
    expect(refund2 > 0).toEqual(true);
    // R = balance before - own returns - DUST - storage floor; each refund
    // arrives less its own forwarding fee (mode 0).
    val r = before - NFT_TRANSFER_VALUE * 2 - DUST - floor;
    val fwd = calculateForwardFee(BASECHAIN, 0, 0);
    expect(refund1 + refund2).toBeInRange(r - fwd * 2 - ton("0.00001"), r - fwd * 2);
    // Each side's outlay (paid - refund - own return) is the same.
    val paid1 = g.gram1Received + g.serviceFee1 + g.gram1DepositReserve;
    val paid2 = g.gram2Received + g.serviceFee2 + g.gram2DepositReserve;
    val outlay1 = paid1 - refund1 - NFT_TRANSFER_VALUE;
    val outlay2 = paid2 - refund2 - NFT_TRANSFER_VALUE;
    expect(outlay1 - outlay2).toBeInRange(-1, 1);
    expect(testing.getAccountBalance(f.escrow.address) >= floor).toEqual(true);
}

// In SETUP a jetton recorded against side 2's claimed wallet goes back
// through that wallet.
get fun `test emergency_return in SETUP with a provisional jetton returns it to its depositor`() {
    val d = oneSigDeal("sr-2", 79211);
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
    expect(readJettonBalance(d.m1, d.o2.address)).toEqual(ton("90"));
    expect(d.escrow.phase()).toEqual(PHASE_SETUP);
    d.escrow.sendText(supAddr(), "emergency_return_assets", ton("0.5"));
    expect(d.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(readJettonBalance(d.m1, d.o2.address)).toEqual(ton("100"));
}

get fun `test a second emergency_return fails with 410`() {
    val f = setup1x1("sr-3", 79221);
    f.escrow.sendText(supAddr(), "emergency_return_assets", ton("0.5"));
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
    val before = testing.getAccountBalance(f.escrow.address);
    val res = f.escrow.sendText(supAddr(), "emergency_return_assets", ton("0.5"));
    expect(res).toHaveFailedTx({ to: f.escrow.address, exitCode: Errors.AlreadyFinalized });
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(testing.getAccountBalance(f.escrow.address) >= before).toEqual(true);
}

// Above 100 entries the return runs as a batch chain whose later transactions
// pay from the balance: the attachment must cover them (430 below that).
get fun `test batch emergency_return needs the chain reserve`() {
    val f = deployActiveRegistry("sr-b", 101, 2, 79101);
    val need = chainReserve(101, 2);
    val low = f.escrow.sendText(supAddr(), "emergency_return_assets", need - 1);
    expect(low).toHaveFailedTx({ to: f.escrow.address, exitCode: Errors.InsufficientBalance });
    expect(f.escrow.phase()).toEqual(PHASE_ACTIVE);
    val ok = f.escrow.sendText(supAddr(), "emergency_return_assets", need);
    expect(ok).toHaveAllSuccessfulTxs();
    expect(f.escrow.phase()).toEqual(PHASE_CANCELLED);
    expect(f.escrow.distributionProgress()).toEqual((0, 101));
    expect(readMockOwner(f.nfts.mustGet(0))).toEqual(f.o1.address);
    expect(readMockOwner(f.nfts.mustGet(1))).toEqual(f.o1.address);
    expect(testing.getAccountBalance(f.escrow.address) >= f.escrow.storageFloor()).toEqual(true);
}

// The returns are paid from the balance; if the balance and the attachment
// cannot pay them, the action phase fails and the whole transaction rolls back.
get fun `test emergency_return with an attachment below its returns rolls back`() {
    val o1 = testing.treasury("sr-5-o1");
    val o2 = testing.treasury("sr-5-o2");
    val fw = testing.treasury("sr-5-fw");
    val n1 = deployNft(o1, 79231);
    val n2 = deployNft(o2, 79232);
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
    sendNftToEscrow(o1, n1, escrow.address, ton("0.005"), 0);
    sendNftToEscrow(o2, n2, escrow.address, ton("0.005"), 1);
    expect(escrow.receivedCounts()).toEqual((1, 1));
    // Empty the balance first, so that an attachment that buys enough gas
    // stays short of the two returns.
    escrow.sendText(supAddr(), "emergency_withdraw_ton", ton("0.01"));
    expect(testing.getAccountBalance(escrow.address)).toEqual(0);
    val attach = ton("0.02");
    val res = escrow.sendText(supAddr(), "emergency_return_assets", attach);
    // Compute succeeds (exit 0); the action phase cannot pay the returns.
    expect(res).toHaveTx({ to: escrow.address, exitCode: 0, success: false });
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(readMockOwner(n1)).toEqual(escrow.address);
}
