// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * A thin TS layer on top of the generated wrapper.
 *
 * WHY: the wrapper (wrappers-ts/SwapEscrow.gen.ts) is the interface a
 * TypeScript integrator consumes, so this layer validates exactly that
 * interface by actually executing it, rather than trusting that generated
 * code matches the contract.
 *
 * METHOD: comparing cell HASHES. The references (ts-tests/fixtures.txt) are
 * captured by scripts/gen_ts_fixtures.tolk using Tolk — the same code that
 * actually goes over the network and has been proven by live runs. A hash
 * match means the cells are bit-for-bit identical (hash is a cryptographic
 * binding to content and references), so this check is stronger than a
 * round-trip: a round-trip wouldn't catch a matched error in a store/load
 * pair, but a cross-language hash comparison would.
 *
 * Run: npm test   (update the references: npm run fixtures)
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { Address, beginCell, Cell } from '@ton/core';
import {
    ContinueDistribution,
    ForceDeliver,
    JettonTransfer,
    NftTransfer,
    RescueNft,
    SwapEscrow,
} from '../wrappers-ts/SwapEscrow.gen';

const here = __dirname;

// ── references ──
const fixtures = new Map<string, string>();
for (const line of readFileSync(join(here, 'fixtures.txt'), 'utf8').split('\n')) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const [name, value] = t.split(/\s+/);
    fixtures.set(name, value);
}

// Tolk prints hex via {:x} WITHOUT leading zeros — normalize to 64 characters.
const expectHash = (name: string): string => {
    const v = fixtures.get(name);
    if (!v) throw new Error(`fixture '${name}' is missing from fixtures.txt`);
    return v.padStart(64, '0');
};

const hashOf = (c: Cell): string => c.hash().toString('hex');

let passed = 0;
let failed = 0;

function check(name: string, cell: Cell): void {
    const want = expectHash(name);
    const got = hashOf(cell);
    if (want === got) {
        console.log(`  ✓ ${name}`);
        passed++;
    } else {
        console.log(`  ✗ ${name}\n      Tolk: ${want}\n      TS:   ${got}`);
        failed++;
    }
}

function checkEq(name: string, want: unknown, got: unknown): void {
    if (want === got) {
        console.log(`  ✓ ${name}`);
        passed++;
    } else {
        console.log(`  ✗ ${name}\n      want: ${String(want)}\n      got:  ${String(got)}`);
        failed++;
    }
}

const a1 = Address.parse(fixtures.get('addr1')!);
const a2 = Address.parse(fixtures.get('addr2')!);
const a3 = Address.parse(fixtures.get('addr3')!);

// Deposit hint: either-0 + uint16 asset_index. The frontend MUST put
// asset_index into forward_payload, or acceptance falls back to the O(n)
// path and large deals hit the ceiling.
const hintPayload = (idx: number) =>
    beginCell().storeUint(0, 1).storeUint(idx, 16).endCell().beginParse();

const textBody = (s: string) =>
    beginCell().storeUint(0, 32).storeStringTail(s).endCell();

console.log('=== Validating the TS wrapper against Tolk references ===\n');

console.log('1. Deposit bodies with a hint:');
// KEY: NftTransfer carries forwardPayload as RemainingBitsAndRefs (not a
// bool tag). If a client builds a different form, acceptance breaks. This
// catches that bit-for-bit.
check(
    'NftTransfer_hint42',
    NftTransfer.toCell(
        NftTransfer.create({
            queryId: 7n,
            newOwner: a2,
            responseDestination: a1,
            customPayload: null,
            forwardAmount: 50000000n, // 0.05 TON
            forwardPayload: hintPayload(42),
        }),
    ),
);
check(
    'JettonTransfer_hint3',
    JettonTransfer.toCell(
        JettonTransfer.create({
            queryId: 7n,
            amount: 1000000000n, // 1 jetton (9 decimals)
            destination: a2,
            responseDestination: a1,
            customPayload: null,
            forwardTonAmount: 200000000n, // 0.2 TON
            forwardPayload: hintPayload(3),
        }),
    ),
);
check('hint_payload_42_cell', beginCell().storeUint(0, 1).storeUint(42, 16).endCell());

console.log('\n2. Outbound body from the escrow (empty payload = a single 0 bit):');
check(
    'NftTransfer_zeroPayload',
    NftTransfer.toCell(
        NftTransfer.create({
            queryId: 0n,
            newOwner: a2,
            responseDestination: a1,
            customPayload: null,
            forwardAmount: 30000000n, // 0.03 TON
            forwardPayload: beginCell().storeUint(0, 1).endCell().beginParse(),
        }),
    ),
);

console.log('\n3. Opcodes (watcher/operator):');
check(
    'ContinueDistribution_q5',
    ContinueDistribution.toCell(ContinueDistribution.create({ queryId: 5n })),
);
check(
    'ForceDeliver_idx9_resend',
    ForceDeliver.toCell(
        ForceDeliver.create({ queryId: 0n, assetIndex: 9n, fallback: false }),
    ),
);
check(
    'ForceDeliver_idx9_fallback',
    ForceDeliver.toCell(
        ForceDeliver.create({ queryId: 0n, assetIndex: 9n, fallback: true }),
    ),
);
check('RescueNft', RescueNft.toCell(RescueNft.create({ nftAddr: a3 })));

console.log('\n4. Text commands (32 zero bits + ASCII):');
check('text_kick', textBody('kick'));
check('text_service_fee_owner1', textBody('service_fee_owner1'));
check('text_cancel_swap', textBody('cancel_swap'));
check('text_deploy_fee', textBody('deploy_fee'));

console.log('\n5. Round-trip parsing (deserialization by the wrapper):');
// Checks that the wrapper READS back what it wrote, and that the hint can
// be extracted — this is exactly how the backend will parse incoming bodies.
const nftCell = NftTransfer.toCell(
    NftTransfer.create({
        queryId: 7n,
        newOwner: a2,
        responseDestination: a1,
        customPayload: null,
        forwardAmount: 50000000n,
        forwardPayload: hintPayload(42),
    }),
);
const parsed = NftTransfer.fromSlice(nftCell.beginParse());
checkEq('NftTransfer.queryId', 7n, parsed.queryId);
checkEq('NftTransfer.newOwner', true, parsed.newOwner.equals(a2));
checkEq('NftTransfer.forwardAmount', 50000000n, parsed.forwardAmount);
// Parses the hint exactly like the contract does (parseAssetIndexHint): either-bit + uint16.
const hintSlice = parsed.forwardPayload;
const isRef = hintSlice.loadBit();
checkEq('hint either-bit == 0', false, isRef);
checkEq('hint asset_index == 42', 42, hintSlice.loadUint(16));

const fd = ForceDeliver.fromSlice(
    ForceDeliver.toCell(
        ForceDeliver.create({ queryId: 0n, assetIndex: 9n, fallback: true }),
    ).beginParse(),
);
// IMPORTANT FOR THE BACKEND: in the wrapper, uint16/uint64/coins are
// declared as `bigint` (see the type aliases in SwapEscrow.gen.ts). Plain
// numbers work at runtime because storeUint accepts number|bigint, but
// bigint is the type-correct choice.
checkEq('ForceDeliver.assetIndex (bigint)', 9n, fd.assetIndex);
checkEq('ForceDeliver.fallback', true, fd.fallback);

console.log('\n6. Interface required by the watcher:');
// DONE for large deals happens ASYNCHRONOUSLY, so the watcher must poll the
// getters rather than assume the deal is finalized just because the deposit
// transaction succeeded.
const proto = SwapEscrow.prototype as unknown as Record<string, unknown>;
checkEq('getPhase is present', 'function', typeof proto.getPhase);
checkEq('getDistributionProgress is present', 'function', typeof proto.getDistributionProgress);
checkEq('getReceivedCounts is present', 'function', typeof proto.getReceivedCounts);
checkEq('getCanAutoExecuteNow is present', 'function', typeof proto.getCanAutoExecuteNow);
// Error codes must be available to the backend for human-readable messages.
// IMPORTANT FOR THE BACKEND: keys in the generated map are FULLY QUALIFIED
// — 'Errors.BadAssetIndex', not 'BadAssetIndex'. The exit-code-to-text
// mapping must use exactly this key form.
const errs = (SwapEscrow as unknown as { Errors: Record<string, number> }).Errors;
checkEq("Errors['Errors.BadAssetIndex'] == 431", 431, errs['Errors.BadAssetIndex']);
checkEq("Errors['Errors.AlreadyFinalized'] == 410", 410, errs['Errors.AlreadyFinalized']);
checkEq("Errors['Errors.NotOwner1'] == 401", 401, errs['Errors.NotOwner1']);
checkEq("Errors['Errors.UnknownOp'] == 65535", 65535, errs['Errors.UnknownOp']);

// The wrapper embeds a COPY of the compiled contract in SwapEscrow.CodeCell,
// and consumers derive escrow addresses from it. Nothing else in this file
// touches that copy, so a contract change that is not followed by
// `acton wrapper SwapEscrow --ts` leaves the wrapper silently pinned to stale
// bytecode: every address it computes would be wrong, and it would deploy the
// previous contract. This is exactly what happened once — the check exists so
// it cannot happen quietly again.
console.log('\n5. Wrapper bytecode matches the current build:');
const built = JSON.parse(
    readFileSync(join(here, '..', 'build', 'SwapEscrow.json'), 'utf8'),
) as { hash: string };
checkEq(
    'SwapEscrow.CodeCell matches build/SwapEscrow.json',
    built.hash.toLowerCase(),
    hashOf(SwapEscrow.CodeCell),
);

console.log(`\n=== RESULT: ${passed} passed, ${failed} failed ===`);
if (failed > 0) process.exit(1);
