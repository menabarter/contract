// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// variant:begin
// Incoming binary messages of SwapEscrowNosup.
// variant:end
// The standard TEP structures and ContinueDistribution come from ../messages,
// the escrow's own from shared/messages.
import "../messages"
import "../shared/messages"

type EscrowInMessage =
    | OwnershipAssigned
    | TakeWalletAddressNosup
    | JettonTransferNotification
    | Excesses
    | ContinueDistribution
    | ClaimAsset
    | AcceptDeal
