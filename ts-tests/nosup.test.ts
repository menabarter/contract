// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * A thin TS layer on top of the generated wrapper for SwapEscrowNosup.
 *
 * WHY: the wrapper (wrappers-ts/SwapEscrowNosup.gen.ts) is the interface a
 * TypeScript integrator consumes, so this layer validates exactly that
 * interface by actually executing it, rather than trusting that generated
 * code matches the contract.
 *
 * METHOD: comparing cell HASHES. The references (ts-tests/fixtures-nosup.txt)
 * are captured by scripts/gen_ts_fixtures_nosup.tolk using Tolk — the same
 * code that actually goes over the network and has been proven by live runs.
 * A hash match means the cells are bit-for-bit identical (hash is a
 * cryptographic binding to content and references), so this check is
 * stronger than a round-trip.
 *
 * Run: npm test   (update the references: npm run fixtures)
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { Address, Cell, Dictionary } from '@ton/core';
import {
    AcceptDeal,
    Asset,
    ClaimAsset,
    DistState,
    GramState,
    Storage,
    SwapEscrowNosup,
} from '../wrappers-ts/SwapEscrowNosup.gen';

const here = __dirname;

// ── references ──
const fixtures = new Map<string, string>();
for (const line of readFileSync(join(here, 'fixtures-nosup.txt'), 'utf8').split('\n')) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const [name, value] = t.split(/\s+/);
    fixtures.set(name, value);
}

// Tolk prints hex via {:x} WITHOUT leading zeros — normalize to 64 characters.
// An absent or unparsed fixture line is treated as a hard failure, not a pass.
const expectHash = (name: string): string => {
    const v = fixtures.get(name);
    if (!v) throw new Error(`fixture '${name}' is missing from fixtures-nosup.txt`);
    return v.padStart(64, '0');
};

const expectValue = (name: string): string => {
    const v = fixtures.get(name);
    if (!v) throw new Error(`fixture '${name}' is missing from fixtures-nosup.txt`);
    return v;
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

console.log('=== Validating the TS wrapper (SwapEscrowNosup) against Tolk references ===\n');

console.log('1. Binary messages / state cells:');
check(
    'ClaimAsset_idx7',
    ClaimAsset.toCell(ClaimAsset.create({ queryId: 0n, assetIndex: 7n })),
);
// The message the dapp builds for the one-signature flow: its claims map
// must serialize bit for bit as the contract reads it.
const claims = Dictionary.empty(Dictionary.Keys.Address(), Dictionary.Values.Address());
claims.set(
    Address.parse('0:00000000000000000000000000000000000000000000000000000000000000bb'),
    Address.parse('0:00000000000000000000000000000000000000000000000000000000000000cc'),
);
check('AcceptDeal_1claim', AcceptDeal.toCell(AcceptDeal.create({ queryId: 5n, claims })));
checkEq('AcceptDeal opcode is 0x6d5f0007', 0x6d5f0007, AcceptDeal.PREFIX);
checkEq(
    'jettonWalletStatus getter is generated',
    'function',
    typeof (SwapEscrowNosup.prototype as unknown as Record<string, unknown>).getJettonWalletStatus,
);
check(
    'DistState_idle',
    DistState.toCell(DistState.create({ mode: 0n, cursor: 0n })),
);

const claimableAsset = Asset.create({
    kind: 0n,
    ownerSide: 1n,
    addr: Address.parse('0:00000000000000000000000000000000000000000000000000000000000000aa'),
    jettonWallet: null,
    amount: 0n,
    received: true,
    walletUnverified: false,
    bounces: 1n,
    claimable: true,
});
check('Asset_nft_claimable', Asset.toCell(claimableAsset));

console.log('\n2. Deployed StateInit for the fixed 2x1 deal (no supervisor):');
// Registry order is part of the protocol: side 1's assets first, then side 2's.
const OWNER1 = Address.parse('0:1111111111111111111111111111111111111111111111111111111111111111');
const OWNER2 = Address.parse('0:2222222222222222222222222222222222222222222222222222222222222222');
const FEE_WALLET = Address.parse('0:3333333333333333333333333333333333333333333333333333333333333333');
const NFT_A = Address.parse('0:00000000000000000000000000000000000000000000000000000000000000aa');
const NFT_B = Address.parse('0:00000000000000000000000000000000000000000000000000000000000000bb');
const NFT_C = Address.parse('0:00000000000000000000000000000000000000000000000000000000000000cc');

const mkNft = (side: bigint, addr: Address): Asset =>
    Asset.create({
        kind: 0n,
        ownerSide: side,
        addr,
        jettonWallet: null,
        amount: 0n,
        received: false,
        walletUnverified: false,
        bounces: 0n,
        claimable: false,
    });

const assets = Dictionary.empty<bigint, Asset>(Dictionary.Keys.BigUint(16), {
    serialize: (v, b) => Asset.store(v, b),
    parse: (s) => Asset.fromSlice(s),
});
assets.set(0n, mkNft(1n, NFT_A));
assets.set(1n, mkNft(1n, NFT_B));
assets.set(2n, mkNft(2n, NFT_C));

const grams = {
    ref: GramState.create({
        gram1Amount: 1500000000n, // 1.5 TON
        gram2Amount: 0n,
        gram1Received: 0n,
        gram2Received: 0n,
        gram1DepositReserve: 0n,
        gram2DepositReserve: 0n,
        serviceFee1: 0n,
        serviceFee2: 0n,
    }),
};
const dist = {
    ref: DistState.create({ mode: 0n, cursor: 0n }),
};

const storage = Storage.create({
    swapId: 424242n,
    phase: 1n, // PHASE_ACTIVE
    owner1: OWNER1,
    owner2: OWNER2,
    feeWallet: FEE_WALLET,
    assetsCount: 3n,
    required1Count: 2n,
    required2Count: 1n,
    received1Count: 0n,
    received2Count: 0n,
    pendingWallets: 0n,
    jettonsCount: 0n,
    receivedJettons1: 0n,
    receivedJettons2: 0n,
    assets,
    grams,
    dist,
});

check('Storage_2x1', Storage.toCell(storage));

const escrow = SwapEscrowNosup.fromStorage(storage);
// Tolk's println("{}", address) prints the bounceable, test-only user-friendly form.
checkEq(
    'address_2x1',
    expectValue('address_2x1'),
    escrow.address.toString({ bounceable: true, testOnly: true }),
);

console.log('\n3. Error enum (no supervisor):');
const errs = (SwapEscrowNosup as unknown as { Errors: Record<string, number> }).Errors;
checkEq("Errors['Errors.NotRecipient'] == 405", 405, errs['Errors.NotRecipient']);
checkEq("Errors['Errors.NotClaimable'] == 432", 432, errs['Errors.NotClaimable']);
checkEq("Errors['Errors.SideUnderfunded1'] == 433", 433, errs['Errors.SideUnderfunded1']);
checkEq("Errors['Errors.SideUnderfunded2'] == 434", 434, errs['Errors.SideUnderfunded2']);
checkEq("Errors['Errors.NotSupervisor'] is absent", undefined, errs['Errors.NotSupervisor']);

// The wrapper embeds a COPY of the compiled contract in
// SwapEscrowNosup.CodeCell, and consumers derive escrow addresses from it.
// Nothing else in this file touches that copy, so a contract change that is
// not followed by `acton wrapper SwapEscrowNosup --ts` leaves the wrapper
// silently pinned to stale bytecode: every address it computes would be
// wrong, and it would deploy the previous contract.
console.log('\n4. Wrapper bytecode matches the current build:');
const built = JSON.parse(
    readFileSync(join(here, '..', 'build', 'SwapEscrowNosup.json'), 'utf8'),
) as { hash: string };
checkEq(
    'SwapEscrowNosup.CodeCell matches build/SwapEscrowNosup.json',
    built.hash.toLowerCase(),
    hashOf(SwapEscrowNosup.CodeCell),
);
checkEq('code_hash fixture matches build/SwapEscrowNosup.json', built.hash.toLowerCase(), expectHash('code_hash'));

console.log(`\n=== RESULT: ${passed} passed, ${failed} failed ===`);
if (failed > 0) process.exit(1);
