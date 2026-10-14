// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Helpers of the SwapEscrowV2 supervisor tests (tests/v2/sup_*.test.tolk).
import "@stdlib/gas-payments"
import "@acton/emulation/testing"
import "@contracts/shared/types"

// The supervisor of every V2 test deal (v2_helpers.testSupervisor).
fun supAddr(): address {
    return testing.treasury("v2-sup").address;
}

// Mirrors Storage.emergencyChainReserve: the later batches of a supervisor's
// chain run on the escrow's balance, so the attachment pays for them.
fun chainReserve(registrySize: int, received: int): coins {
    val walkUnits = SKIP_GAS_UNITS_PER_ENTRY * (registrySize - received);
    val batches = (received + BATCH_MAX_SENDS - 1) / BATCH_MAX_SENDS +
        (walkUnits + BATCH_GAS_SOFT_CAP - 1) / BATCH_GAS_SOFT_CAP;
    return calculateGasFee(BASECHAIN, EXEC_GAS_UNITS_PER_SEND * received) +
        calculateGasFee(BASECHAIN, BATCH_EXTRA_GAS_UNITS * batches + walkUnits) +
        calculateGasFee(BASECHAIN, CONTINUE_GAS_UNITS) +
        calculateForwardFee(BASECHAIN, 1023, 1);
}
