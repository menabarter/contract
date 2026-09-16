// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later
// Shared code for the TEP-74 mocks (test-only). The wallet address is derived
// from the INITIAL stateInit (balance = 0): the current balance lives in data
// and does not affect the address, matching real jetton wallets. walletCode is
// stored in data (like jetton_wallet_code on real jettons) so both the minter
// and the wallets derive addresses in exactly the same way.

struct JwStorage {
    balance: coins
    ownerAddr: address
    minterAddr: address
    walletCode: cell
}

fun JwStorage.load(): JwStorage {
    return JwStorage.fromCell(contract.getData());
}

fun JwStorage.save(self) {
    contract.setData(self.toCell());
}

fun walletInitFor(minter: address, owner: address, walletCode: cell): ContractState {
    return ContractState {
        code: walletCode,
        data: JwStorage {
            balance: 0,
            ownerAddr: owner,
            minterAddr: minter,
            walletCode,
        }.toCell(),
    };
}

fun walletAddrFor(minter: address, owner: address, walletCode: cell): address {
    return AutoDeployAddress {
        stateInit: walletInitFor(minter, owner, walletCode),
    }.calculateAddress();
}
