// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Minimal TEP-74 jetton wallet for tests (analogous to nft_item_mock):
// transfer from the owner -> internal_transfer to the recipient's wallet
// (auto-deployed via stateInit) -> transfer_notification to the recipient
// owner when forward_ton_amount > 0. internal_transfer authenticity is
// checked by deriving the sender wallet's address (or accepting the minter
// itself for mint). Excesses is sent to responseAddress after crediting
// (mode 66 = CARRY_ALL_REMAINING + IGNORE_ERRORS), which makes the escrow's
// outgoing responseDestination observable by tests.
import "jetton_mock_lib"
import "messages"

contract JettonWalletMock {
    author: "MENA"
    version: "1.0.0"
    description: "Minimal TEP-74 wallet for escrow tests"
    storage: JwStorage
    incomingMessages: JwMessage
}

type JwMessage =
    | JettonTransfer
    | JettonInternalTransfer

fun onInternalMessage(in: InMessage) {
    if (in.body.isEmpty()) {
        return; // TON balance top-up — ignore
    }
    val msg = lazy JwMessage.fromSlice(in.body);
    match (msg) {
        JettonTransfer => {
            var st = JwStorage.load();
            assert (in.senderAddress == st.ownerAddr) throw 401; // TEP-74: owner only
            assert (st.balance >= msg.amount) throw 402;         // insufficient tokens
            st.balance -= msg.amount;
            st.save();
            val m = createMessage({
                bounce: true,
                value: 0,
                dest: { stateInit: walletInitFor(st.minterAddr, msg.destination, st.walletCode) },
                body: JettonInternalTransfer {
                    queryId: msg.queryId,
                    amount: msg.amount,
                    from: st.ownerAddr,
                    responseAddress: msg.responseDestination,
                    forwardTonAmount: msg.forwardTonAmount,
                    forwardPayload: msg.forwardPayload,
                },
            });
            m.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }
        JettonInternalTransfer => {
            var st = JwStorage.load();
            // TEP-74 anti-spoofing: only accept from a wallet of the same
            // minter (address derived from from) or from the minter itself (mint).
            val expectedPeer = walletAddrFor(st.minterAddr, msg.from, st.walletCode);
            assert (
                in.senderAddress == expectedPeer || in.senderAddress == st.minterAddr
            ) throw 403;
            st.balance += msg.amount;
            st.save();
            if (msg.forwardTonAmount > 0) {
                val notice = createMessage({
                    bounce: false,
                    value: msg.forwardTonAmount,
                    dest: st.ownerAddr,
                    body: JettonTransferNotification {
                        queryId: msg.queryId,
                        amount: msg.amount,
                        sender: msg.from,
                        forwardPayload: msg.forwardPayload,
                    },
                });
                notice.send(SEND_MODE_PAY_FEES_SEPARATELY);
            }
            // TEP-74 excesses — the leftover value attached to
            // internal_transfer is sent to msg.responseAddress, as on real
            // jetton wallets. Staying silent here would make the deposit's
            // responseDest unfalsifiable: no test could check WHO actually
            // received the excesses.
            //
            // The send mode is deliberate: mode 64
            // (CARRY_ALL_REMAINING_MESSAGE_VALUE) alone broke ~35 existing
            // deposit tests with action_result_code=37 "Not enough Toncoin" —
            // when forwardTonAmount > 0, the notice above already goes out
            // SEND_MODE_PAY_FEES_SEPARATELY (the forward fee is taken FROM
            // the wallet's balance ON TOP OF the declared value, not
            // deducted from it), so the SECOND outgoing message (excesses)
            // from the same wallet can end up without enough coverage — the
            // test forwardTon amounts (0.2 TON) were not sized for TWO
            // fee-separate messages from an intermediate mock wallet with a
            // minimal balance of its own. Added the +2 flag
            // (SEND_MODE_IGNORE_ERRORS, giving mode 66 total): when there
            // isn't enough left, this SPECIFIC send is silently skipped (the
            // transaction does not abort), and when there is enough (all
            // non-deposit paths — executeSwap/cancel/emergency with
            // forwardTonAmount=0 — never send the notice at all) the
            // excesses go out normally. This is the minimal change under
            // which the ENTIRE existing suite is green (verified: 115
            // passed/4 skipped after adding +2).
            val excesses = createMessage({
                bounce: false,
                value: 0,
                dest: msg.responseAddress,
                body: Excesses { queryId: msg.queryId },
            });
            excesses.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE + SEND_MODE_IGNORE_ERRORS);
        }
    }
}

get fun jettonBalance(): coins {
    val st = lazy JwStorage.load();
    return st.balance;
}

get fun jwOwner(): address {
    val st = lazy JwStorage.load();
    return st.ownerAddr;
}
