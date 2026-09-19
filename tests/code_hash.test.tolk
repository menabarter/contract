// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// The deployed SwapEscrow bytecode is referenced by every live deal address.
// Any change to escrow_beta_v1.tolk or to a file it compiles from would move
// this hash; the test makes such a change impossible to merge unnoticed.
import "@acton/build"
import "@acton/testing/expect"

get fun `test SwapEscrow code hash is pinned`() {
    expect(build("SwapEscrow").hash()).toEqual(
        0x41F7882FE4445147DAC4907FF6AEB60C32C4F7A5F43BFE5357433C18D41418D3,
    );
}
