// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Checks whether a jetton minter responds to TEP-89 (provide_wallet_address).
//
// WHY. This is exactly how the escrow resolves the address of its jetton
// wallets: it sends ProvideWalletAddress to the minter and waits for
// TakeWalletAddress. If the minter doesn't support this or stays silent, the
// deal is stuck in the SETUP phase forever — the contract won't accept a
// jetton deposit before that resolves. Checking this BEFORE the deal costs
// 0.02 TON; finding out after means a stuck deal with the fee already paid.
//
// Having a get_wallet_address getter is NOT proof: a getter and a message
// handler are different things, and the contract needs the actual reply to
// the message.
//
// Run: acton script scripts/probe_tep89.tolk --net testnet
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/messages"

// The minter being checked.
const MINTER = "0:226e80c4bffa91adc11dad87706d52cd397047c128456ed2866d0549d8e2b163"

// Matches what the escrow attaches (PROVIDE_WALLET_VALUE in storage.tolk).
const PROBE_VALUE: coins = ton("0.02")

const POLL_ATTEMPTS = 40
const POLL_SLEEP_MS = 3000

fun main() {
    println("=== Checking TEP-89 on the minter ===");
    println("Broadcasting to real network: {}", net.isBroadcasting());

    val wallet1 = scripts.wallet("wallet1");
    val minter = address(MINTER);
    println("prober = {}", wallet1.address);
    println("minter = {}", minter);

    // includeAddress: true — matches how the escrow sends it.
    val res = net.send(
        wallet1.address,
        createMessage({
            bounce: true,
            value: PROBE_VALUE,
            dest: minter,
            body: ProvideWalletAddress {
                queryId: 0,
                ownerAddress: wallet1.address,
                includeAddress: true,
            },
        }),
    );

    // Wait for the WHOLE trace: the take_wallet_address reply is a separate transaction.
    val applied = res.waitForTrace(false, POLL_ATTEMPTS, POLL_SLEEP_MS);
    if (applied == null) {
        println("");
        println("RESULT: the trace did not settle within the allotted time.");
        println("The minter may not have responded — using this jetton in a deal is UNSAFE.");
        return;
    }

    println("");
    println("RESULT: trace settled — the minter processed provide_wallet_address.");
    println("Check in the explorer that the reply was take_wallet_address (0xd1735400):");
    println("https://testnet.tonviewer.com/{}", wallet1.address);
}
