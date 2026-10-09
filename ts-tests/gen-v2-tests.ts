// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * Generates SwapEscrowV2's copy of the SwapEscrowNosup test suite (and of the
 * one-signature testnet smoke): the same tests, run against the contract with
 * the supervisor. Edit the nosup sources, then `npm run gen:v2`; the check in
 * v2-sync.test.ts fails while the copy is stale. Numbers that are
 * measurements of the contract (gas, physical limits, nanoton figures) may
 * differ on V2; each such difference is an entry in v2-test-overrides.json.
 */
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const root = join(__dirname, '..');

interface Override {
    file: string;
    find: string;
    replace: string;
    reason: string;
}

const SUPERVISOR_HELPER = `
// Added for SwapEscrowV2: the supervisor of every test deal.
fun testSupervisor(): Cell<SupervisorState> {
    return SupervisorState {
        supervisor: testing.treasury("v2-sup").address,
        rescueAssets: [],
        rescueCount: 0,
    }.toCell();
}
`;

function banner(source: string): string {
    return `// GENERATED from ${source} by ts-tests/gen-v2-tests.ts — edit the source, then run npm run gen:v2.\n`;
}

// `acton fmt` keeps each run of adjacent `@contracts/` imports sorted; after
// nosup/ became v2/ the run is re-sorted the same way, so a generated file is
// already formatted.
function sortContractImports(text: string): string {
    const lines = text.split('\n');
    const isContractImport = (l: string) => l.startsWith('import "@contracts/');
    for (let i = 0; i < lines.length; ) {
        if (!isContractImport(lines[i])) {
            i++;
            continue;
        }
        let j = i;
        while (j < lines.length && isContractImport(lines[j])) j++;
        const run = lines.slice(i, j).sort();
        lines.splice(i, j - i, ...run);
        i = j;
    }
    return lines.join('\n');
}

function rename(text: string): string {
    return sortContractImports(
        text
            .replace(/@wrappers\/SwapEscrowNosup\.gen/g, '@wrappers/SwapEscrowV2.gen')
            .replace(/\bSwapEscrowNosup\b/g, 'SwapEscrowV2')
            .replace(/@contracts\/nosup\//g, '@contracts/v2/')
            .replace(/import "nosup_helpers"/g, 'import "v2_helpers"')
            .replace(/import "onesig_common"/g, 'import "onesig_common_v2"'),
    );
}

function insertSup(text: string, supExpr: string, file: string, expected: number): string {
    const lines = text.split('\n');
    const out: string[] = [];
    let count = 0;
    for (const line of lines) {
        const m = /^(\s*)dist: DistState \{/.exec(line);
        if (m) {
            out.push(`${m[1]}sup: ${supExpr.replace(/\n/g, `\n${m[1]}`)},`);
            count++;
        }
        out.push(line);
    }
    if (count !== expected) {
        throw new Error(`${file}: expected ${expected} Storage literal(s), found ${count}`);
    }
    return out.join('\n');
}

export function generate(): Map<string, string> {
    const out = new Map<string, string>();
    const src = join(root, 'tests', 'nosup');
    for (const name of readdirSync(src).sort()) {
        if (!name.endsWith('.tolk')) continue;
        let text = rename(readFileSync(join(src, name), 'utf8'));
        let dest = name;
        if (name === 'nosup_helpers.tolk') {
            dest = 'v2_helpers.tolk';
            text = insertSup(text, 'testSupervisor()', name, 1) + SUPERVISOR_HELPER;
        }
        if (name === 'code_hash.test.tolk') continue; // V2 pins its own hash (sup_code_hash)
        out.set(join('tests', 'v2', dest), banner(`tests/nosup/${name}`) + text);
    }
    const common = rename(readFileSync(join(root, 'scripts', 'onesig_common.tolk'), 'utf8'));
    out.set(
        join('scripts', 'onesig_common_v2.tolk'),
        banner('scripts/onesig_common.tolk') +
            insertSup(
                common,
                'SupervisorState {\n    supervisor: funder,\n    rescueAssets: [],\n    rescueCount: 0,\n}.toCell()',
                'onesig_common.tolk',
                1,
            ),
    );
    out.set(
        join('scripts', 'smoke_v2_onesig_testnet.tolk'),
        banner('scripts/smoke_nosup_onesig_testnet.tolk') +
            rename(readFileSync(join(root, 'scripts', 'smoke_nosup_onesig_testnet.tolk'), 'utf8')),
    );
    const overrides = JSON.parse(
        readFileSync(join(__dirname, 'v2-test-overrides.json'), 'utf8'),
    ) as Override[];
    for (const o of overrides) {
        const key = join('tests', 'v2', o.file);
        const text = out.get(key);
        if (text === undefined) throw new Error(`override for unknown file ${o.file}`);
        const at = text.indexOf(o.find);
        if (at < 0 || text.indexOf(o.find, at + 1) >= 0) {
            throw new Error(`override in ${o.file} must match exactly once: ${o.find}`);
        }
        out.set(key, text.replace(o.find, o.replace));
    }
    return out;
}

if (require.main === module) {
    const files = generate();
    for (const [path, text] of files) writeFileSync(join(root, path), text);
    console.log('generated', files.size, 'files');
}
