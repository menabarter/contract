// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// An NFT whose transfer needs more gas than the escrow attaches: the push
// delivery fails (possibly without any bounce), and the recipient pulls it
// with a larger claim value — without a bounce mark.
//
// GAS EVIDENCE: this test's numbers are calibrated against the emulator's
// actual basechain gas price, not a guessed one. tests/nosup/gas_probe.test.tolk
// pins that price down: calculateGasFee(0, 45000) lands in [0.003, 0.0036]
// TON, i.e. roughly 66.7-80 nanoton per gas unit (matching the
// 4369067/2^16 ≈ 66.68 nanoton/gas documented in contracts/nosup/storage.tolk).
// At ≈66.7 nanoton/gas, NFT_TRANSFER_VALUE (0.03 TON, minus a small forward
// fee) buys roughly 430k-440k gas of compute for the push transaction, well
// under the hard per-transaction compute ceiling of 1,000,000 gas
// (GasPricesExtended.gasLimit, .acton/emulation/config.tolk). A claim value of
// 0.5 TON already exceeds the TON needed to hit that hard ceiling
// (1,000,000 gas x ~66.7 nanoton ≈ 0.0667 TON), so the claim transaction's
// compute budget is capped at the ceiling itself, independent of the exact
// value above that point.
// burnGas = 600000 sits between these two budgets: below the ~1,000,000-gas
// ceiling a well-funded claim can reach, but above the ~440k-gas budget the
// fixed NFT_TRANSFER_VALUE push can reach — so the push fails out of gas and
// the larger claim succeeds.
import "@acton/build"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/types/big_array"
import "@acton/types/transaction"
import "@contracts/messages"
import "@contracts/nft_item_gas_mock"
import "@wrappers/SwapEscrowNosup.gen"
import "@contracts/nosup/messages"
import "@contracts/nosup/storage"
import "nosup_helpers"

fun deployGasNft(owner: Treasury, seed: int, burnGas: int): address {
    val st = MockGasNftStorage {
        ownerAddr: owner.address,
        seed: seed as uint32,
        burnGas: burnGas as uint32,
    };
    val init = ContractState {
        code: build("NftItemGasMock"),
        data: st.toCell(),
    };
    val addr = AutoDeployAddress { stateInit: init }.calculateAddress();
    expect(
        net.send(
            owner.address,
            createMessage({ bounce: BounceMode.NoBounce, value: ton("0.1"), dest: {
                    stateInit: init,
                } }),
        ),
    ).toHaveSuccessfulDeploy({ to: addr });
    return addr;
}

// True if `res` contains a failed (aborted) transaction at `addr`.
fun SendResultList.hasFailedTxAt(self, addr: address): bool {
    var i = 0;
    while (i < self.size()) {
        val r = self.at(i);
        val tx = r.tx.load();
        if (tx.getAccountAddress() == addr) {
            val descr = tx.description.load();
            if (descr is TlbTransOrd) {
                if (descr.aborted) {
                    return true;
                }
            }
        }
        i += 1;
    }
    return false;
}

get fun `test heavy NFT fails push delivery and is claimed with more gas`() {
    val o1 = testing.treasury("gm-o1");
    val o2 = testing.treasury("gm-o2");
    val fw = testing.treasury("gm-fw");
    // See the file header for the gas-price evidence behind these numbers.
    val heavy = deployGasNft(o1, 81001, 600000);
    val nft2 = deployNft(o2, 81002);
    var cfg = makeBasicConfig(o1, o2, fw);
    var n1: map<uint16, address> = [];
    n1.set(0, heavy);
    var n2: map<uint16, address> = [];
    n2.set(0, nft2);
    cfg.nfts1 = n1;
    cfg.nfts1Count = 1;
    cfg.nfts2 = n2;
    cfg.nfts2Count = 1;
    val escrow = deployEscrow(o1, cfg);
    expect(escrow.sendText(o1.address, "service_fee_owner1", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    expect(escrow.sendText(o2.address, "service_fee_owner2", SERVICE_FEE)).toHaveAllSuccessfulTxs();
    // The deposit's own transfer to the heavy mock must carry enough value to
    // clear burnGas on its own; 0.2 forward + the 0.05 reserve added by
    // sendNftToEscrow is comfortably above the ~440k-gas budget of 0.03 TON.
    val dep = sendNftToEscrow(o1, heavy, escrow.address, ton("0.2"), 0);
    expect(dep).toHaveAllSuccessfulTxs();
    expect(net.runGetMethod<address>(heavy, "ownerAddr")).toEqual(escrow.address);
    val trigger = sendNftToEscrow(o2, nft2, escrow.address, ton("0.2"), 1);
    expect(escrow.phase()).toEqual(PHASE_DONE);
    // The push to the heavy NFT really failed out of gas: the NFT is still
    // escrow-owned, and the trigger's trace contains a failed transaction at
    // the heavy NFT's address (not just a skipped one).
    expect(net.runGetMethod<address>(heavy, "ownerAddr")).toEqual(escrow.address);
    expect(trigger.hasFailedTxAt(heavy)).toEqual(true);
    // Whether a bounce mark landed depends only on how much of the fixed
    // NFT_TRANSFER_VALUE survived the out-of-gas abort at the NFT — either
    // outcome is a correct implementation (see the report for what was
    // actually observed).
    println("assetStatus(0) after the failed push: {}", escrow.assetStatus(0));

    // Too little gas again: the claim fails at the NFT, nothing moves.
    val smallClaim = sendClaim(o2.address, escrow.address, 0, ton("0.03"));
    expect(net.runGetMethod<address>(heavy, "ownerAddr")).toEqual(escrow.address);
    expect(smallClaim.hasFailedTxAt(heavy)).toEqual(true);

    // Enough gas: delivered, whether or not a bounce mark exists.
    expect(sendClaim(o2.address, escrow.address, 0, ton("0.5"))).toHaveAllSuccessfulTxs();
    expect(net.runGetMethod<address>(heavy, "ownerAddr")).toEqual(o2.address);
}
