// GENERATED from tests/nosup/plain_transfer.test.tolk by ts-tests/gen-v2-tests.ts — edit the source, then run npm run gen:v2.
// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// A bare transfer (empty body) from an owner is a TON deposit and follows the
// same phase rule as deposit_ton1/2. A stranger's bare transfer is forwarded
// to the fee wallet in any phase.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowV2.gen"
import "@contracts/shared/types"
import "@contracts/v2/storage"
import "v2_helpers"

get fun `test owner bare transfer to a finished deal bounces`() {
    val escrow = runFullSwap(1, 1, 0, 0, ton("0.20"));
    val o1 = testing.treasury("rf-o1");
    val before = testing.getAccountBalance(escrow.address);
    val res = net.send(
        o1.address,
        createMessage({ bounce: BounceMode.Only256BitsOfBody, value: ton("1"), dest: escrow.address }),
    );
    expect(res).toHaveFailedTx({ to: escrow.address, exitCode: Errors.AlreadyFinalized });
    expect(testing.getAccountBalance(escrow.address) <= before).toEqual(true);
}

get fun `test stranger bare transfer to a finished deal goes to the fee wallet`() {
    val escrow = runFullSwap(1, 1, 0, 0, ton("0.20"));
    val fw = testing.treasury("rf-fw");
    val stranger = testing.treasury("pt-stranger");
    val res = net.send(
        stranger.address,
        createMessage({ bounce: BounceMode.Only256BitsOfBody, value: ton("1"), dest: escrow.address }),
    );
    expect(res).toHaveAllSuccessfulTxs();
    expect(res).toHaveTx({ from: escrow.address, to: fw.address });
}

get fun `test owner bare transfer to an active deal still credits the side`() {
    val f = setup1x1("pt-act", 73001);
    val res = net.send(
        f.o1.address,
        createMessage({ bounce: BounceMode.Only256BitsOfBody, value: ton("0.5"), dest: f
                .escrow
                .address }),
    );
    expect(res).toHaveAllSuccessfulTxs();
    expect(f.escrow.gramState().gram1Received).toEqual(ton("0.5"));
}
