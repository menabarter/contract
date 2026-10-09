// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * SwapEscrowV2 is SwapEscrowNosup plus the supervisor. This check keeps the
 * two from drifting apart: every pair of files below must be identical once
 * the supervisor blocks (`// sup:begin` … `// sup:end`, only in V2) are
 * removed and the content of each `// variant:begin` … `// variant:end`
 * region (present in both, content may differ) is set aside. Whitespace is
 * not compared: the formatter realigns trailing comments and blank lines
 * around a supervisor block.
 *
 * Run: npm test
 */
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = join(__dirname, '..');
const PAIRS: [string, string][] = [
    ['contracts/escrow_nosup_beta_v1.tolk', 'contracts/escrow_beta_v2.tolk'],
    ['contracts/nosup/storage.tolk', 'contracts/v2/storage.tolk'],
    ['contracts/nosup/accounting.tolk', 'contracts/v2/accounting.tolk'],
    ['contracts/nosup/messages.tolk', 'contracts/v2/messages.tolk'],
];

export function normalize(text: string, stripSup: boolean): string[] {
    const out: string[] = [];
    let inSup = false;
    let inVariant = false;
    for (const line of text.split('\n')) {
        const t = line.trim();
        if (t === '// sup:begin') {
            if (!stripSup) throw new Error('sup block in a file that must not have one');
            inSup = true;
            continue;
        }
        if (t === '// sup:end') {
            inSup = false;
            continue;
        }
        if (inSup) continue;
        if (t === '// variant:begin') {
            inVariant = true;
            out.push('<variant>');
            continue;
        }
        if (t === '// variant:end') {
            inVariant = false;
            continue;
        }
        if (inVariant) continue;
        if (t === '') continue;
        out.push(t.replace(/\s+/g, ' '));
    }
    if (inSup || inVariant) throw new Error('unterminated block');
    return out;
}

console.log('=== SwapEscrowV2 against SwapEscrowNosup outside the supervisor blocks ===\n');
let failed = 0;
for (const [a, b] of PAIRS) {
    const pa = join(root, a);
    const pb = join(root, b);
    if (!existsSync(pb)) {
        console.log(`  ✗ ${b} is missing`);
        failed++;
        continue;
    }
    const na = normalize(readFileSync(pa, 'utf8'), false);
    const nb = normalize(readFileSync(pb, 'utf8'), true);
    const n = Math.max(na.length, nb.length);
    let diff = -1;
    for (let i = 0; i < n; i++) {
        if (na[i] !== nb[i]) {
            diff = i;
            break;
        }
    }
    if (diff < 0) {
        console.log(`  ✓ ${b} matches ${a} outside its supervisor blocks`);
    } else {
        console.log(`  ✗ ${b} differs from ${a} at normalized line ${diff + 1}`);
        console.log(`      ${a}: ${na[diff] ?? '<end>'}`);
        console.log(`      ${b}: ${nb[diff] ?? '<end>'}`);
        failed++;
    }
}
console.log(`\n=== RESULT: ${PAIRS.length - failed} passed, ${failed} failed ===`);
if (failed > 0) process.exit(1);
