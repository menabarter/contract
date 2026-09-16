// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Minimal TIP-4-like NFT item used ONLY by the test suite (a separate
// artifact, registered in Acton.toml as [contracts.NftItemMock]). Holds an
// owner, accepts NftTransfer (owner-checked), and sends OwnershipAssigned to
// the new owner with forwardAmount — enough to exercise the escrow's
// handleNftReceived/returnForeignNft without a full TIP-4 implementation.
import "messages"

struct MockNftStorage {
    ownerAddr: address
    seed: uint32          // distinguishes mock addresses (unique stateInit per deployment)
    rejectTransfers: bool // test-only switch for bounce scenarios
}

fun MockNftStorage.load(): MockNftStorage {
    return MockNftStorage.fromCell(contract.getData());
}

fun MockNftStorage.save(self) {
    contract.setData(self.toCell());
}

contract NftItemMock {
    author: "MENA"
    version: "1.0.0"
    description: "Minimal TIP-4 item for escrow tests"
    storage: MockNftStorage
    incomingMessages: MockNftMessage
}

type MockNftMessage =
    | NftTransfer
    | SetNftReject
    | SetNftOwner

fun onInternalMessage(in: InMessage) {
    if (in.body.isEmpty()) {
        return; // balance top-up / deploy with an empty body — ignore
    }
    val msg = lazy MockNftMessage.fromSlice(in.body);
    match (msg) {
        NftTransfer => {
            var st = MockNftStorage.load();
            assert (in.senderAddress == st.ownerAddr) throw 401;
            // Test mock of a broken recipient: a toggleable refusal to accept
            // transfers (bounce scenarios, see SetNftReject below).
            assert (!st.rejectTransfers) throw 999;
            val prev = st.ownerAddr;
            st.ownerAddr = msg.newOwner;
            st.save();
            // OwnershipAssigned goes to the new owner only if forwardAmount > 0
            // (TIP-4: the notification is sent ONLY when forward_amount is
            // nonzero). This matters for the escrow's returnForeignNft: it
            // returns the NFT with forwardAmount: 0 (see
            // contracts/escrow_beta_v1.tolk) — without this check the mock would
            // send a stray value: 0 notification back to the previous owner,
            // which fails in the emulator (a 0-value message with
            // bounce:false cannot cover the forward fee) and aborts the
            // whole transaction chain, even though the ownership change
            // (contract.setData above) has already been applied and is the
            // only effect the return actually needs.
            if (msg.forwardAmount > 0) {
                val notice = createMessage({
                    bounce: false,
                    value: msg.forwardAmount,
                    dest: msg.newOwner,
                    body: OwnershipAssigned {
                        queryId: msg.queryId,
                        previousOwner: prev,
                        // Pass the deposit's forward_payload straight through
                        // (TIP-4 semantics) so the asset_index hint reaches the escrow.
                        forwardPayload: msg.forwardPayload,
                    },
                });
                notice.send(SEND_MODE_PAY_FEES_SEPARATELY);
            }
        }
        // TEST-ONLY opcode: toggle refusal to accept transfers (bounce
        // scenarios). Callable by anyone — this is a test mock, not TIP-4-guarded.
        SetNftReject => {
            var st = MockNftStorage.load();
            st.rejectTransfers = msg.reject;
            st.save();
        }
        // TEST-ONLY opcode: change the owner without a TIP-4 transfer (breaks
        // the circular escrow/mock address dependency in mid-state fixtures,
        // see deployEscrowMidDistribution).
        SetNftOwner => {
            var st = MockNftStorage.load();
            st.ownerAddr = msg.newOwner;
            st.save();
        }
        else => {
            throw 0xFFFF;
        }
    }
}

get fun ownerAddr(): address {
    val st = lazy MockNftStorage.load();
    return st.ownerAddr;
}
