// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Incoming binary messages for the supervisor-free escrow.
// The standard TEP structures (OwnershipAssigned, NftTransfer, TEP-74/89) and
// ContinueDistribution are shared with the supervised contract and imported
// rather than copied: the test mocks import the same file, and a second
// definition of a struct in one compilation unit does not compile.
import "../messages"

// Pull delivery of a deal asset whose push delivery did not arrive.
struct (0x6d5f0006) ClaimAsset {
    queryId: uint64
    assetIndex: uint16
}

type EscrowNosupBinaryMessage =
    | OwnershipAssigned
    | TakeWalletAddress
    | JettonTransferNotification
    | Excesses
    | ContinueDistribution
    | ClaimAsset
