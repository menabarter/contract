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
        0xB6C5117A685568E8FF0919C2E36D62F5B2C686D6BA1BBEE986669CBB2A68A6AC,
    );
}
