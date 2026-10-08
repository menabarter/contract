// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Several internal messages in ONE signed external message — what a TON
// Connect wallet does when the dapp asks for one signature over a batch.
// `net.send` sends one message per external message, so the testnet smokes of
// the one-signature flow build the wallet's signed request themselves:
//   • wallet v5r1: signed_request with an OutList of action_send_msg;
//   • wallet v4r2: up to four (mode, ^message) pairs after op 0.
// Every message goes with mode 3 (pay fees separately + ignore errors), the
// mode TON Connect wallets use: a message the balance cannot cover is dropped
// and the rest still go out.
//
// Keys are available only in scripts started with `--net`. Without it (a
// local dry run) the messages are sent one by one in the same order, which
// checks the deal logic but not the batch encoding.
import "@acton/emulation/network"
import "@acton/emulation/scripts"

const BATCH_SEND_MODE = 3
const BATCH_TTL_SECONDS = 300
const W5_SIGNED_EXTERNAL = 0x7369676e
const W5_ACTION_SEND_MSG = 0x0ec3c86d

fun walletSeqno(wallet: address): int {
    if (!scripts.isContractDeployed(wallet)) {
        return 0;
    }
    return net.runGetMethod<int>(wallet, "seqno");
}

fun sendOneByOne(wallet: ActonWallet, msgs: array<OutMessage>): SendResultList {
    var last = net.send(wallet.address, msgs.get(0));
    var i = 1;
    while (i < msgs.size()) {
        last = net.send(wallet.address, msgs.get(i));
        i += 1;
    }
    return last;
}

// out_list$_ {n:#} prev:^(OutList n) action:OutAction = OutList (n + 1);
// the first message of `msgs` is the deepest one and is sent first.
fun w5OutList(msgs: array<OutMessage>): cell {
    var list = beginCell().endCell();
    var i = 0;
    while (i < msgs.size()) {
        list = beginCell()
            .storeRef(list)
            .storeUint(W5_ACTION_SEND_MSG, 32)
            .storeUint(BATCH_SEND_MODE, 8)
            .storeRef(msgs.get(i).messageCell)
            .endCell();
        i += 1;
    }
    return list;
}

// Sends `msgs` from a v5r1 wallet in one signed external message.
fun sendBatchV5(wallet: ActonWallet, msgs: array<OutMessage>): ExternalSendResult? {
    if (!net.isBroadcasting()) {
        sendOneByOne(wallet, msgs);
        return null;
    }
    val unsigned = beginCell()
        .storeUint(W5_SIGNED_EXTERNAL, 32)
        .storeUint(wallet.walletId(), 32)
        .storeUint(blockchain.now() + BATCH_TTL_SECONDS, 32)
        .storeUint(walletSeqno(wallet.address), 32)
        .storeMaybeRef(w5OutList(msgs))
        .storeUint(0, 1) // no extended actions
        .endCell();
    val signature = wallet.sign(unsigned);
    val body = beginCell().storeSlice(unsigned.beginParse()).storeSlice(signature).endCell();
    return net.sendExternal(net.createExternalMessage(wallet.address, body.beginParse()));
}

// Sends `msgs` (at most four) from a v4r2 wallet in one signed external message.
fun sendBatchV4(wallet: ActonWallet, msgs: array<OutMessage>): ExternalSendResult? {
    assert (msgs.size() <= 4) throw 0xFFFF;
    if (!net.isBroadcasting()) {
        sendOneByOne(wallet, msgs);
        return null;
    }
    // subwallet_id, valid_until, seqno, op 0 (simple send)
    var b = beginCell()
        .storeUint(wallet.walletId(), 32)
        .storeUint(blockchain.now() + BATCH_TTL_SECONDS, 32)
        .storeUint(walletSeqno(wallet.address), 32)
        .storeUint(0, 8);
    var i = 0;
    while (i < msgs.size()) {
        b = b.storeUint(BATCH_SEND_MODE, 8).storeRef(msgs.get(i).messageCell);
        i += 1;
    }
    val unsigned = b.endCell();
    val signature = wallet.sign(unsigned);
    val body = beginCell().storeSlice(signature).storeSlice(unsigned.beginParse()).endCell();
    return net.sendExternal(net.createExternalMessage(wallet.address, body.beginParse()));
}
