// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// The deployed SwapEscrow bytecode is referenced by every live deal address.
// Any change to escrow_beta_v1.tolk or to a file it compiles from would move
// this hash; the test makes such a change impossible to merge unnoticed.
//
// The hash also depends on the compiler. The pin is for the toolchain in
// Acton.toml (Acton 1.2.1, Tolk 1.5.0). The deployed contract was built with
// Tolk 1.4.2 (Acton 1.2.0), where the same source compiles to
// 41F7882FE4445147DAC4907FF6AEB60C32C4F7A5F43BFE5357433C18D41418D3.
import "@acton/build"
import "@acton/testing/expect"

get fun `test SwapEscrow code hash is pinned`() {
    expect(build("SwapEscrow").hash()).toEqual(
        0x25811004DF61AAB86E8A06292804E9AE88E18A06CC6FF54E88CAFE510BEA9B3B,
    );
}
