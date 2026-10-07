// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// An acceptance matrix of deal configurations: every row must complete via
// the auto-execution path on the first attempt.
//
// One test per row: `runFullSwap` does the full assembly (deposits + service
// fee + NFT) AND asserts DONE/owners/feeWallet internally (see
// tests/nosup/nosup_helpers.tolk), so each test is a complete deal cycle for
// its (n1, n2, gram1, gram2).
import "nosup_helpers"

// #1: 1×1 NFT, no GRAM.
get fun `test parity #1: 1x1 NFT no GRAM`() {
    runFullSwap(1, 1, 0, 0, ton("0.20"));
}

// #2: a minimal case — GRAM only on side 2, side 1
// deposits nothing material (0 NFT / 0 GRAM). The TON-only side tops up its
// half of the shared costs (execution gas, dust, the storage floor), which
// its leg and fee alone do not carry.
get fun `test parity #2: 1x0 NFT with GRAM2 only`() {
    runFullSwap(
        1,
        0,
        0,
        ton("1"),
        ton("0.20"),
        true,
    );
}

// #3: the mirror of #2 — GRAM only on side 1, with the same top-up.
get fun `test parity #3: 0x1 NFT with GRAM1 only`() {
    runFullSwap(
        0,
        1,
        ton("1"),
        0,
        ton("0.20"),
        true,
    );
}

// #4: 5×5 NFT, no GRAM.
get fun `test parity #4: 5x5 NFT no GRAM`() {
    runFullSwap(5, 5, 0, 0, ton("0.20"));
}

// #5: asymmetric 5×1 + GRAM only on side 2.
get fun `test parity #5: 5x1 NFT with GRAM2`() {
    runFullSwap(5, 1, 0, ton("3"), ton("0.20"));
}

// #6: 10×10 NFT + GRAM on both sides.
get fun `test parity #6: 10x10 NFT with GRAM both sides`() {
    runFullSwap(10, 10, ton("1"), ton("1"), ton("0.20"));
}

// #7: 20×20 NFT, no GRAM.
get fun `test parity #7: 20x20 NFT no GRAM`() {
    runFullSwap(20, 20, 0, 0, ton("0.20"));
}

// #8: 30×30 NFT + GRAM 5/5 on both sides.
get fun `test parity #8: 30x30 NFT with GRAM both sides`() {
    runFullSwap(30, 30, ton("5"), ton("5"), ton("0.20"));
}

// #9/#10: 37×37 and 50×50 (the largest single-transaction deal,
// FAST_PATH_MAX_ASSETS = 100). Ordinary full checks via runFullSwap
// (DONE + NFT owners + feeWallet), like rows #1-#8. The gas boundaries are
// in tests/gas_probe.test.tolk.
get fun `test parity #9: 37x37 NFT no GRAM`() {
    runFullSwap(37, 37, 0, 0, ton("0.20"));
}

get fun `test parity #10: 50x50 NFT with GRAM both sides`() {
    runFullSwap(50, 50, ton("10"), ton("10"), ton("0.20"));
}

// #11: #10 above forwards the generous ton("0.20")/NFT used by the gas
// probes (see the comment above runFullSwap in nosup_helpers.tolk). A
// wallet-facing client forwards ton("0.05")/NFT (runFullSwap's default); this
// row proves the same 50×50 deal auto-executes with that realistic forward.
get fun `test parity #11: 50x50 NFT with GRAM both sides (forward 0.05)`() {
    runFullSwap(50, 50, ton("10"), ton("10"), ton("0.05"));
}

// Mixed configs — both sides carry NFT+jettons (or a jetton asymmetry), a
// full cycle via runMixedSwap (nosup_helpers). The k1/k2 numbers in both
// cases (10 and 20 jettons total) are far below the jetton boundary from one
// minter (154 total, gas_probe.test.tolk).

// #12: both sides mixed — 5 NFT + 5 jettons on each, GRAM going both ways
// (1<->2, asymmetric — parity with the directional asserts of the other
// mixed tests, see jetton_swap.test.tolk).
get fun `test parity #12: mixed 5 NFT + 5 jettons x 5 NFT + 5 jettons, GRAM 1<->2`() {
    runMixedSwap(
        5,
        5,
        5,
        5,
        ton("1"),
        ton("2"),
    );
}

// #13: a jetton asymmetry — 20 jettons from side 1 against 1 NFT from side
// 2, no GRAM (a pure asset-type asymmetry, not just a quantity one).
get fun `test parity #13: asymmetric 20 jettons x 1 NFT`() {
    runMixedSwap(
        0,
        20,
        1,
        0,
        0,
        0,
    );
}
