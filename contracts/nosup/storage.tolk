// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Phases. SETUP is used when a deal involves jettons — jetton deals deploy
// into PHASE_SETUP and wait for TEP-89 discovery of all unique minters (see
// handleDeployFee/handleTakeWalletAddress in escrow_nosup_beta_v1.tolk); NFT-only
// deals (pendingWallets == 0) still deploy straight into ACTIVE.
const PHASE_SETUP = 0
const PHASE_ACTIVE = 1
const PHASE_EXECUTING = 2 // set only for large deals routed through the batch-distribution engine (see Storage.executeSwap in escrow_nosup_beta_v1.tolk)
const PHASE_DONE = 3
const PHASE_CANCELLED = 4

// User-facing economics: what a deal costs its participants. DO NOT change
// these — every deployed deal's arithmetic is calibrated against them, and a
// change also moves the code hash and therefore every deal address.
const SERVICE_FEE = ton("0.1")
const NFT_TRANSFER_VALUE = ton("0.03")
const DUST = ton("0.003")

// Gas cost is stored in GAS UNITS (config-independent), converted to TON via
// calculateGasFee (GETGASFEE) against the CURRENT network config (the same
// pattern as TON's reference stablecoin contract). The units correspond to
// the intended 0.003/0.0006 TON at a price of 66.67 nanoton/unit
// (4369067/2^16): 45000 ≈ 0.003, 9000 ≈ 0.0006.
// Margin over measured consumption (gas ≈ 18445 + 4231×N) is preserved:
// 2.44× (base), 2.13× (per send). If the gas price changes via the network
// config, the reserve recalculates itself — the margin principle "reserve ≥
// actual cost" does not depend on the constants staying up to date.
// BASECHAIN is already defined in stdlib (common.tolk) — reused, not duplicated.
const EXEC_GAS_UNITS_BASE = 45000
const EXEC_GAS_UNITS_PER_SEND = 9000
const RETURN_TRANSFER_VALUE = ton("0.03")

// Value for each outgoing jetton transfer — pricier than NFT (two hops: our
// wallet -> internal_transfer -> the recipient's wallet)
const JETTON_TRANSFER_VALUE = ton("0.05")
// value for each TEP-89 provide_wallet_address to a unique minter (SETUP);
// a jetton deal's deploy transaction must carry
// 0.05 + PROVIDE_WALLET_VALUE × <number of unique minters>
const PROVIDE_WALLET_VALUE = ton("0.02")

// handleDeployFee scans ALL assetsCount entries (not just jetton ones) on
// every deploy_fee in PHASE_SETUP, so the deploy value must scale with the
// TOTAL asset count — not with the number of unique minters. Pricing it from
// minters alone leaves a jetton deal short of gas at 38-39 total assets
// (action_result_code=37, "Not enough Toncoin"), because the per-entry scan
// is paid for by nobody.
// Hence the deploy value adds calculateGasFee(BASECHAIN,
// DEPLOY_GAS_UNITS_PER_ASSET × assetsCount) on top of the flat fee, the same
// gas-units pattern as EXEC_GAS_UNITS_* above.
// Measured with one minter owning every asset — the worst case for this
// scan: total=10 -> 17311 gas, total=40 -> 53331 gas, total=100 -> 127421
// gas. Linear model (least squares): gas ≈ 4768 + 1225×N; the intercept is
// already covered with margin by the flat 0.05 TON, so no separate BASE
// constant is needed. Margin ≥2× over the measured per-asset cost (1225):
// chose 3000 (≈2.45×, the same margin style as EXEC_GAS_UNITS_PER_SEND).
const DEPLOY_GAS_UNITS_PER_ASSET = 3000

// The same scaling problem recurs one level deeper in the cascade (deploy ->
// ProvideWalletAddress -> TakeWalletAddress), and it is the one that bites
// first: a 100-asset deal owned by a single minter fails in the minter's
// TakeWalletAddress response, not in handleDeployFee.
// handleTakeWalletAddress (below in this file) scans all n assets and calls
// `.set()` on EVERY match — legitimate work, it resolves jettonWallet — but a
// flat PROVIDE_WALLET_VALUE does not scale with how many assets belong to the
// queried minter.
// Measured, isolated call, one minter owning every asset (worst case):
// total=10 -> 46422 gas, total=40 -> 214172 gas, total=100 -> 597172 gas.
// Growth is slightly faster than linear: each `.set()` gets pricier as the
// dictionary tree deepens.
// A full 2× margin over the 100-total figure (597172×2 = 1194344) is
// physically unreachable — it is ABOVE the hard compute ceiling for an
// ordinary transaction (1,000,000 gas, GasPricesExtended.gasLimit, see
// .acton/emulation/config.tolk), and no attached value can buy more than that
// ceiling. Rather than claim a margin that cannot exist, this takes the
// largest safe headroom UNDER the ceiling: 9000 gas/asset, which at total=100
// means 900,000 gas — margin ≈1.51× over the measured 597172, leaving 100,000
// gas below the hard ceiling.
// 9000 is not a fresh guess: it is the same per-`.set()` cost measured for
// Storage.executeSwapSingleTx in escrow_nosup_beta_v1.tolk. Applied in handleDeployFee to
// the value of each ProvideWalletAddress, on top of PROVIDE_WALLET_VALUE.
const TAKE_WALLET_GAS_UNITS_PER_ASSET = 9000

// Error codes. The numeric values are part of the wire contract — integrators
// match on them — so they are pinned by tests and must not be renumbered.
enum Errors {
    NotOwner1 = 401
    NotOwner2 = 402
    NotOwners = 403
    NotRecipient = 405  // claim_asset from anyone but the asset's rightful recipient
    AlreadyFinalized = 410
    NotEnoughTon1 = 420
    NotEnoughTon2 = 421
    ServiceFee1 = 422
    ServiceFee2 = 423
    NftsNotReceived = 424
    InsufficientBalance = 430
    BadAssetIndex = 431 // claim_asset on an index outside the registry
    NotClaimable = 432  // claim_asset on an asset that is not currently claimable
    UnknownOp = 0xFFFF
}

// ── Reserved queryId sentinels ──
// Outgoing NFT/jetton transfers carry the asset's registry index as their
// queryId, and onBouncedMessage reads it back to decide which asset bounced.
// Transfers that are NOT registry assets must therefore use a queryId that
// can never be mistaken for an index: onBouncedMessage ignores any bounce at
// or above QUERY_ID_NON_ASSET. Anything sent with a literal 0 would be
// indistinguishable from a bounce of asset index 0.
// The registry is keyed by uint16, so reserving the top values costs theoretically-addressable indices that no real deal can reach.
const QUERY_ID_NON_ASSET = 0xFFFE // jetton excess refunds

// ── Batch distribution (self-trigger) ──
// Batch distribution engine, shared by execute and cancel. A
// batch sends ≤ BATCH_MAX_SENDS transfers per transaction, with progress
// tracked by a SINGLE write to the dist cell per batch: a per-asset
// assets.set in the distribution loop would cost ≈9000 gas/asset.
// K = 50 is deliberately conservative; ≥3× margin: 50 sends ≈
// 50×4231 + 18445 ≈ 230k gas against a 1M ceiling (limits:
// docs.ton.org/foundations/limits).
const FAST_PATH_MAX_ASSETS = 100 // <=100 assets uses the single-transaction path (proven up to 231/154)
const BATCH_MAX_SENDS = 50
// GASCONSUMED safety valve (TVM 2023.07, 26 gas/call; in Tolk —
// getGasConsumedAtTheMoment, stdlib gas-payments.tolk): the batch stops
// early once compute has eaten this much — the remainder ships in the next
// batch. 600k out of 1M: 400k reserved for the transaction tail (dist
// write, continue message, action serialization) — errs only on the safe
// side.
const BATCH_GAS_SOFT_CAP = 600000
// Gas reserve surcharge for EACH additional batch: base for a new compute
// phase (45000) + one dist write (9000) + headroom for the continue-fwd
// ≈ 60000 units.
const BATCH_EXTRA_GAS_UNITS = 60000
// value of the continue_distribution self-message: dest = the contract
// itself, so the value returns to the balance on arrival (only the fwd fee
// is spent); it bounces on failure (BounceMode.Only256BitsOfBody in the
// actual send) — a failed batch returns the value, and a kick resumes from
// the same point.
const CONTINUE_MSG_VALUE = ton("0.05")

// Delivery modes (who receives the batch):
const DIST_IDLE = 0 // no delivery in progress
const DIST_EXECUTE = 1 // execution: to the opposite side (phase EXECUTING)
const DIST_CANCEL = 2 // cancel_swap: to depositors, with a sweep at the end (phase CANCELLED)

struct DistState {
    mode: uint3
    cursor: uint16 // next registry index to process
}

struct Asset {
    kind: uint2            // 0 = NFT, 1 = Jetton
    ownerSide: uint2       // 1 | 2 — which side is depositing
    addr: address          // NFT item address (or jetton minter address)
    jettonWallet: address? // null for NFT assets
    amount: coins          // 0 for NFT assets
    received: bool
    // Reserved: initialized to false and never assigned — delivery progress is
    // tracked by DistState.cursor. Kept because dropping it would change the
    // storage layout, and with it every deal address.
    sent: bool
    // saturating count of bounced deliveries (diagnostics)
    bounces: uint4
    // Set when an outgoing transfer of this asset bounced back to the escrow;
    // cleared when claim_asset sends it again. Jettons can only be claimed
    // while this is set.
    claimable: bool
}

struct GramState {
    gram1Amount: coins
    gram2Amount: coins
    gram1Received: coins
    gram2Received: coins
    gram1DepositReserve: coins // value attached to side 1's NFT deposits
    gram2DepositReserve: coins
    serviceFee1: coins
    serviceFee2: coins
}

struct Storage {
    swapId: uint64
    phase: uint3
    owner1: address
    owner2: address
    feeWallet: address
    assetsCount: uint16
    required1Count: uint16
    required2Count: uint16
    received1Count: uint16
    received2Count: uint16
    pendingWallets: uint16   // outstanding TEP-89 minter discoveries (0 for NFT-only deals)
    jettonsCount: uint16     // total number of jetton assets (both sides)
    receivedJettons1: uint16 // of those, how many side 1 has received (used by the cancel formulas)
    receivedJettons2: uint16
    assets: map<uint16, Asset>
    grams: Cell<GramState>   // ref: 8 coins fields don't fit in the root alongside 3 addresses
    dist: Cell<DistState>    // batch distribution state
}

fun Storage.load(): Storage {
    return Storage.fromCell(contract.getData());
}

fun Storage.save(self) {
    contract.setData(self.toCell());
}
