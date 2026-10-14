// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Test-only NFT item whose transfer burns a configurable amount of gas before
// changing the owner. Models a collection with heavy transfer logic: the
// escrow's fixed NFT_TRANSFER_VALUE is not enough, the transfer fails out of
// gas, and the value may be fully consumed so that no bounce comes back.
//
// Alias "@stdlib/..." (NOT "@acton/tolk-stdlib/...") — the same alias under
// which this physical file is already imported transitively via test files
// that pull in "@acton/testing/expect" (see the explanation in
// tests/nosup/gas_probe.test.tolk). A different alias for the same physical
// file gives "redefinition of a symbol from stdlib" once this contract is
// linked into a test binary alongside those files.
import "@stdlib/gas-payments"
import "messages"

struct MockGasNftStorage {
    ownerAddr: address
    seed: uint32
    burnGas: uint32 // gas to consume before applying a transfer
}

contract NftItemGasMock {
    author: "MENA"
    version: "1.0.0"
    description: "TIP-4 item with a gas-hungry transfer, for escrow tests"
    storage: MockGasNftStorage
    incomingMessages: NftTransfer
}

fun onInternalMessage(in: InMessage) {
    if (in.body.isEmpty()) {
        return;
    }
    val msg = lazy NftTransfer.fromSlice(in.body);
    var st = MockGasNftStorage.fromCell(contract.getData());
    assert (in.senderAddress == st.ownerAddr) throw 401;
    var x = 0;
    while (getGasConsumedAtTheMoment() < (st.burnGas as int)) {
        x += 1;
    }
    val prev = st.ownerAddr;
    st.ownerAddr = msg.newOwner;
    contract.setData(st.toCell());
    if (msg.forwardAmount > 0) {
        createMessage({
            bounce: BounceMode.NoBounce,
            value: msg.forwardAmount,
            dest: msg.newOwner,
            body: OwnershipAssigned {
                queryId: msg.queryId,
                previousOwner: prev,
                forwardPayload: msg.forwardPayload,
            },
        }).send(SEND_MODE_PAY_FEES_SEPARATELY);
    }
}

get fun ownerAddr(): address {
    return MockGasNftStorage.fromCell(contract.getData()).ownerAddr;
}
