// GENERATED from tests/nosup/nft_deposits.test.tolk by ts-tests/gen-v2-tests.ts — edit the source, then run npm run gen:v2.
// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/SwapEscrowV2.gen"
import "v2_helpers"

// deployNft/sendNftToEscrow/readMockOwner live in nosup_helpers.tolk
// (reused by runFullSwap and the parity matrix); only the tests themselves remain here.

get fun `test in-swap NFT is accepted and counted`() {
    val o1 = testing.treasury("nft-o1");
    val o2 = testing.treasury("nft-o2");
    val fw = testing.treasury("nft-fw");
    val nft = deployNft(o1, 1);

    var nfts1: map<uint16, address> = [];
    nfts1.set(0, nft);
    val empty2: map<uint16, address> = [];
    val cfg = EscrowConfig {
        owner1: o1.address,
        owner2: o2.address,
        feeWallet: fw.address,
        nfts1,
        nfts1Count: 1,
        nfts2: empty2,
        nfts2Count: 0,
        gram1Amount: ton("1"),
        gram2Amount: ton("2"),
        jettons: [],
        jettonsCount: 0,
    };
    val escrow = deployEscrow(o1, cfg);

    val res = sendNftToEscrow(o1, nft, escrow.address, ton("0.05"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(escrow.receivedCounts()).toEqual((1, 0));
    expect(readMockOwner(nft)).toEqual(escrow.address);
}

get fun `test foreign NFT is auto-returned to previous owner`() {
    val o1 = testing.treasury("nft2-o1");
    val o2 = testing.treasury("nft2-o2");
    val fw = testing.treasury("nft2-fw");
    // The NFT is NOT part of the escrow's config (won't be found in assets) → foreign.
    val nft = deployNft(o1, 2);
    val escrow = deployEscrow(
        o1,
        makeBasicConfig(o1, o2, fw),
    );

    // forward 0.05 >= RETURN_TRANSFER_VALUE (0.03) — the return must go through.
    val res = sendNftToEscrow(o1, nft, escrow.address, ton("0.05"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nft)).toEqual(o1.address);
    expect(escrow.receivedCounts()).toEqual((0, 0));
}

get fun `test foreign NFT with dust value stays on escrow`() {
    val o1 = testing.treasury("nft3-o1");
    val o2 = testing.treasury("nft3-o2");
    val fw = testing.treasury("nft3-fw");
    val nft = deployNft(o1, 3);
    val escrow = deployEscrow(
        o1,
        makeBasicConfig(o1, o2, fw),
    );

    // forward 0.005 < RETURN_TRANSFER_VALUE (0.03) — insufficient gas for
    // the return: the NFT stays on the escrow (recovering a stuck asset is
    // out of scope for this suite), but the incoming transaction itself
    // must NOT fail (no throw in the acceptance rule).
    val res = sendNftToEscrow(o1, nft, escrow.address, ton("0.005"));
    expect(res).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nft)).toEqual(escrow.address);
    expect(escrow.receivedCounts()).toEqual((0, 0));
}

// The duplicate case (the same NFT sent back to the escrow while still
// marked received) is not covered here: producing it needs an asset to
// leave the registry and come back without going through cancel, and
// OwnershipAssigned cannot be forged "on behalf of someone else" — the
// sender must be the real NFT mock's address.

// ── O(1) NFT-acceptance hint + VERIFICATION (security) ──

// A correct hint → acceptance via the O(1) path, the asset at the right index.
get fun `test NFT accepted via correct asset_index hint`() {
    val o1 = testing.treasury("nfth1-o1");
    val o2 = testing.treasury("nfth1-o2");
    val fw = testing.treasury("nfth1-fw");
    val nftA = deployNft(o1, 7001);
    val nftB = deployNft(o1, 7002);
    var nfts1: map<uint16, address> = [];
    nfts1.set(0, nftA);
    nfts1.set(1, nftB);
    var cfg = makeBasicConfig(o1, o2, fw);
    cfg.nfts1 = nfts1;
    cfg.nfts1Count = 2;
    val escrow = deployEscrow(o1, cfg);

    // nftB is at global index 1; hint 1 matches by address → O(1) acceptance.
    expect(sendNftToEscrow(o1, nftB, escrow.address, ton("0.05"), 1)).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nftB)).toEqual(escrow.address);
    expect(escrow.receivedCounts()).toEqual((1, 0));
}

// SECURITY: the hint points at a DIFFERENT index (nftA's index), but nftB is
// sent. The check assets[hint].addr == sender() does NOT match (that slot
// holds nftA) → falls back to the linear scan → finds nftB by address at
// index 1 → marks received for nftB SPECIFICALLY, not nftA (the hint's
// index is ignored). Index spoofing does not lead to misattribution: the
// source of truth is the sender's address.
get fun `test malicious wrong-index hint does not misattribute — verify catches it`() {
    val o1 = testing.treasury("nfth2-o1");
    val o2 = testing.treasury("nfth2-o2");
    val fw = testing.treasury("nfth2-fw");
    val nftA = deployNft(o1, 7101); // index 0
    val nftB = deployNft(o1, 7102); // index 1
    var nfts1: map<uint16, address> = [];
    nfts1.set(0, nftA);
    nfts1.set(1, nftB);
    var cfg = makeBasicConfig(o1, o2, fw);
    cfg.nfts1 = nfts1;
    cfg.nfts1Count = 2;
    val escrow = deployEscrow(o1, cfg);

    // Send nftB, but the hint lies: it points at index 0 (nftA).
    expect(sendNftToEscrow(o1, nftB, escrow.address, ton("0.05"), 0)).toHaveAllSuccessfulTxs();
    // nftB is accepted (by its actual address), nftA is NOT.
    expect(readMockOwner(nftB)).toEqual(escrow.address);
    expect(readMockOwner(nftA)).toEqual(o1.address);
    expect(escrow.receivedCounts()).toEqual((1, 0));
    // Sending nftA again with an honest hint of 0 — accepted normally
    // (index 0 is still free, the misattribution did not corrupt the bookkeeping).
    expect(sendNftToEscrow(o1, nftA, escrow.address, ton("0.05"), 0)).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nftA)).toEqual(escrow.address);
    expect(escrow.receivedCounts()).toEqual((2, 0));
}

// A hint out of range (>= assetsCount) → fallback → acceptance by address.
get fun `test out-of-range hint falls back to linear scan`() {
    val o1 = testing.treasury("nfth3-o1");
    val o2 = testing.treasury("nfth3-o2");
    val fw = testing.treasury("nfth3-fw");
    val nft = deployNft(o1, 7201);
    var nfts1: map<uint16, address> = [];
    nfts1.set(0, nft);
    var cfg = makeBasicConfig(o1, o2, fw);
    cfg.nfts1 = nfts1;
    cfg.nfts1Count = 1;
    val escrow = deployEscrow(o1, cfg);

    expect(sendNftToEscrow(o1, nft, escrow.address, ton("0.05"), 999)).toHaveAllSuccessfulTxs();
    expect(readMockOwner(nft)).toEqual(escrow.address);
    expect(escrow.receivedCounts()).toEqual((1, 0));
}

// SECURITY: a foreign NFT WITH a hint (pointing at a valid deal index) →
// the address check does not match (the in-deal asset has a different addr)
// → fallback finds nothing → auto-return. The hint does not let a foreign
// NFT slip through.
get fun `test foreign NFT with hint still auto-returned`() {
    val o1 = testing.treasury("nfth4-o1");
    val o2 = testing.treasury("nfth4-o2");
    val fw = testing.treasury("nfth4-fw");
    val inDeal = deployNft(o1, 7301);
    val foreign = deployNft(o1, 7302);
    var nfts1: map<uint16, address> = [];
    nfts1.set(0, inDeal);
    var cfg = makeBasicConfig(o1, o2, fw);
    cfg.nfts1 = nfts1;
    cfg.nfts1Count = 1;
    val escrow = deployEscrow(o1, cfg);

    // foreign with hint 0 (inDeal's index): the addr check doesn't match → auto-return.
    expect(sendNftToEscrow(o1, foreign, escrow.address, ton("0.05"), 0)).toHaveAllSuccessfulTxs();
    expect(readMockOwner(foreign)).toEqual(o1.address); // returned to its owner
    expect(escrow.receivedCounts()).toEqual((0, 0));    // nothing accepted
}
