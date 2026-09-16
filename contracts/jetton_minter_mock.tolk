// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Minimal TEP-89 minter for tests: responds with take_wallet_address to
// provide_wallet_address (using the same address derivation as the wallet
// mock), plus a test-only MintMock issuance (internal_transfer sent as the
// minter, which the wallet mock accepts without checking the peer address).
import "jetton_mock_lib"
import "messages"

struct MinterMockStorage {
    seed: uint32 // distinguishes minters (unique stateInit)
    walletCode: cell
}

fun MinterMockStorage.load(): MinterMockStorage {
    return MinterMockStorage.fromCell(contract.getData());
}

contract JettonMinterMock {
    author: "MENA"
    version: "1.0.0"
    description: "Minimal TEP-89 minter for escrow tests"
    storage: MinterMockStorage
    incomingMessages: MinterMessage
}

type MinterMessage =
    | ProvideWalletAddress
    | MintMock

fun onInternalMessage(in: InMessage) {
    if (in.body.isEmpty()) {
        return;
    }
    val msg = lazy MinterMessage.fromSlice(in.body);
    match (msg) {
        ProvideWalletAddress => {
            val st = MinterMockStorage.load();
            val resp = createMessage({
                bounce: false,
                value: 0,
                dest: in.senderAddress,
                body: TakeWalletAddress {
                    queryId: msg.queryId,
                    walletAddress: walletAddrFor(
                        contract.getAddress(),
                        msg.ownerAddress,
                        st.walletCode,
                    ),
                    rest: zeroBitSlice(), // include_address is not supported: Maybe = 0
                },
            });
            resp.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }
        MintMock => {
            val st = MinterMockStorage.load();
            val m = createMessage({
                bounce: true,
                value: 0,
                dest: { stateInit: walletInitFor(contract.getAddress(), msg.to, st.walletCode) },
                body: JettonInternalTransfer {
                    queryId: msg.queryId,
                    amount: msg.amount,
                    from: in.senderAddress,
                    responseAddress: in.senderAddress,
                    forwardTonAmount: 0,
                    forwardPayload: zeroBitSlice(),
                },
            });
            m.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }
    }
}
