// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// SwapEscrowNosup's bytecode is referenced by every deal address the dapp
// computes. A change to escrow_nosup_beta_v1.tolk or to any file it compiles
// from moves this hash; the test makes such a change visible. Pinned for the
// toolchain in Acton.toml (Acton 1.2.1, Tolk 1.5.0).
import "@acton/build"
import "@acton/testing/expect"

get fun `test SwapEscrowNosup code hash is pinned`() {
    expect(build("SwapEscrowNosup").hash()).toEqual(
        0x7E0F567AB6B41C58F9B9E8F91355446C3DA9E13DEA56ED344E51A87612F0AAED,
    );
}
