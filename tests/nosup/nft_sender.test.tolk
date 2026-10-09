// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// Which registry slot an incoming NFT fills, and when the sender must be the
// slot's side owner.
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@contracts/messages"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/storage"
import "@contracts/shared/types"
import "nosup_helpers"

struct StrangerDeal {
    escrow: EscrowFixture
    o1: Treasury
    stranger: Treasury
    nft: address // registry slot 0 (side 1), owned by `stranger`
}

// 1x1 deal whose side-1 registry item belongs to a third party.
fun strangerDeal(tag: string, seed: int): StrangerDeal {
    val o1 = testing.treasury(tagged(tag, "-o1"));
    val o2 = testing.treasury(tagged(tag, "-o2"));
    val fw = testing.treasury(tagged(tag, "-fw"));
    val stranger = testing.treasury(tagged(tag, "-st"));
    val nft = deployNft(stranger, seed);
    val other = deployNft(o2, seed + 1);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, nft);
    var b: map<uint16, address> = [];
    b.set(0, other);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = 1;
    return StrangerDeal {
        escrow: deployEscrow(o1, cfg),
        o1,
        stranger,
        nft,
    };
}

get fun `test stranger deposit able to pay its return is sent back`() {
    val d = strangerDeal("ns-ret", 74001);
    sendNftToEscrow(d.stranger, d.nft, d.escrow.address, ton("0.05"), 0);
    expect(d.escrow.receivedCounts()).toEqual((0, 0));
    expect(readMockOwner(d.nft)).toEqual(d.stranger.address);
}

get fun `test stranger deposit below the return cost is credited as before`() {
    val d = strangerDeal("ns-low", 74011);
    sendNftToEscrow(d.stranger, d.nft, d.escrow.address, ton("0.01"), 0);
    expect(d.escrow.receivedCounts()).toEqual((1, 0));
    expect(readMockOwner(d.nft)).toEqual(d.escrow.address);
}

get fun `test owner deposit is credited`() {
    val f = setup1x1("ns-own", 74021);
    expect(f.escrow.receivedCounts()).toEqual((1, 1));
}

// One item listed on both sides: a hint at the other side's slot must not
// credit the other side — the match falls through to the sender's own slot.
get fun `test wrong hint falls through to the sender's own slot`() {
    val o1 = testing.treasury("ns-hint-o1");
    val o2 = testing.treasury("ns-hint-o2");
    val fw = testing.treasury("ns-hint-fw");
    val x = deployNft(o1, 74031);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, x);
    var b: map<uint16, address> = [];
    b.set(0, x);
    cfg.nfts1 = a;
    cfg.nfts1Count = 1;
    cfg.nfts2 = b;
    cfg.nfts2Count = 1;
    val escrow = deployEscrow(o1, cfg);
    sendNftToEscrow(o1, x, escrow.address, ton("0.05"), 1);
    expect(escrow.receivedCounts()).toEqual((1, 0));
}

// Two side-1 slots for one item, the first already received: a deposit
// without a hint must find the free second slot.
get fun `test linear match skips a received slot`() {
    val o1 = testing.treasury("ns-lin-o1");
    val o2 = testing.treasury("ns-lin-o2");
    val fw = testing.treasury("ns-lin-fw");
    val x = deployNft(o1, 74041);
    var cfg = makeBasicConfig(o1, o2, fw);
    var a: map<uint16, address> = [];
    a.set(0, x);
    a.set(1, x);
    cfg.nfts1 = a;
    cfg.nfts1Count = 2;
    var st = buildInitialStorage(cfg);
    var s0 = st.assets.mustGet(0);
    s0.received = true;
    st.assets.set(0, s0);
    st.received1Count = 1;
    val escrow = SwapEscrowNosup.fromStorage(st);
    expect(
        net.send(
            o1.address,
            createMessage({
                bounce: BounceMode.NoBounce,
                value: ton("1"),
                dest: { stateInit: escrow.stateInit! },
                body: Excesses { queryId: 0 },
            }),
        ),
    ).toHaveSuccessfulDeploy({ to: escrow.address });
    sendNftToEscrow(o1, x, escrow.address, ton("0.05"), -1);
    expect(escrow.receivedCounts()).toEqual((2, 0));
}
