// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Settlement model: every coin that arrives is recorded against the side that
// sent it; each side pays for moving its own assets; everything else the deal
// spends — gas, service messages, the storage floor — is shared equally.
//
// Refunds are split from R, the amount actually left on the balance, using the
// per-side counters only for the DIFFERENCE between the sides:
//   refund1 = (R + N1 - N2) / 2,  refund2 = R - refund1
// where Ni is side i's contribution net of its own costs. With S the shared
// costs and U any unattributed inflow, R = N1 + N2 - S + U, so
// refund1 = N1 - S/2 + U/2: its own contribution minus half of what was shared.
// Because the total comes from the balance, overstated counters (deposit gas is
// credited gross) cannot make the split pay out more than the balance holds.
import "storage"

// Everything `side` has paid into the deal.
fun paidBy(g: GramState, side: int): coins {
    return side == 1
        ? g.gram1Received + g.serviceFee1 + g.gram1DepositReserve
        : g.gram2Received + g.serviceFee2 + g.gram2DepositReserve;
}

fun transferCost(nfts: int, jettons: int): coins {
    return NFT_TRANSFER_VALUE * nfts + JETTON_TRANSFER_VALUE * jettons;
}

// Split R between the sides. A side whose formula share falls below zero gets
// nothing and the other side gets all of R; the two always sum to R.
fun splitRefunds(r: coins, n1: coins, n2: coins): (coins, coins) {
    if (r <= 0) {
        return (0, 0);
    }
    var r1 = (r + n1 - n2) / 2;
    if (r1 < 0) {
        r1 = 0;
    }
    if (r1 > r) {
        r1 = r;
    }
    return (r1, r - r1);
}

// Cost of moving `side`'s received assets (delivery on execute, return on
// cancel — the same per-asset values either way), from the received counters.
fun Storage.ownTransferCost(self, side: int): coins {
    val total = side == 1 ? (self.received1Count as int) : (self.received2Count as int);
    val jettons = side == 1 ? (self.receivedJettons1 as int) : (self.receivedJettons2 as int);
    return transferCost(total - jettons, jettons);
}

// The same cost from the registry, before the deposits have arrived. Walks
// every entry: get-methods only.
fun Storage.registryTransferCost(self, side: int): coins {
    var nfts = 0;
    var jettons = 0;
    var r = self.assets.findFirst();
    while (r.isFound) {
        val a = r.loadValue();
        if ((a.ownerSide as int) == side) {
            if (a.kind == 1) {
                jettons += 1;
            } else {
                nfts += 1;
            }
        }
        r = self.assets.iterateNext(r);
    }
    return transferCost(nfts, jettons);
}
