// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Jetton wallet discovery with claims: side 2 claims the escrow's wallet
// addresses in AcceptDeal, a deposit from a claimed address is recorded
// provisionally, and the minter's take_wallet_address confirms or undoes it.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "nosup_helpers"

// A minter answers addr_none for an owner it does not serve. The answer must
// not throw: the minter's slots stay without a wallet, nothing counts as
// resolved and the deal stays in SETUP until it is cancelled.
get fun `test an addr_none answer keeps the deal in SETUP`() {
    val d = setupWithSilentMinter("wc1", 0x710000, false);
    val res = sendTakeWallet(d.silent.address, d.escrow.address, null);
    expect(res).toHaveAllSuccessfulTxs();
    expect(d.escrow.phase()).toEqual(PHASE_SETUP);
    expect(d.escrow.pendingWalletsLeft()).toEqual(1);
    expect(d.escrow.assetJettonWallet(1)).toEqual(null);
}
