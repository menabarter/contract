// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// SwapEscrowV2's bytecode is referenced by every deal address the dapp
// computes. A change to escrow_beta_v2.tolk or to any file it compiles from
// moves this hash; the test makes such a change visible. Pinned for the
// toolchain in Acton.toml (Acton 1.2.1, Tolk 1.5.0).
import "@acton/build"
import "@acton/testing/expect"

get fun `test SwapEscrowV2 code hash is pinned`() {
    expect(build("SwapEscrowV2").hash()).toEqual(
        0xC4C683EE77AA7EB93E10B2E616D0A9C330D6793B96A3C49A3B04213539FA4B7A,
    );
}
