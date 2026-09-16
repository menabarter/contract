// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// A fork test of TEP-89 discovery against the REAL mainnet USDT minter (not
// a mock minter, as in all the other jetton_* tests).
//
// Fork mode: a run against real mainnet minters (USDT). Mechanism: `acton
// test` can resolve account state remotely via the `--fork-net <network>`
// flag (+ optionally `--fork-block-number <seqno>` for a historical block) —
// see `acton help test`, the "Remote Options"/"TONCENTER API KEYS" section.
// This is a CLI flag for the whole run, NOT a setting inside the test:
// without it, the real minter's address in local emulation is an account
// with no code (it was never deployed in this world), so
// provide_wallet_address would go "into the void" (the balance gets
// credited, no response comes back) — exactly the same outcome as
// `silentMinterKeepsSetupAndCancelRefunds` in jetton_discovery.test.tolk. So
// the test is @test.skip by default (an ordinary `acton test` in CI/offline
// will not spin up a fork) — the manual-run command is recorded in the
// reason below.
//
// The deposit is NOT emulated in fork mode (the test treasuries have no
// real USDT balance in the forked mainnet state) — the test only covers the
// discovery path (provision → wallet-address resolution by the minter's
// real code). The rest of the jetton wire path (TEP-74 transfers) is
// identical between real USDT and the mock minter in message format — a
// full E2E run against real USDT on testnet is a separate effort.
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/storage"
import "@wrappers/SwapEscrow.gen"
import "escrow_helpers"

// The USDT (Tether) jetton minter on mainnet — the canonical TEP-74/89
// contract.
const USDT_MAINNET_MINTER = address("EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs")

// The manual-run command (see the skip reason below): requires network
// access (toncenter) — an API key is not required (keyless mode works, but
// is limited to 1 RPS, see .env.example); it helps to put
// TONCENTER_MAINNET_API_KEY in .env for speed.
//
//   acton test tests/jetton_fork_usdt.test.tolk --fork-net mainnet -f "discoveryResolvesAgainstRealUsdtMinter"
//
// (to pin it to a specific block, add
// `--fork-block-number <seqno>`, see `acton rpc block-number`).
@test.skip("fork mode requires network; run manually: acton test tests/jetton_fork_usdt.test.tolk --fork-net mainnet -f \"discoveryResolvesAgainstRealUsdtMinter\"")
get fun `test discoveryResolvesAgainstRealUsdtMinter`() {
    val o1 = testing.treasury("fork-o1");
    val o2 = testing.treasury("fork-o2");
    val fw = testing.treasury("fork-fw");
    val sup = testing.treasury("fork-sup");

    // Deal: 1 side-1 USDT jetton, no NFT/GRAM — the minimal config
    // sufficient to check the discovery path.
    var cfg = makeBasicConfig(o1, o2, fw, sup);
    var js: map<uint16, JettonCfg> = [];
    js.set(
        0,
        JettonCfg {
            minter: USDT_MAINNET_MINTER,
            ownerSide: 1,
            amount: ton("1"), // 1 USDT (the real minter uses 6 decimals, but amount here is
            // just a serializable value per the TEP-74 protocol — the escrow does not decode it)
        },
    );
    cfg.jettons = js;
    cfg.jettonsCount = 1;

    // Deploy into PHASE_SETUP: handleDeployFee sends ProvideWalletAddress to
    // the REAL USDT minter (fork-net resolves its code+data from mainnet).
    val escrow = deployEscrow(o1, cfg);

    // TEP-89 discovery against the real minter's code: the minter computed
    // the escrow's jetton-wallet address ITSELF (not our
    // JettonWalletMock/walletAddrFor) and responded with take_wallet_address
    // → handleTakeWalletAddress resolved the asset and moved the phase to
    // ACTIVE.
    expect(escrow.phase()).toEqual(PHASE_ACTIVE);
    expect(escrow.pendingWalletsLeft()).toEqual(0);
    expect(escrow.assetJettonWallet(0)).toBeNotNull();
}
