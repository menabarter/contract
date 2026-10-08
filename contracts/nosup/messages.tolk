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

// TEP-89 take_wallet_address. A minter answers addr_none for an owner it does
// not serve (an address in another workchain), so the wallet is read as
// `address?`: null is addr_none. Same opcode and layout as the shared
// TakeWalletAddress, which reads a plain `address`.
struct (0xd1735400) TakeWalletAddressNosup {
    queryId: uint64
    walletAddress: address?
    rest: RemainingBitsAndRefs // owner_address:(Maybe ^MsgAddress) — not read
}

type EscrowNosupBinaryMessage =
    | OwnershipAssigned
    | TakeWalletAddressNosup
    | JettonTransferNotification
    | Excesses
    | ContinueDistribution
    | ClaimAsset
