// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Fuzzing the conservation invariant — VALUE CONSERVATION and BINARY OUTCOME
// under an ARBITRARY order of events, ported from tests/fuzz_invariants.test.tolk
// for the supervisor-free contract.
//
// The invariant (literal meaning):
//   • value conservation: the sum of assets and GRAM across all
//     participants + the service fee equals what was deposited (minus gas);
//   • binary outcome: the terminal state is exactly one of two: DONE (all
//     assets with the opposite sides) or CANCELLED (all assets back with
//     the depositors); there is no third outcome. The one documented
//     exception is an asset still at the escrow whose delivery bounced — it
//     is owed to its rightful recipient via claim_asset, and is never
//     counted as a loss.
//   The order of deposits/cancel/kick can change WHICH of the two outcomes
//   is reached, but cannot create a third one.
//
// nosup HAS NO SUPERVISOR: there is no rescue/force_deliver escape hatch, so
// the beta suite's "stuck in supervisor custody" exception does not apply
// here. Its replacement is the claim_asset pull path: a bounced
// delivery marks the asset claimable, and the rightful recipient —
// the counterparty in EXECUTING/DONE, the depositor in CANCELLED — can always
// pull it out. The broken-recipient scenario below exercises exactly that
// recovery instead of a supervisor rescue.
//
// ASSERT PRECISION RULES: "minus gas" rules out checking TON with
// equality. So:
//   • EXACT — NFT ownership (recomputed by address) and the distribution by
//     outcome;
//   • BOUNDED (a tolerance) — the escrow's TON balance in the terminal state;
//   • An asset still at the escrow in a terminal state is acceptable only
//     when it has actually been received — it is then owed to the rightful
//     recipient, NOT counted as a loss.
//
// Reproducibility: the seed is printed by the runner; pin it via --fuzz-seed.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/testing/fuzz"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "@contracts/shared/types"
import "nosup_helpers"

const FUZZ_GRAM2: coins = ton("0.3")

// Action alphabet (indices 0..7). Every action is ALWAYS EXECUTED; a
// legitimate rejection (e.g. cancel after DONE → 410) is allowed and does
// NOT count as a failure — resilience to an arbitrary order is exactly what
// is being checked here.
const ACT_DEP_NFT0 = 0 // deposit NFT#0 (side 1)
const ACT_DEP_NFT1 = 1 // deposit NFT#1 (side 1)
const ACT_DEP_NFT2 = 2 // deposit NFT#2 (side 2)
const ACT_DEP_GRAM = 3 // side-2 GRAM deposit
const ACT_FEE1 = 4 // service_fee_owner1
const ACT_FEE2 = 5 // service_fee_owner2
const ACT_CANCEL = 6 // cancel_swap by owner 1
const ACT_KICK = 7 // kick by owner 1

struct FuzzWorld {
    escrow: EscrowFixture
    o1: Treasury
    o2: Treasury
    fw: Treasury
    nft0: address
    nft1: address
    nft2: address
}

// Deal: side 1 — 2 NFTs, side 2 — 1 NFT + GRAM. Both sides pay SERVICE_FEE.
// A small deal is chosen deliberately: fast-path, a quick run, so the
// exploration of orderings can be genuinely wide.
fun buildWorld(): FuzzWorld {
    val o1 = testing.treasury("fz-o1");
    val o2 = testing.treasury("fz-o2");
    val fw = testing.treasury("fz-fw");
    val nft0 = deployNft(o1, 96001);
    val nft1 = deployNft(o1, 96002);
    val nft2 = deployNft(o2, 96003);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, nft0);
    n1.set(1, nft1);
    var n2: map<uint16, address> = [];
    n2.set(0, nft2);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 2;
    cfg.nfts2 = n2;
    cfg.nfts2Count = 1;
    cfg.gram2Amount = FUZZ_GRAM2;
    val escrow = deployEscrow(o1, cfg);
    return FuzzWorld { escrow, o1, o2, fw, nft0, nft1, nft2 };
}

// Perform an action. The result is deliberately ignored: some actions in
// some orderings are legitimately rejected by the contract (and that is part
// of what is being checked).
fun applyAction(w: FuzzWorld, act: int) {
    if (act == ACT_DEP_NFT0) {
        sendNftToEscrow(w.o1, w.nft0, w.escrow.address, ton("0.2"), 0);
        return;
    }
    if (act == ACT_DEP_NFT1) {
        sendNftToEscrow(w.o1, w.nft1, w.escrow.address, ton("0.2"), 1);
        return;
    }
    if (act == ACT_DEP_NFT2) {
        sendNftToEscrow(w.o2, w.nft2, w.escrow.address, ton("0.2"), 2);
        return;
    }
    if (act == ACT_DEP_GRAM) {
        w.escrow.sendText(w.o2.address, "deposit_ton2", FUZZ_GRAM2 + ton("0.05"));
        return;
    }
    if (act == ACT_FEE1) {
        w.escrow.sendText(w.o1.address, "service_fee_owner1", SERVICE_FEE);
        return;
    }
    if (act == ACT_FEE2) {
        w.escrow.sendText(w.o2.address, "service_fee_owner2", SERVICE_FEE);
        return;
    }
    if (act == ACT_CANCEL) {
        w.escrow.sendText(w.o1.address, "cancel_swap", ton("0.1"));
        return;
    }
    // ACT_KICK
    w.escrow.sendText(w.o1.address, "kick", ton("0.1"));
}

// 6 actions required to reach DONE (all deposits + both fees).
fun requiredAction(i: int): int {
    if (i == 0) {
        return ACT_DEP_NFT0;
    }
    if (i == 1) {
        return ACT_DEP_NFT1;
    }
    if (i == 2) {
        return ACT_DEP_NFT2;
    }
    if (i == 3) {
        return ACT_DEP_GRAM;
    }
    if (i == 4) {
        return ACT_FEE1;
    }
    return ACT_FEE2;
}

// Which side deposited the asset at this world's fixed registry index
// (0,1 → side 1's two NFTs; 2 → side 2's one NFT — see buildWorld).
fun depositSideOf(idx: int): int {
    return idx < 2 ? 1 : 2;
}

// True if the NFT at registry index `idx` is still at the escrow but has
// actually been received — it is then owed to its rightful recipient via
// claim_asset, not lost. There is no supervisor/rescue exception in nosup
// (unlike the beta suite this was ported from): this is the only allowance
// for an asset that stays on the contract past a terminal state.
fun assetOwedAtEscrow(w: FuzzWorld, idx: int): bool {
    val (received, _claimable, _bounces) = w.escrow.assetStatus(idx);
    return received;
}

// ── Checking the conservation invariant ──
fun checkConservation(w: FuzzWorld) {
    val phase = w.escrow.phase();
    val ow0 = readMockOwner(w.nft0);
    val ow1 = readMockOwner(w.nft1);
    val ow2 = readMockOwner(w.nft2);
    val e = w.escrow.address;
    val terminal = phase == PHASE_DONE || phase == PHASE_CANCELLED;

    // (A) CONSERVATION (exact): every NFT exists and belongs to one of the
    // allowed holders. Holders: the depositor, the escrow (in progress, or —
    // after a terminal state — only if it is actually owed there), the
    // opposite side (after DONE).
    val ok0 = ow0 == w.o1.address || ow0 == w.o2.address ||
        (ow0 == e && (!terminal || assetOwedAtEscrow(w, 0)));
    val ok1 = ow1 == w.o1.address || ow1 == w.o2.address ||
        (ow1 == e && (!terminal || assetOwedAtEscrow(w, 1)));
    val ok2 = ow2 == w.o2.address || ow2 == w.o1.address ||
        (ow2 == e && (!terminal || assetOwedAtEscrow(w, 2)));
    expect(ok0).toBeTrue();
    expect(ok1).toBeTrue();
    expect(ok2).toBeTrue();

    // (B) BINARY: the phase is only from the legal set, no third outcome exists.
    val phaseOk = phase == PHASE_SETUP || phase == PHASE_ACTIVE || phase == PHASE_EXECUTING ||
        phase == PHASE_DONE ||
        phase == PHASE_CANCELLED;
    expect(phaseOk).toBeTrue();

    if (phase == PHASE_DONE) {
        // DONE outcome: every asset is with the opposite side, or still at
        // the escrow but owed to it (recoverable via claim_asset). None of
        // the three plain fuzz tests below ever enable a reject, so this
        // escrow-held branch is not expected to trigger in practice — the
        // check stays sound if it ever does.
        expect(ow0 == w.o2.address || (ow0 == e && assetOwedAtEscrow(w, 0))).toBeTrue();
        expect(ow1 == w.o2.address || (ow1 == e && assetOwedAtEscrow(w, 1))).toBeTrue();
        expect(ow2 == w.o1.address || (ow2 == e && assetOwedAtEscrow(w, 2))).toBeTrue();
    } else if (phase == PHASE_CANCELLED) {
        // CANCELLED outcome: every asset is back with its depositor, or
        // still at the escrow but owed to it.
        expect(ow0 == w.o1.address || (ow0 == e && assetOwedAtEscrow(w, 0))).toBeTrue();
        expect(ow1 == w.o1.address || (ow1 == e && assetOwedAtEscrow(w, 1))).toBeTrue();
        expect(ow2 == w.o2.address || (ow2 == e && assetOwedAtEscrow(w, 2))).toBeTrue();
    } else {
        // Not terminal: an asset is either with its depositor or at the
        // escrow — but NEVER with the opposite side (delivery before the
        // terminal state is impossible).
        expect(ow0 == w.o1.address || ow0 == e).toBeTrue();
        expect(ow1 == w.o1.address || ow1 == e).toBeTrue();
        expect(ow2 == w.o2.address || ow2 == e).toBeTrue();
    }

    // (C) TON in the terminal state (BOUNDED, a tolerance): after
    // DONE/CANCELLED the escrow is swept, i.e. value does not stick to the
    // contract. The upper tolerance allows for dust/negligible remainders;
    // equality to zero cannot be required (see the precision rules above).
    if (terminal) {
        val st = testing.getAccountState(e);
        if (st != null) {
            val bal = st.storage.balance.grams;
            expect(bal <= ton("0.05")).toBeTrue();
        }
    }
}

// ── Fuzz tests ──

// 4 actions: a wide exploration of short prefixes (including invalid orderings).
@test.fuzz(64)
get fun `test fuzz conservation:value conservation and binary outcome (4 actions)`(
    a: int,
    b: int,
    c: int,
    d: int,
) {
    val w = buildWorld();
    applyAction(w, fuzz.bound(a, 0, 7));
    applyAction(w, fuzz.bound(b, 0, 7));
    applyAction(w, fuzz.bound(c, 0, 7));
    applyAction(w, fuzz.bound(d, 0, 7));
    checkConservation(w);
}

// 6 actions: longer — reaches a terminal state more often (all deposits + fee + cancel/kick).
@test.fuzz(64)
get fun `test fuzz conservation:longer sequences reach terminal states (6 actions)`(
    a: int,
    b: int,
    c: int,
    d: int,
    e: int,
    f: int,
) {
    val w = buildWorld();
    applyAction(w, fuzz.bound(a, 0, 7));
    applyAction(w, fuzz.bound(b, 0, 7));
    applyAction(w, fuzz.bound(c, 0, 7));
    applyAction(w, fuzz.bound(d, 0, 7));
    applyAction(w, fuzz.bound(e, 0, 7));
    applyAction(w, fuzz.bound(f, 0, 7));
    checkConservation(w);
}

// Targeted: the full deposit set in ARBITRARY order (permutations of the 6
// required actions) + one arbitrary action — checks that the path to DONE
// does not depend on order, and that an intruding cancel/kick produces a
// LEGAL second outcome, not a third one.
@test.fuzz(64)
get fun `test fuzz conservation:full deposit set in arbitrary order plus one intruder`(
    p: int,
    q: int,
) {
    val w = buildWorld();
    // Rotate the order by bounded(p) — a deterministic permutation of the
    // actions required for DONE (see requiredAction).
    val shift = fuzz.bound(p, 0, 5);
    val intruderAt = fuzz.bound(q, 0, 6);
    var i = 0;
    while (i < 6) {
        if (i == intruderAt) {
            // The intruder: cancel or kick (by the parity of the shift).
            applyAction(w, shift % 2 == 0 ? ACT_CANCEL : ACT_KICK);
        }
        applyAction(w, requiredAction((i + shift) % 6));
        i += 1;
    }
    checkConservation(w);
    // STRENGTHENING (otherwise "binary outcome" would be checked vacuously):
    // ALL 6 required actions are performed here, so a terminal state MUST be
    // reached — either DONE (auto-execution on the last deposit) or
    // CANCELLED (the intruding cancel got there first). Exactly two
    // outcomes, no third. The test is falsifiable: if the order could leave
    // the deal hanging in ACTIVE/EXECUTING, this assert would fail.
    val ph = w.escrow.phase();
    expect(ph == PHASE_DONE || ph == PHASE_CANCELLED).toBeTrue();
}

// ── Documented exception under fuzzing: claim_asset recovery ──
// A broken recipient (the mock rejects transfer) → bounce → the delivery is
// marked claimable. There is no supervisor here, so recovery is the
// claim_asset pull path, not a rescue: once the recipient's mock is
// fixed, the rightful recipient claims every index the contract reports as
// claimable, and every NFT ends up with its rightful owner for the outcome
// actually reached.
@test.fuzz(48)
get fun `test fuzz conservation:broken recipient — claim_asset recovers, not lost`(
    p: int,
) {
    val w = buildWorld();
    // NFT#2 (side 2) will go to owner 1; we break the RECIPIENT of side-1
    // assets, i.e. reject is enabled on nft0/nft1, which go to owner 2.
    val brokenFirst = fuzz.bound(p, 0, 1) == 1;
    val brokenNft = brokenFirst ? w.nft0 : w.nft1;
    val brokenIdx = brokenFirst ? 0 : 1;

    // ORDER IS MANDATORY: the mock rejects ANY NftTransfer
    // (`assert (!st.rejectTransfers) throw 999`, nft_item_mock), so enabling
    // the reject BEFORE the deposits would break the DEPOSIT itself, and
    // auto-execution would never happen at all. Break it AFTER all deposits
    // and BEFORE the trigger, so it is specifically the DISTRIBUTION that
    // fails.
    var i = 0;
    while (i < 5) {
        applyAction(w, requiredAction(i));
        i += 1;
    }
    setReject(w.o1.address, brokenNft, true);
    // The last required action pushes the conditions over the edge →
    // distribution, in which the broken asset's transfer bounces and is
    // marked claimable.
    applyAction(w, requiredAction(5));

    val terminalPhase = w.escrow.phase();
    // VERIFIED BEHAVIOR (fast-path ≤100 assets, same as beta): distribution
    // happens in ONE transaction, phase → DONE immediately, and the broken
    // transfer's bounce arrives only after finalization.
    expect(terminalPhase).toEqual(PHASE_DONE);

    // Fix the recipient, then claim every index the contract reports as
    // claimable — the replacement for supervisor rescue.
    setReject(w.o1.address, brokenNft, false);
    val claimables = w.escrow.claimableAssets();
    var r = claimables.findFirst();
    while (r.isFound) {
        val idx = r.getKey() as int;
        val side = depositSideOf(idx);
        val depositor = side == 1 ? w.o1.address : w.o2.address;
        val counterparty = side == 1 ? w.o2.address : w.o1.address;
        val recipient = terminalPhase == PHASE_CANCELLED ? depositor : counterparty;
        expect(sendClaim(recipient, w.escrow.address, idx, ton("0.1"))).toHaveAllSuccessfulTxs();
        r = claimables.iterateNext(r);
    }

    // The broken NFT actually reached exactly one claimable index (its own),
    // and the claim above delivered it — this is the falsifiable half of
    // "not lost": an empty claimables map here would mean the bounce was
    // never recorded.
    expect(claimables.get(brokenIdx as uint16).isFound).toEqual(true);

    // Every NFT is now with its rightful owner for the outcome actually
    // reached (DONE → opposite side, CANCELLED → depositor). No asset is
    // left stranded, and none was ever counted as lost.
    val ow0 = readMockOwner(w.nft0);
    val ow1 = readMockOwner(w.nft1);
    val ow2 = readMockOwner(w.nft2);
    if (terminalPhase == PHASE_CANCELLED) {
        expect(ow0).toEqual(w.o1.address);
        expect(ow1).toEqual(w.o1.address);
        expect(ow2).toEqual(w.o2.address);
    } else {
        expect(ow0).toEqual(w.o2.address);
        expect(ow1).toEqual(w.o2.address);
        expect(ow2).toEqual(w.o1.address);
    }
}
