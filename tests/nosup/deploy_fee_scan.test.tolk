// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

import "@stdlib/gas-payments"
// deploy_fee in SETUP must cost its caller everything the call spends: the
// provide values and the registry scan. A registry "minter" that keeps the
// value and never answers must not be able to burn the escrow's balance.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "nosup_helpers"

struct SilentMinterDeal {
    escrow: EscrowFixture
    minter: Treasury // an ordinary wallet: accepts provide requests, never answers
}

// `nfts` dummy NFT entries on side 1 plus one jetton on side 2 whose minter
// never answers, so the deal stays in SETUP. Registry size = nfts + 1.
fun silentMinterDeal(tag: string, nfts: int): SilentMinterDeal {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val z = testing.treasury(tagged(tag, "-z"));
    val dummy = testing.treasury(tagged(tag, "-d"));
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    var i = 0;
    while (i < nfts) {
        a.set(i as uint16, dummy.address);
        i += 1;
    }
    cfg.nfts1 = a;
    cfg.nfts1Count = nfts;
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter: z.address,
            ownerSide: 2,
            amount: ton("1"),
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.phase()).toEqual(PHASE_SETUP);
    return SilentMinterDeal {
        escrow,
        minter: z,
    };
}

fun providesOnly(n: int): coins {
    return PROVIDE_WALLET_VALUE + calculateGasFee(BASECHAIN, TAKE_WALLET_GAS_UNITS_PER_ASSET * n);
}

fun providesAndScan(n: int): coins {
    return providesOnly(n) +
        calculateGasFee(BASECHAIN, DEPLOY_BASE_GAS_UNITS + DEPLOY_GAS_UNITS_PER_ASSET * n);
}

fun deployFeeCall(d: SilentMinterDeal, value: coins): SendResultList {
    return d.escrow.sendText(d.minter.address, "deploy_fee", value);
}

get fun `test deploy_fee paying only the provides is rejected`() {
    val d = silentMinterDeal("dfs-rej", 0);
    val before = testing.getAccountBalance(d.escrow.address);
    val res = deployFeeCall(d, providesOnly(1));
    expect(res).toHaveFailedTx({ to: d.escrow.address, exitCode: Errors.InsufficientBalance });
    expect(testing.getAccountBalance(d.escrow.address) >= before).toEqual(true);
}

fun loopDoesNotDrain(tag: string, nfts: int) {
    val d = silentMinterDeal(tag, nfts);
    val n = nfts + 1;
    val before = testing.getAccountBalance(d.escrow.address);
    var k = 0;
    while (k < 5) {
        expect(deployFeeCall(d, providesAndScan(n))).toHaveAllSuccessfulTxs();
        k += 1;
    }
    expect(testing.getAccountBalance(d.escrow.address) >= before).toEqual(true);
}

get fun `test repeated deploy_fee does not drain a 1-entry registry`() {
    loopDoesNotDrain("dfs-1", 0);
}

get fun `test repeated deploy_fee does not drain a 5-entry registry`() {
    loopDoesNotDrain("dfs-5", 4);
}

get fun `test repeated deploy_fee does not drain a 300-entry registry`() {
    loopDoesNotDrain("dfs-300", 299);
}
