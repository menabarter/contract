// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Fuzzing the conservation invariant — VALUE CONSERVATION and BINARY OUTCOME
// under an ARBITRARY order of events.
//
// The invariant (literal meaning):
//   • value conservation: the sum of assets and GRAM across all
//     participants + the service fee equals what was deposited (minus gas);
//   • binary outcome: the terminal state is exactly one of two: DONE (all
//     assets with the opposite sides) or CANCELLED (all assets back with
//     the depositors); there is no third outcome — up to the documented
//     exceptions to "every received asset is delivered or returned"
//     (abandoned, a jetton failure on the second
//     hop), which move a SPECIFIC asset into supervisor rescue without
//     changing the outcome for the rest.
//   The order of deposits/cancel/kick can change WHICH of the two outcomes
//   is reached, but cannot create a third one.
//
// ASSERT PRECISION RULES: "minus gas" rules out checking TON with
// equality. So:
//   • EXACT — NFT ownership (recomputed by address) and the distribution by
//     outcome;
//   • BOUNDED (a tolerance) — the escrow's TON balance in the terminal state;
//   • A SEPARATE term — assets stuck in rescue (documented exceptions),
//     NOT counted as a "loss".
//
// STATE FRESHNESS on every run is CHECKED by a separate probe: the mock
// address is deterministic, and the assert "on entry the NFT is with the
// depositor" held across every run, even though every run transferred the
// NFT to the escrow.
//
// Reproducibility: the seed is printed by the runner; pin it via --fuzz-seed.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/testing/fuzz"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/SwapEscrow.gen"
import "escrow_helpers"

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
    sup: Treasury
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
    val sup = testing.treasury("fz-sup");
    val nft0 = deployNft(o1, 96001);
    val nft1 = deployNft(o1, 96002);
    val nft2 = deployNft(o2, 96003);
    var cfg = makeBasicConfig(o1, o2, fw, sup);
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
    return FuzzWorld { escrow, o1, o2, fw, sup, nft0, nft1, nft2 };
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

// Enable/disable the mock's rejection of incoming transfers (a broken recipient).
fun setNftReject(sender: address, nft: address, reject: bool): SendResultList {
    val m = createMessage({
        bounce: false,
        value: ton("0.05"),
        dest: nft,
        body: SetNftReject {
            queryId: 0,
            reject,
        },
    });
    return net.send(sender, m);
}

fun sendForceDeliverFz(
    sender: address,
    escrow: address,
    idx: int,
    fallback: bool,
): SendResultList {
    val m = createMessage({
        bounce: true,
        value: ton("0.1"),
        dest: escrow,
        body: ForceDeliver {
            queryId: 0,
            assetIndex: idx as uint16,
            fallback,
        },
    });
    return net.send(sender, m);
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

// ── Checking the conservation invariant ──
fun checkConservation(w: FuzzWorld) {
    val phase = w.escrow.phase();
    val ow0 = readMockOwner(w.nft0);
    val ow1 = readMockOwner(w.nft1);
    val ow2 = readMockOwner(w.nft2);
    val e = w.escrow.address;

    // (A) CONSERVATION (exact): every NFT exists and belongs to one of the
    // allowed holders. It cannot "get lost" (go to a third party). Holders:
    // the depositor, the escrow (in progress), the opposite side (after
    // DONE), the supervisor (a documented exception — rescue).
    val ok0 = ow0 == w.o1.address || ow0 == e || ow0 == w.o2.address || ow0 == w.sup.address;
    val ok1 = ow1 == w.o1.address || ow1 == e || ow1 == w.o2.address || ow1 == w.sup.address;
    val ok2 = ow2 == w.o2.address || ow2 == e || ow2 == w.o1.address || ow2 == w.sup.address;
    expect(ok0).toBeTrue();
    expect(ok1).toBeTrue();
    expect(ok2).toBeTrue();

    // (B) BINARY: the phase is only from the legal set, no third outcome exists.
    val phaseOk = phase == PHASE_SETUP || phase == PHASE_ACTIVE || phase == PHASE_EXECUTING ||
    phase == PHASE_DONE ||
    phase == PHASE_CANCELLED;
    expect(phaseOk).toBeTrue();

    if (phase == PHASE_DONE) {
        // DONE outcome: ALL assets with the opposite sides, uniformly.
        expect(ow0).toEqual(w.o2.address);
        expect(ow1).toEqual(w.o2.address);
        expect(ow2).toEqual(w.o1.address);
    } else if (phase == PHASE_CANCELLED) {
        // CANCELLED outcome: ALL assets with the depositors, uniformly
        // (deposited assets are returned, undeposited ones never left).
        expect(ow0).toEqual(w.o1.address);
        expect(ow1).toEqual(w.o1.address);
        expect(ow2).toEqual(w.o2.address);
    } else {
        // Not terminal: an asset is either with its depositor or at the
        // escrow — but NEVER with the opposite side (delivery before the
        // terminal state is impossible).
        expect(ow0 == w.o1.address || ow0 == e).toBeTrue();
        expect(ow1 == w.o1.address || ow1 == e).toBeTrue();
        expect(ow2 == w.o2.address || ow2 == e).toBeTrue();
    }

    // (C) TON in the terminal state (BOUNDED, a tolerance): after
    // DONE/CANCELLED the escrow is swept (mode 128 in finalization), i.e.
    // value does not stick to the contract. The upper tolerance allows for
    // dust/negligible remainders; equality to zero cannot be required (see
    // the precision rules above).
    if (phase == PHASE_DONE || phase == PHASE_CANCELLED) {
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

// ── Documented exceptions under fuzzing ──
// A broken recipient (the mock rejects transfer) → bounce → retry →
// kick/force_deliver. Here the conservation invariant is checked in its FULL form: an
// asset that ends up in rescue (abandoned / bounce after finalization) is
// accounted for as a SEPARATE term and is NOT counted as a loss; the
// outcome for the REMAINING assets stays uniform.
@test.fuzz(48)
get fun `test fuzz conservation:broken recipient — rescue accounted, not lost`(
    p: int,
    q: int,
) {
    val w = buildWorld();
    // NFT#2 (side 2) will go to owner 1; we break the RECIPIENT of side-1
    // assets, i.e. reject is enabled on nft0/nft1, which go to owner 2.
    // The mock rejects the transfer, so distributing these assets will bounce.
    val brokenFirst = fuzz.bound(p, 0, 1) == 1;
    val brokenNft = brokenFirst ? w.nft0 : w.nft1;

    // ORDER IS MANDATORY: the mock rejects ANY NftTransfer
    // (`assert (!st.rejectTransfers) throw 999`, nft_item_mock), so
    // enabling the reject BEFORE the deposits is not allowed — the DEPOSIT
    // itself would break, and auto-execution would never happen at all (the
    // phase would stay ACTIVE — exactly what the first run of this test
    // caught). Break it AFTER all deposits and BEFORE the trigger, so it is
    // specifically the DISTRIBUTION that fails.
    var i = 0;
    while (i < 5) {
        applyAction(w, requiredAction(i));
        i += 1;
    }
    expect(setNftReject(w.o1.address, brokenNft, true)).toHaveAllSuccessfulTxs();
    // The last required action pushes the conditions over the edge →
    // distribution, in which the broken asset's transfer will bounce.
    applyAction(w, requiredAction(5));

    // An arbitrary recovery sequence by the supervisor/owner.
    // VERIFIED BEHAVIOR (fast-path ≤100 assets): distribution happens in ONE
    // transaction, phase → DONE immediately, and the broken transfer's
    // bounce arrives ONLY AFTER finalization, with dist.mode == IDLE. This
    // is exactly the documented exception: the asset stays on the contract
    // and can ONLY be pulled out via supervisor rescue. So kick here
    // fundamentally does NOT redeliver (there is nothing to continue — mode
    // is IDLE), and that is correct, not a defect.
    val recovery = fuzz.bound(q, 0, 3);
    if (recovery == 1) {
        applyAction(w, ACT_KICK);
    } else if (recovery == 2) {
        applyAction(w, ACT_KICK);
        sendForceDeliverFz(w.sup.address, w.escrow.address, brokenFirst ? 0 : 1, false);
    } else if (recovery == 3) {
        // Fix the recipient and finish with a kick.
        expect(setNftReject(w.o1.address, brokenNft, false)).toHaveAllSuccessfulTxs();
        applyAction(w, ACT_KICK);
    }

    val ow0 = readMockOwner(w.nft0);
    val ow1 = readMockOwner(w.nft1);
    val ow2 = readMockOwner(w.nft2);
    val e = w.escrow.address;

    // (A) CONSERVATION: no asset has disappeared or gone to a third party.
    expect(
        ow0 == w.o1.address || ow0 == e || ow0 == w.o2.address || ow0 == w.sup.address,
    ).toBeTrue();
    expect(
        ow1 == w.o1.address || ow1 == e || ow1 == w.o2.address || ow1 == w.sup.address,
    ).toBeTrue();
    expect(
        ow2 == w.o2.address || ow2 == e || ow2 == w.o1.address || ow2 == w.sup.address,
    ).toBeTrue();

    // (B) The outcome did NOT become a "third one": despite the broken
    // recipient, the deal reaches DONE (an exception for one asset does not
    // block the outcome). Falsifiable: if the broken asset dropped the
    // whole deal, this would be ACTIVE/EXECUTING.
    expect(w.escrow.phase()).toEqual(PHASE_DONE);

    // (C) UNIFORMITY for the REMAINING assets: the non-broken ones are delivered normally.
    expect(ow2).toEqual(w.o1.address);
    if (brokenFirst) {
        expect(ow1).toEqual(w.o2.address);
    } else {
        expect(ow0).toEqual(w.o2.address);
    }

    // (D) DOCUMENTED EXCEPTION — as a SEPARATE term, not a loss: the broken
    // asset is stuck on the contract, and it IS RECOVERABLE via supervisor
    // rescue. This is the actual meaning of "rescue accounted, not lost" —
    // verified, not just asserted in words.
    val brokenOwner = readMockOwner(brokenNft);
    if (brokenOwner == e) {
        // First, "fix" the NFT contract: while it rejects EVERY transfer
        // (throw 999), no operation — including supervisor rescue — can
        // move the asset out (verified: rescue bounces too). This is a
        // property of the EXTERNAL contract, not the escrow. The point of
        // the invariant: once transfers work again, the asset IS
        // RECOVERABLE, and therefore not lost.
        expect(setNftReject(w.o1.address, brokenNft, false)).toHaveAllSuccessfulTxs();
        expect(
            w.escrow.sendRescueNft(w.sup.address, brokenNft, { value: ton("0.1") }),
        ).toHaveAllSuccessfulTxs();
        expect(readMockOwner(brokenNft)).toEqual(w.sup.address);
    } else {
        // Either delivered (the recipient was fixed in time), or already with the supervisor.
        expect(brokenOwner == w.o2.address || brokenOwner == w.sup.address).toBeTrue();
    }
}
