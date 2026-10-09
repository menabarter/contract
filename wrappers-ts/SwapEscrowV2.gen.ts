// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// AUTO-GENERATED, do not edit
// It's a TypeScript wrapper for a SwapEscrowV2 contract in Tolk.
/* eslint-disable */

import * as c from '@ton/core';
import { beginCell, ContractProvider, Sender, SendMode } from '@ton/core';

// ————————————————————————————————————————————
//   predefined types and functions
//

type RemainingBitsAndRefs = c.Slice

type StoreCallback<T> = (obj: T, b: c.Builder) => void
type LoadCallback<T> = (s: c.Slice) => T

export type CellRef<T> = {
    ref: T
}

function makeCellFrom<T>(self: T, storeFn_T: StoreCallback<T>): c.Cell {
    let b = beginCell();
    storeFn_T(self, b);
    return b.endCell();
}

function loadAndCheckPrefix32(s: c.Slice, expected: number, structName: string): void {
    let prefix = s.loadUint(32);
    if (prefix !== expected) {
        throw new Error(`Incorrect prefix for '${structName}': expected 0x${expected.toString(16).padStart(8, '0')}, got 0x${prefix.toString(16).padStart(8, '0')}`);
    }
}

function lookupPrefix(s: c.Slice, expected: number, prefixLen: number): boolean {
    return s.remainingBits >= prefixLen && s.preloadUint(prefixLen) === expected;
}

function throwNonePrefixMatch(fieldPath: string): never {
    throw new Error(`Incorrect prefix for '${fieldPath}': none of variants matched`);
}

function storeCellRef<T>(cell: CellRef<T>, b: c.Builder, storeFn_T: StoreCallback<T>): void {
    let b_ref = c.beginCell();
    storeFn_T(cell.ref, b_ref);
    b.storeRef(b_ref.endCell());
}

function loadCellRef<T>(s: c.Slice, loadFn_T: LoadCallback<T>): CellRef<T> {
    let s_ref = s.loadRef().beginParse();
    return { ref: loadFn_T(s_ref) };
}

function storeTolkRemaining(v: RemainingBitsAndRefs, b: c.Builder): void {
    b.storeSlice(v);
}

function loadTolkRemaining(s: c.Slice): RemainingBitsAndRefs {
    let rest = s.clone();
    s.loadBits(s.remainingBits);
    while (s.remainingRefs) {
        s.loadRef();
    }
    return rest;
}

function storeTolkNullable<T>(v: T | null, b: c.Builder, storeFn_T: StoreCallback<T>): void {
    if (v === null) {
        b.storeUint(0, 1);
    } else {
        b.storeUint(1, 1);
        storeFn_T(v, b);
    }
}

function createDictionaryValue<V>(loadFn_V: LoadCallback<V>, storeFn_V: StoreCallback<V>): c.DictionaryValue<V> {
    return {
        serialize(self: V, b: c.Builder) {
            storeFn_V(self, b);
        },
        parse(s: c.Slice): V {
            const value = loadFn_V(s);
            s.endParse();
            return value;
        }
    }
}

// ————————————————————————————————————————————
//   parse get methods result from a TVM stack
//

class StackReader {
    constructor(private tuple: c.TupleItem[]) {
    }

    static fromGetMethod(expectedN: number, getMethodResult: { stack: c.TupleReader }): StackReader {
        let tuple = [] as c.TupleItem[];
        while (getMethodResult.stack.remaining) {
            tuple.push(getMethodResult.stack.pop());
        }
        if (tuple.length !== expectedN) {
            throw new Error(`expected ${expectedN} stack width, got ${tuple.length}`);
        }
        return new StackReader(tuple);
    }

    private popExpecting<ItemT>(itemType: string): ItemT {
        const item = this.tuple.shift();
        if (item?.type === itemType) {
            return item as ItemT;
        }
        throw new Error(`not '${itemType}' on a stack`);
    }

    private popCellLike(): c.Cell {
        const item = this.tuple.shift();
        if (item && (item.type === 'cell' || item.type === 'slice' || item.type === 'builder')) {
            return item.cell;
        }
        throw new Error(`not cell/slice on a stack`);
    }

    readBigInt(): bigint {
        return this.popExpecting<c.TupleItemInt>('int').value;
    }

    readBoolean(): boolean {
        return this.popExpecting<c.TupleItemInt>('int').value !== 0n;
    }

    readCell(): c.Cell {
        return this.popCellLike();
    }

    readSlice(): c.Slice {
        return this.popCellLike().beginParse();
    }

    readNullable<T>(readFn_T: (r: StackReader) => T): T | null {
        if (this.tuple[0].type === 'null') {
            this.tuple.shift();
            return null;
        }
        return readFn_T(this);
    }

    readDictionary<K extends c.DictionaryKeyTypes, V>(keySerializer: c.DictionaryKey<K>, valueSerializer: c.DictionaryValue<V>): c.Dictionary<K, V> {
        if (this.tuple[0].type === 'null') {
            this.tuple.shift();
            return c.Dictionary.empty<K, V>(keySerializer, valueSerializer);
        }
        return c.Dictionary.loadDirect<K, V>(keySerializer, valueSerializer, this.readCell());
    }
}

// ————————————————————————————————————————————
//   auto-generated serializers to/from cells
//

type coins = bigint

type uint2 = bigint
type uint3 = bigint
type uint4 = bigint
type uint16 = bigint
type uint64 = bigint

/**
 > struct (0x05138d91) OwnershipAssigned {
 >     queryId: uint64
 >     previousOwner: address
 >     forwardPayload: RemainingBitsAndRefs
 > }
 */
export interface OwnershipAssigned {
    readonly $: 'OwnershipAssigned'
    queryId: uint64
    previousOwner: c.Address
    forwardPayload: RemainingBitsAndRefs
}

export const OwnershipAssigned = {
    PREFIX: 0x05138d91,

    create(args: {
        queryId: uint64
        previousOwner: c.Address
        forwardPayload: RemainingBitsAndRefs
    }): OwnershipAssigned {
        return {
            $: 'OwnershipAssigned',
            ...args
        }
    },
    fromSlice(s: c.Slice): OwnershipAssigned {
        loadAndCheckPrefix32(s, 0x05138d91, 'OwnershipAssigned');
        return {
            $: 'OwnershipAssigned',
            queryId: s.loadUintBig(64),
            previousOwner: s.loadAddress(),
            forwardPayload: loadTolkRemaining(s),
        }
    },
    store(self: OwnershipAssigned, b: c.Builder): void {
        b.storeUint(0x05138d91, 32);
        b.storeUint(self.queryId, 64);
        b.storeAddress(self.previousOwner);
        storeTolkRemaining(self.forwardPayload, b);
    },
    toCell(self: OwnershipAssigned): c.Cell {
        return makeCellFrom<OwnershipAssigned>(self, OwnershipAssigned.store);
    }
}

/**
 > struct (0x6d5f0001) SupervisorAssetReceived {
 >     assetAddr: address
 > }
 */
export interface SupervisorAssetReceived {
    readonly $: 'SupervisorAssetReceived'
    assetAddr: c.Address
}

export const SupervisorAssetReceived = {
    PREFIX: 0x6d5f0001,

    create(args: {
        assetAddr: c.Address
    }): SupervisorAssetReceived {
        return {
            $: 'SupervisorAssetReceived',
            ...args
        }
    },
    fromSlice(s: c.Slice): SupervisorAssetReceived {
        loadAndCheckPrefix32(s, 0x6d5f0001, 'SupervisorAssetReceived');
        return {
            $: 'SupervisorAssetReceived',
            assetAddr: s.loadAddress(),
        }
    },
    store(self: SupervisorAssetReceived, b: c.Builder): void {
        b.storeUint(0x6d5f0001, 32);
        b.storeAddress(self.assetAddr);
    },
    toCell(self: SupervisorAssetReceived): c.Cell {
        return makeCellFrom<SupervisorAssetReceived>(self, SupervisorAssetReceived.store);
    }
}

/**
 > struct (0x6d5f0002) RescueNft {
 >     nftAddr: address
 > }
 */
export interface RescueNft {
    readonly $: 'RescueNft'
    nftAddr: c.Address
}

export const RescueNft = {
    PREFIX: 0x6d5f0002,

    create(args: {
        nftAddr: c.Address
    }): RescueNft {
        return {
            $: 'RescueNft',
            ...args
        }
    },
    fromSlice(s: c.Slice): RescueNft {
        loadAndCheckPrefix32(s, 0x6d5f0002, 'RescueNft');
        return {
            $: 'RescueNft',
            nftAddr: s.loadAddress(),
        }
    },
    store(self: RescueNft, b: c.Builder): void {
        b.storeUint(0x6d5f0002, 32);
        b.storeAddress(self.nftAddr);
    },
    toCell(self: RescueNft): c.Cell {
        return makeCellFrom<RescueNft>(self, RescueNft.store);
    }
}

/**
 > struct (0x6d5f0003) RescueJetton {
 >     queryId: uint64
 >     jettonWallet: address
 >     amount: coins
 > }
 */
export interface RescueJetton {
    readonly $: 'RescueJetton'
    queryId: uint64
    jettonWallet: c.Address
    amount: coins
}

export const RescueJetton = {
    PREFIX: 0x6d5f0003,

    create(args: {
        queryId: uint64
        jettonWallet: c.Address
        amount: coins
    }): RescueJetton {
        return {
            $: 'RescueJetton',
            ...args
        }
    },
    fromSlice(s: c.Slice): RescueJetton {
        loadAndCheckPrefix32(s, 0x6d5f0003, 'RescueJetton');
        return {
            $: 'RescueJetton',
            queryId: s.loadUintBig(64),
            jettonWallet: s.loadAddress(),
            amount: s.loadCoins(),
        }
    },
    store(self: RescueJetton, b: c.Builder): void {
        b.storeUint(0x6d5f0003, 32);
        b.storeUint(self.queryId, 64);
        b.storeAddress(self.jettonWallet);
        b.storeCoins(self.amount);
    },
    toCell(self: RescueJetton): c.Cell {
        return makeCellFrom<RescueJetton>(self, RescueJetton.store);
    }
}

/**
 > struct (0x6d5f0004) ContinueDistribution {
 >     queryId: uint64
 > }
 */
export interface ContinueDistribution {
    readonly $: 'ContinueDistribution'
    queryId: uint64
}

export const ContinueDistribution = {
    PREFIX: 0x6d5f0004,

    create(args: {
        queryId: uint64
    }): ContinueDistribution {
        return {
            $: 'ContinueDistribution',
            ...args
        }
    },
    fromSlice(s: c.Slice): ContinueDistribution {
        loadAndCheckPrefix32(s, 0x6d5f0004, 'ContinueDistribution');
        return {
            $: 'ContinueDistribution',
            queryId: s.loadUintBig(64),
        }
    },
    store(self: ContinueDistribution, b: c.Builder): void {
        b.storeUint(0x6d5f0004, 32);
        b.storeUint(self.queryId, 64);
    },
    toCell(self: ContinueDistribution): c.Cell {
        return makeCellFrom<ContinueDistribution>(self, ContinueDistribution.store);
    }
}

/**
 > struct (0x6d5f0005) ForceDeliver {
 >     queryId: uint64
 >     assetIndex: uint16
 >     fallback: bool
 > }
 */
export interface ForceDeliver {
    readonly $: 'ForceDeliver'
    queryId: uint64
    assetIndex: uint16
    fallback: boolean
}

export const ForceDeliver = {
    PREFIX: 0x6d5f0005,

    create(args: {
        queryId: uint64
        assetIndex: uint16
        fallback: boolean
    }): ForceDeliver {
        return {
            $: 'ForceDeliver',
            ...args
        }
    },
    fromSlice(s: c.Slice): ForceDeliver {
        loadAndCheckPrefix32(s, 0x6d5f0005, 'ForceDeliver');
        return {
            $: 'ForceDeliver',
            queryId: s.loadUintBig(64),
            assetIndex: s.loadUintBig(16),
            fallback: s.loadBoolean(),
        }
    },
    store(self: ForceDeliver, b: c.Builder): void {
        b.storeUint(0x6d5f0005, 32);
        b.storeUint(self.queryId, 64);
        b.storeUint(self.assetIndex, 16);
        b.storeBit(self.fallback);
    },
    toCell(self: ForceDeliver): c.Cell {
        return makeCellFrom<ForceDeliver>(self, ForceDeliver.store);
    }
}

/**
 > struct (0x5fcc3d14) NftTransfer {
 >     queryId: uint64
 >     newOwner: address
 >     responseDestination: address
 >     customPayload: cell?
 >     forwardAmount: coins
 >     forwardPayload: RemainingBitsAndRefs
 > }
 */
export interface NftTransfer {
    readonly $: 'NftTransfer'
    queryId: uint64
    newOwner: c.Address
    responseDestination: c.Address
    customPayload: c.Cell | null
    forwardAmount: coins
    forwardPayload: RemainingBitsAndRefs
}

export const NftTransfer = {
    PREFIX: 0x5fcc3d14,

    create(args: {
        queryId: uint64
        newOwner: c.Address
        responseDestination: c.Address
        customPayload: c.Cell | null
        forwardAmount: coins
        forwardPayload: RemainingBitsAndRefs
    }): NftTransfer {
        return {
            $: 'NftTransfer',
            ...args
        }
    },
    fromSlice(s: c.Slice): NftTransfer {
        loadAndCheckPrefix32(s, 0x5fcc3d14, 'NftTransfer');
        return {
            $: 'NftTransfer',
            queryId: s.loadUintBig(64),
            newOwner: s.loadAddress(),
            responseDestination: s.loadAddress(),
            customPayload: s.loadBoolean() ? s.loadRef() : null,
            forwardAmount: s.loadCoins(),
            forwardPayload: loadTolkRemaining(s),
        }
    },
    store(self: NftTransfer, b: c.Builder): void {
        b.storeUint(0x5fcc3d14, 32);
        b.storeUint(self.queryId, 64);
        b.storeAddress(self.newOwner);
        b.storeAddress(self.responseDestination);
        storeTolkNullable<c.Cell>(self.customPayload, b,
            (v,b) => b.storeRef(v)
        );
        b.storeCoins(self.forwardAmount);
        storeTolkRemaining(self.forwardPayload, b);
    },
    toCell(self: NftTransfer): c.Cell {
        return makeCellFrom<NftTransfer>(self, NftTransfer.store);
    }
}

/**
 > struct (0x2c76b973) ProvideWalletAddress {
 >     queryId: uint64
 >     ownerAddress: address
 >     includeAddress: bool
 > }
 */
export interface ProvideWalletAddress {
    readonly $: 'ProvideWalletAddress'
    queryId: uint64
    ownerAddress: c.Address
    includeAddress: boolean
}

export const ProvideWalletAddress = {
    PREFIX: 0x2c76b973,

    create(args: {
        queryId: uint64
        ownerAddress: c.Address
        includeAddress: boolean
    }): ProvideWalletAddress {
        return {
            $: 'ProvideWalletAddress',
            ...args
        }
    },
    fromSlice(s: c.Slice): ProvideWalletAddress {
        loadAndCheckPrefix32(s, 0x2c76b973, 'ProvideWalletAddress');
        return {
            $: 'ProvideWalletAddress',
            queryId: s.loadUintBig(64),
            ownerAddress: s.loadAddress(),
            includeAddress: s.loadBoolean(),
        }
    },
    store(self: ProvideWalletAddress, b: c.Builder): void {
        b.storeUint(0x2c76b973, 32);
        b.storeUint(self.queryId, 64);
        b.storeAddress(self.ownerAddress);
        b.storeBit(self.includeAddress);
    },
    toCell(self: ProvideWalletAddress): c.Cell {
        return makeCellFrom<ProvideWalletAddress>(self, ProvideWalletAddress.store);
    }
}

/**
 > struct (0x0f8a7ea5) JettonTransfer {
 >     queryId: uint64
 >     amount: coins
 >     destination: address
 >     responseDestination: address
 >     customPayload: cell?
 >     forwardTonAmount: coins
 >     forwardPayload: RemainingBitsAndRefs
 > }
 */
export interface JettonTransfer {
    readonly $: 'JettonTransfer'
    queryId: uint64
    amount: coins
    destination: c.Address
    responseDestination: c.Address
    customPayload: c.Cell | null
    forwardTonAmount: coins
    forwardPayload: RemainingBitsAndRefs
}

export const JettonTransfer = {
    PREFIX: 0x0f8a7ea5,

    create(args: {
        queryId: uint64
        amount: coins
        destination: c.Address
        responseDestination: c.Address
        customPayload: c.Cell | null
        forwardTonAmount: coins
        forwardPayload: RemainingBitsAndRefs
    }): JettonTransfer {
        return {
            $: 'JettonTransfer',
            ...args
        }
    },
    fromSlice(s: c.Slice): JettonTransfer {
        loadAndCheckPrefix32(s, 0x0f8a7ea5, 'JettonTransfer');
        return {
            $: 'JettonTransfer',
            queryId: s.loadUintBig(64),
            amount: s.loadCoins(),
            destination: s.loadAddress(),
            responseDestination: s.loadAddress(),
            customPayload: s.loadBoolean() ? s.loadRef() : null,
            forwardTonAmount: s.loadCoins(),
            forwardPayload: loadTolkRemaining(s),
        }
    },
    store(self: JettonTransfer, b: c.Builder): void {
        b.storeUint(0x0f8a7ea5, 32);
        b.storeUint(self.queryId, 64);
        b.storeCoins(self.amount);
        b.storeAddress(self.destination);
        b.storeAddress(self.responseDestination);
        storeTolkNullable<c.Cell>(self.customPayload, b,
            (v,b) => b.storeRef(v)
        );
        b.storeCoins(self.forwardTonAmount);
        storeTolkRemaining(self.forwardPayload, b);
    },
    toCell(self: JettonTransfer): c.Cell {
        return makeCellFrom<JettonTransfer>(self, JettonTransfer.store);
    }
}

/**
 > struct (0x7362d09c) JettonTransferNotification {
 >     queryId: uint64
 >     amount: coins
 >     sender: address
 >     forwardPayload: RemainingBitsAndRefs
 > }
 */
export interface JettonTransferNotification {
    readonly $: 'JettonTransferNotification'
    queryId: uint64
    amount: coins
    sender: c.Address
    forwardPayload: RemainingBitsAndRefs
}

export const JettonTransferNotification = {
    PREFIX: 0x7362d09c,

    create(args: {
        queryId: uint64
        amount: coins
        sender: c.Address
        forwardPayload: RemainingBitsAndRefs
    }): JettonTransferNotification {
        return {
            $: 'JettonTransferNotification',
            ...args
        }
    },
    fromSlice(s: c.Slice): JettonTransferNotification {
        loadAndCheckPrefix32(s, 0x7362d09c, 'JettonTransferNotification');
        return {
            $: 'JettonTransferNotification',
            queryId: s.loadUintBig(64),
            amount: s.loadCoins(),
            sender: s.loadAddress(),
            forwardPayload: loadTolkRemaining(s),
        }
    },
    store(self: JettonTransferNotification, b: c.Builder): void {
        b.storeUint(0x7362d09c, 32);
        b.storeUint(self.queryId, 64);
        b.storeCoins(self.amount);
        b.storeAddress(self.sender);
        storeTolkRemaining(self.forwardPayload, b);
    },
    toCell(self: JettonTransferNotification): c.Cell {
        return makeCellFrom<JettonTransferNotification>(self, JettonTransferNotification.store);
    }
}

/**
 > struct (0xd53276db) Excesses {
 >     queryId: uint64
 > }
 */
export interface Excesses {
    readonly $: 'Excesses'
    queryId: uint64
}

export const Excesses = {
    PREFIX: 0xd53276db,

    create(args: {
        queryId: uint64
    }): Excesses {
        return {
            $: 'Excesses',
            ...args
        }
    },
    fromSlice(s: c.Slice): Excesses {
        loadAndCheckPrefix32(s, 0xd53276db, 'Excesses');
        return {
            $: 'Excesses',
            queryId: s.loadUintBig(64),
        }
    },
    store(self: Excesses, b: c.Builder): void {
        b.storeUint(0xd53276db, 32);
        b.storeUint(self.queryId, 64);
    },
    toCell(self: Excesses): c.Cell {
        return makeCellFrom<Excesses>(self, Excesses.store);
    }
}

/**
 > struct (0x6d5f0006) ClaimAsset {
 >     queryId: uint64
 >     assetIndex: uint16
 > }
 */
export interface ClaimAsset {
    readonly $: 'ClaimAsset'
    queryId: uint64
    assetIndex: uint16
}

export const ClaimAsset = {
    PREFIX: 0x6d5f0006,

    create(args: {
        queryId: uint64
        assetIndex: uint16
    }): ClaimAsset {
        return {
            $: 'ClaimAsset',
            ...args
        }
    },
    fromSlice(s: c.Slice): ClaimAsset {
        loadAndCheckPrefix32(s, 0x6d5f0006, 'ClaimAsset');
        return {
            $: 'ClaimAsset',
            queryId: s.loadUintBig(64),
            assetIndex: s.loadUintBig(16),
        }
    },
    store(self: ClaimAsset, b: c.Builder): void {
        b.storeUint(0x6d5f0006, 32);
        b.storeUint(self.queryId, 64);
        b.storeUint(self.assetIndex, 16);
    },
    toCell(self: ClaimAsset): c.Cell {
        return makeCellFrom<ClaimAsset>(self, ClaimAsset.store);
    }
}

/**
 > struct (0x6d5f0007) AcceptDeal {
 >     queryId: uint64
 >     claims: map<address, address>
 > }
 */
export interface AcceptDeal {
    readonly $: 'AcceptDeal'
    queryId: uint64
    claims: c.Dictionary<c.Address, c.Address>
}

export const AcceptDeal = {
    PREFIX: 0x6d5f0007,

    create(args: {
        queryId: uint64
        claims: c.Dictionary<c.Address, c.Address>
    }): AcceptDeal {
        return {
            $: 'AcceptDeal',
            ...args
        }
    },
    fromSlice(s: c.Slice): AcceptDeal {
        loadAndCheckPrefix32(s, 0x6d5f0007, 'AcceptDeal');
        return {
            $: 'AcceptDeal',
            queryId: s.loadUintBig(64),
            claims: c.Dictionary.load<c.Address, c.Address>(c.Dictionary.Keys.Address(), createDictionaryValue<c.Address>(
                (s) => s.loadAddress(),
                (v,b) => b.storeAddress(v)
            ), s),
        }
    },
    store(self: AcceptDeal, b: c.Builder): void {
        b.storeUint(0x6d5f0007, 32);
        b.storeUint(self.queryId, 64);
        b.storeDict<c.Address, c.Address>(self.claims, c.Dictionary.Keys.Address(), createDictionaryValue<c.Address>(
            (s) => s.loadAddress(),
            (v,b) => b.storeAddress(v)
        ));
    },
    toCell(self: AcceptDeal): c.Cell {
        return makeCellFrom<AcceptDeal>(self, AcceptDeal.store);
    }
}

/**
 > struct (0xd1735400) TakeWalletAddressNosup {
 >     queryId: uint64
 >     walletAddress: address?
 >     rest: RemainingBitsAndRefs
 > }
 */
export interface TakeWalletAddressNosup {
    readonly $: 'TakeWalletAddressNosup'
    queryId: uint64
    walletAddress: c.Address | null
    rest: RemainingBitsAndRefs
}

export const TakeWalletAddressNosup = {
    PREFIX: 0xd1735400,

    create(args: {
        queryId: uint64
        walletAddress: c.Address | null
        rest: RemainingBitsAndRefs
    }): TakeWalletAddressNosup {
        return {
            $: 'TakeWalletAddressNosup',
            ...args
        }
    },
    fromSlice(s: c.Slice): TakeWalletAddressNosup {
        loadAndCheckPrefix32(s, 0xd1735400, 'TakeWalletAddressNosup');
        return {
            $: 'TakeWalletAddressNosup',
            queryId: s.loadUintBig(64),
            walletAddress: s.loadMaybeAddress(),
            rest: loadTolkRemaining(s),
        }
    },
    store(self: TakeWalletAddressNosup, b: c.Builder): void {
        b.storeUint(0xd1735400, 32);
        b.storeUint(self.queryId, 64);
        b.storeAddress(self.walletAddress);
        storeTolkRemaining(self.rest, b);
    },
    toCell(self: TakeWalletAddressNosup): c.Cell {
        return makeCellFrom<TakeWalletAddressNosup>(self, TakeWalletAddressNosup.store);
    }
}

/**
 > struct DistState {
 >     mode: uint3
 >     cursor: uint16
 > }
 */
export interface DistState {
    readonly $: 'DistState'
    mode: uint3
    cursor: uint16
}

export const DistState = {
    create(args: {
        mode: uint3
        cursor: uint16
    }): DistState {
        return {
            $: 'DistState',
            ...args
        }
    },
    fromSlice(s: c.Slice): DistState {
        return {
            $: 'DistState',
            mode: s.loadUintBig(3),
            cursor: s.loadUintBig(16),
        }
    },
    store(self: DistState, b: c.Builder): void {
        b.storeUint(self.mode, 3);
        b.storeUint(self.cursor, 16);
    },
    toCell(self: DistState): c.Cell {
        return makeCellFrom<DistState>(self, DistState.store);
    }
}

/**
 > struct Asset {
 >     kind: uint2
 >     ownerSide: uint2
 >     addr: address
 >     jettonWallet: address?
 >     amount: coins
 >     received: bool
 >     walletUnverified: bool
 >     bounces: uint4
 >     claimable: bool
 > }
 */
export interface Asset {
    readonly $: 'Asset'
    kind: uint2
    ownerSide: uint2
    addr: c.Address
    jettonWallet: c.Address | null
    amount: coins
    received: boolean
    walletUnverified: boolean
    bounces: uint4
    claimable: boolean
}

export const Asset = {
    create(args: {
        kind: uint2
        ownerSide: uint2
        addr: c.Address
        jettonWallet: c.Address | null
        amount: coins
        received: boolean
        walletUnverified: boolean
        bounces: uint4
        claimable: boolean
    }): Asset {
        return {
            $: 'Asset',
            ...args
        }
    },
    fromSlice(s: c.Slice): Asset {
        return {
            $: 'Asset',
            kind: s.loadUintBig(2),
            ownerSide: s.loadUintBig(2),
            addr: s.loadAddress(),
            jettonWallet: s.loadMaybeAddress(),
            amount: s.loadCoins(),
            received: s.loadBoolean(),
            walletUnverified: s.loadBoolean(),
            bounces: s.loadUintBig(4),
            claimable: s.loadBoolean(),
        }
    },
    store(self: Asset, b: c.Builder): void {
        b.storeUint(self.kind, 2);
        b.storeUint(self.ownerSide, 2);
        b.storeAddress(self.addr);
        b.storeAddress(self.jettonWallet);
        b.storeCoins(self.amount);
        b.storeBit(self.received);
        b.storeBit(self.walletUnverified);
        b.storeUint(self.bounces, 4);
        b.storeBit(self.claimable);
    },
    toCell(self: Asset): c.Cell {
        return makeCellFrom<Asset>(self, Asset.store);
    }
}

/**
 > struct GramState {
 >     gram1Amount: coins
 >     gram2Amount: coins
 >     gram1Received: coins
 >     gram2Received: coins
 >     gram1DepositReserve: coins
 >     gram2DepositReserve: coins
 >     serviceFee1: coins
 >     serviceFee2: coins
 > }
 */
export interface GramState {
    readonly $: 'GramState'
    gram1Amount: coins
    gram2Amount: coins
    gram1Received: coins
    gram2Received: coins
    gram1DepositReserve: coins
    gram2DepositReserve: coins
    serviceFee1: coins
    serviceFee2: coins
}

export const GramState = {
    create(args: {
        gram1Amount: coins
        gram2Amount: coins
        gram1Received: coins
        gram2Received: coins
        gram1DepositReserve: coins
        gram2DepositReserve: coins
        serviceFee1: coins
        serviceFee2: coins
    }): GramState {
        return {
            $: 'GramState',
            ...args
        }
    },
    fromSlice(s: c.Slice): GramState {
        return {
            $: 'GramState',
            gram1Amount: s.loadCoins(),
            gram2Amount: s.loadCoins(),
            gram1Received: s.loadCoins(),
            gram2Received: s.loadCoins(),
            gram1DepositReserve: s.loadCoins(),
            gram2DepositReserve: s.loadCoins(),
            serviceFee1: s.loadCoins(),
            serviceFee2: s.loadCoins(),
        }
    },
    store(self: GramState, b: c.Builder): void {
        b.storeCoins(self.gram1Amount);
        b.storeCoins(self.gram2Amount);
        b.storeCoins(self.gram1Received);
        b.storeCoins(self.gram2Received);
        b.storeCoins(self.gram1DepositReserve);
        b.storeCoins(self.gram2DepositReserve);
        b.storeCoins(self.serviceFee1);
        b.storeCoins(self.serviceFee2);
    },
    toCell(self: GramState): c.Cell {
        return makeCellFrom<GramState>(self, GramState.store);
    }
}

/**
 > struct SupervisorState {
 >     supervisor: address
 >     rescueAssets: map<uint16, address>
 >     rescueCount: uint16
 > }
 */
export interface SupervisorState {
    readonly $: 'SupervisorState'
    supervisor: c.Address
    rescueAssets: c.Dictionary<uint16, c.Address>
    rescueCount: uint16
}

export const SupervisorState = {
    create(args: {
        supervisor: c.Address
        rescueAssets: c.Dictionary<uint16, c.Address>
        rescueCount: uint16
    }): SupervisorState {
        return {
            $: 'SupervisorState',
            ...args
        }
    },
    fromSlice(s: c.Slice): SupervisorState {
        return {
            $: 'SupervisorState',
            supervisor: s.loadAddress(),
            rescueAssets: c.Dictionary.load<uint16, c.Address>(c.Dictionary.Keys.BigUint(16), createDictionaryValue<c.Address>(
                (s) => s.loadAddress(),
                (v,b) => b.storeAddress(v)
            ), s),
            rescueCount: s.loadUintBig(16),
        }
    },
    store(self: SupervisorState, b: c.Builder): void {
        b.storeAddress(self.supervisor);
        b.storeDict<uint16, c.Address>(self.rescueAssets, c.Dictionary.Keys.BigUint(16), createDictionaryValue<c.Address>(
            (s) => s.loadAddress(),
            (v,b) => b.storeAddress(v)
        ));
        b.storeUint(self.rescueCount, 16);
    },
    toCell(self: SupervisorState): c.Cell {
        return makeCellFrom<SupervisorState>(self, SupervisorState.store);
    }
}

/**
 > struct Storage {
 >     swapId: uint64
 >     phase: uint3
 >     owner1: address
 >     owner2: address
 >     feeWallet: address
 >     assetsCount: uint16
 >     required1Count: uint16
 >     required2Count: uint16
 >     received1Count: uint16
 >     received2Count: uint16
 >     pendingWallets: uint16
 >     jettonsCount: uint16
 >     receivedJettons1: uint16
 >     receivedJettons2: uint16
 >     assets: map<uint16, Asset>
 >     grams: Cell<GramState>
 >     sup: Cell<SupervisorState>
 >     dist: Cell<DistState>
 > }
 */
export interface Storage {
    readonly $: 'Storage'
    swapId: uint64
    phase: uint3
    owner1: c.Address
    owner2: c.Address
    feeWallet: c.Address
    assetsCount: uint16
    required1Count: uint16
    required2Count: uint16
    received1Count: uint16
    received2Count: uint16
    pendingWallets: uint16
    jettonsCount: uint16
    receivedJettons1: uint16
    receivedJettons2: uint16
    assets: c.Dictionary<uint16, Asset>
    grams: CellRef<GramState>
    sup: CellRef<SupervisorState>
    dist: CellRef<DistState>
}

export const Storage = {
    create(args: {
        swapId: uint64
        phase: uint3
        owner1: c.Address
        owner2: c.Address
        feeWallet: c.Address
        assetsCount: uint16
        required1Count: uint16
        required2Count: uint16
        received1Count: uint16
        received2Count: uint16
        pendingWallets: uint16
        jettonsCount: uint16
        receivedJettons1: uint16
        receivedJettons2: uint16
        assets: c.Dictionary<uint16, Asset>
        grams: CellRef<GramState>
        sup: CellRef<SupervisorState>
        dist: CellRef<DistState>
    }): Storage {
        return {
            $: 'Storage',
            ...args
        }
    },
    fromSlice(s: c.Slice): Storage {
        return {
            $: 'Storage',
            swapId: s.loadUintBig(64),
            phase: s.loadUintBig(3),
            owner1: s.loadAddress(),
            owner2: s.loadAddress(),
            feeWallet: s.loadAddress(),
            assetsCount: s.loadUintBig(16),
            required1Count: s.loadUintBig(16),
            required2Count: s.loadUintBig(16),
            received1Count: s.loadUintBig(16),
            received2Count: s.loadUintBig(16),
            pendingWallets: s.loadUintBig(16),
            jettonsCount: s.loadUintBig(16),
            receivedJettons1: s.loadUintBig(16),
            receivedJettons2: s.loadUintBig(16),
            assets: c.Dictionary.load<uint16, Asset>(c.Dictionary.Keys.BigUint(16), createDictionaryValue<Asset>(Asset.fromSlice, Asset.store), s),
            grams: loadCellRef<GramState>(s, GramState.fromSlice),
            sup: loadCellRef<SupervisorState>(s, SupervisorState.fromSlice),
            dist: loadCellRef<DistState>(s, DistState.fromSlice),
        }
    },
    store(self: Storage, b: c.Builder): void {
        b.storeUint(self.swapId, 64);
        b.storeUint(self.phase, 3);
        b.storeAddress(self.owner1);
        b.storeAddress(self.owner2);
        b.storeAddress(self.feeWallet);
        b.storeUint(self.assetsCount, 16);
        b.storeUint(self.required1Count, 16);
        b.storeUint(self.required2Count, 16);
        b.storeUint(self.received1Count, 16);
        b.storeUint(self.received2Count, 16);
        b.storeUint(self.pendingWallets, 16);
        b.storeUint(self.jettonsCount, 16);
        b.storeUint(self.receivedJettons1, 16);
        b.storeUint(self.receivedJettons2, 16);
        b.storeDict<uint16, Asset>(self.assets, c.Dictionary.Keys.BigUint(16), createDictionaryValue<Asset>(Asset.fromSlice, Asset.store));
        storeCellRef<GramState>(self.grams, b, GramState.store);
        storeCellRef<SupervisorState>(self.sup, b, SupervisorState.store);
        storeCellRef<DistState>(self.dist, b, DistState.store);
    },
    toCell(self: Storage): c.Cell {
        return makeCellFrom<Storage>(self, Storage.store);
    }
}

// ————————————————————————————————————————————
//    class SwapEscrowV2
//

interface ExtraSendOptions {
    bounce?: boolean                    // default: false
    sendMode?: SendMode                 // default: SendMode.PAY_GAS_SEPARATELY
    extraCurrencies?: c.ExtraCurrency   // default: empty dict
}

interface DeployedAddrOptions {
    workchain?: number                  // default: 0 (basechain)
    toShard?: { fixedPrefixLength: number; closeTo: c.Address }
    overrideContractCode?: c.Cell
}

function calculateDeployedAddress(code: c.Cell, data: c.Cell, options: DeployedAddrOptions): c.Address {
    const stateInitCell = beginCell().store(c.storeStateInit({
        code,
        data,
        splitDepth: options.toShard?.fixedPrefixLength,
        special: null,
        libraries: null,
    })).endCell();

    let addrHash = stateInitCell.hash();
    if (options.toShard) {
        const shardDepth = options.toShard.fixedPrefixLength;
        addrHash = beginCell()
            .storeBits(new c.BitString(options.toShard.closeTo.hash, 0, shardDepth))
            .storeBits(new c.BitString(stateInitCell.hash(), shardDepth, 256 - shardDepth))
            .endCell()
            .beginParse().loadBuffer(32);
    }

    return new c.Address(options.workchain ?? 0, addrHash);
}

export class SwapEscrowV2 implements c.Contract {
    static CodeCell = c.Cell.fromBase64('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');

    static Errors = {
        'Errors.NotOwner1': 401,
        'Errors.NotOwner2': 402,
        'Errors.NotOwners': 403,
        'Errors.NotSupervisor': 404,
        'Errors.NotRecipient': 405,
        'Errors.AlreadyFinalized': 410,
        'Errors.NotEnoughTon1': 420,
        'Errors.NotEnoughTon2': 421,
        'Errors.ServiceFee1': 422,
        'Errors.ServiceFee2': 423,
        'Errors.NftsNotReceived': 424,
        'Errors.InsufficientBalance': 430,
        'Errors.BadAssetIndex': 431,
        'Errors.NotClaimable': 432,
        'Errors.SideUnderfunded1': 433,
        'Errors.SideUnderfunded2': 434,
        'Errors.UnknownOp': 65535,
    }

    readonly address: c.Address
    readonly init: { code: c.Cell, data: c.Cell } | undefined

    protected constructor(address: c.Address, init?: { code: c.Cell, data: c.Cell }) {
        this.address = address;
        this.init = init;
    }

    static fromAddress(address: c.Address) {
        return new SwapEscrowV2(address);
    }

    static fromStorage(emptyStorage: {
        swapId: uint64
        phase: uint3
        owner1: c.Address
        owner2: c.Address
        feeWallet: c.Address
        assetsCount: uint16
        required1Count: uint16
        required2Count: uint16
        received1Count: uint16
        received2Count: uint16
        pendingWallets: uint16
        jettonsCount: uint16
        receivedJettons1: uint16
        receivedJettons2: uint16
        assets: c.Dictionary<uint16, Asset>
        grams: CellRef<GramState>
        sup: CellRef<SupervisorState>
        dist: CellRef<DistState>
    }, deployedOptions?: DeployedAddrOptions) {
        const initialState = {
            code: deployedOptions?.overrideContractCode ?? SwapEscrowV2.CodeCell,
            data: Storage.toCell(Storage.create(emptyStorage)),
        };
        const address = calculateDeployedAddress(initialState.code, initialState.data, deployedOptions ?? {});
        return new SwapEscrowV2(address, initialState);
    }

    static createCellOfOwnershipAssigned(body: {
        queryId: uint64
        previousOwner: c.Address
        forwardPayload: RemainingBitsAndRefs
    }) {
        return OwnershipAssigned.toCell(OwnershipAssigned.create(body));
    }

    static createCellOfTakeWalletAddressNosup(body: {
        queryId: uint64
        walletAddress: c.Address | null
        rest: RemainingBitsAndRefs
    }) {
        return TakeWalletAddressNosup.toCell(TakeWalletAddressNosup.create(body));
    }

    static createCellOfJettonTransferNotification(body: {
        queryId: uint64
        amount: coins
        sender: c.Address
        forwardPayload: RemainingBitsAndRefs
    }) {
        return JettonTransferNotification.toCell(JettonTransferNotification.create(body));
    }

    static createCellOfExcesses(body: {
        queryId: uint64
    }) {
        return Excesses.toCell(Excesses.create(body));
    }

    static createCellOfContinueDistribution(body: {
        queryId: uint64
    }) {
        return ContinueDistribution.toCell(ContinueDistribution.create(body));
    }

    static createCellOfClaimAsset(body: {
        queryId: uint64
        assetIndex: uint16
    }) {
        return ClaimAsset.toCell(ClaimAsset.create(body));
    }

    static createCellOfAcceptDeal(body: {
        queryId: uint64
        claims: c.Dictionary<c.Address, c.Address>
    }) {
        return AcceptDeal.toCell(AcceptDeal.create(body));
    }

    static createCellOfSupervisorAssetReceived(body: {
        assetAddr: c.Address
    }) {
        return SupervisorAssetReceived.toCell(SupervisorAssetReceived.create(body));
    }

    static createCellOfRescueNft(body: {
        nftAddr: c.Address
    }) {
        return RescueNft.toCell(RescueNft.create(body));
    }

    static createCellOfRescueJetton(body: {
        queryId: uint64
        jettonWallet: c.Address
        amount: coins
    }) {
        return RescueJetton.toCell(RescueJetton.create(body));
    }

    static createCellOfForceDeliver(body: {
        queryId: uint64
        assetIndex: uint16
        fallback: boolean
    }) {
        return ForceDeliver.toCell(ForceDeliver.create(body));
    }

    async sendDeploy(provider: ContractProvider, via: Sender, msgValue: coins, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: c.Cell.EMPTY,
            ...extraOptions
        });
    }

    async sendOwnershipAssigned(provider: ContractProvider, via: Sender, msgValue: coins, body: {
        queryId: uint64
        previousOwner: c.Address
        forwardPayload: RemainingBitsAndRefs
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: OwnershipAssigned.toCell(OwnershipAssigned.create(body)),
            ...extraOptions
        });
    }

    async sendTakeWalletAddressNosup(provider: ContractProvider, via: Sender, msgValue: coins, body: {
        queryId: uint64
        walletAddress: c.Address | null
        rest: RemainingBitsAndRefs
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: TakeWalletAddressNosup.toCell(TakeWalletAddressNosup.create(body)),
            ...extraOptions
        });
    }

    async sendJettonTransferNotification(provider: ContractProvider, via: Sender, msgValue: coins, body: {
        queryId: uint64
        amount: coins
        sender: c.Address
        forwardPayload: RemainingBitsAndRefs
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: JettonTransferNotification.toCell(JettonTransferNotification.create(body)),
            ...extraOptions
        });
    }

    async sendExcesses(provider: ContractProvider, via: Sender, msgValue: coins, body: {
        queryId: uint64
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: Excesses.toCell(Excesses.create(body)),
            ...extraOptions
        });
    }

    async sendContinueDistribution(provider: ContractProvider, via: Sender, msgValue: coins, body: {
        queryId: uint64
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: ContinueDistribution.toCell(ContinueDistribution.create(body)),
            ...extraOptions
        });
    }

    async sendClaimAsset(provider: ContractProvider, via: Sender, msgValue: coins, body: {
        queryId: uint64
        assetIndex: uint16
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: ClaimAsset.toCell(ClaimAsset.create(body)),
            ...extraOptions
        });
    }

    async sendAcceptDeal(provider: ContractProvider, via: Sender, msgValue: coins, body: {
        queryId: uint64
        claims: c.Dictionary<c.Address, c.Address>
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: AcceptDeal.toCell(AcceptDeal.create(body)),
            ...extraOptions
        });
    }

    async sendSupervisorAssetReceived(provider: ContractProvider, via: Sender, msgValue: coins, body: {
        assetAddr: c.Address
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: SupervisorAssetReceived.toCell(SupervisorAssetReceived.create(body)),
            ...extraOptions
        });
    }

    async sendRescueNft(provider: ContractProvider, via: Sender, msgValue: coins, body: {
        nftAddr: c.Address
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: RescueNft.toCell(RescueNft.create(body)),
            ...extraOptions
        });
    }

    async sendRescueJetton(provider: ContractProvider, via: Sender, msgValue: coins, body: {
        queryId: uint64
        jettonWallet: c.Address
        amount: coins
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: RescueJetton.toCell(RescueJetton.create(body)),
            ...extraOptions
        });
    }

    async sendForceDeliver(provider: ContractProvider, via: Sender, msgValue: coins, body: {
        queryId: uint64
        assetIndex: uint16
        fallback: boolean
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: ForceDeliver.toCell(ForceDeliver.create(body)),
            ...extraOptions
        });
    }

    async getPhase(provider: ContractProvider): Promise<bigint> {
        const r = StackReader.fromGetMethod(1, await provider.get('phase', []));
        return r.readBigInt();
    }

    async getSwapId(provider: ContractProvider): Promise<bigint> {
        const r = StackReader.fromGetMethod(1, await provider.get('swapId', []));
        return r.readBigInt();
    }

    async getCanAutoExecuteNow(provider: ContractProvider): Promise<boolean> {
        const r = StackReader.fromGetMethod(1, await provider.get('canAutoExecuteNow', []));
        return r.readBoolean();
    }

    async getExecutionShortfall(provider: ContractProvider): Promise<[
        bigint,
        bigint,
    ]> {
        const r = StackReader.fromGetMethod(2, await provider.get('executionShortfall', []));
        return [
            r.readBigInt(),
            r.readBigInt(),
        ];
    }

    async getCancelCost(provider: ContractProvider): Promise<[
        bigint,
        bigint,
    ]> {
        const r = StackReader.fromGetMethod(2, await provider.get('cancelCost', []));
        return [
            r.readBigInt(),
            r.readBigInt(),
        ];
    }

    async getStorageFloor(provider: ContractProvider): Promise<bigint> {
        const r = StackReader.fromGetMethod(1, await provider.get('storageFloor', []));
        return r.readBigInt();
    }

    async getReceivedCounts(provider: ContractProvider): Promise<[
        bigint,
        bigint,
    ]> {
        const r = StackReader.fromGetMethod(2, await provider.get('receivedCounts', []));
        return [
            r.readBigInt(),
            r.readBigInt(),
        ];
    }

    async getGramState(provider: ContractProvider): Promise<GramState> {
        const r = StackReader.fromGetMethod(8, await provider.get('gramState', []));
        return ({
            $: 'GramState',
            gram1Amount: r.readBigInt(),
            gram2Amount: r.readBigInt(),
            gram1Received: r.readBigInt(),
            gram2Received: r.readBigInt(),
            gram1DepositReserve: r.readBigInt(),
            gram2DepositReserve: r.readBigInt(),
            serviceFee1: r.readBigInt(),
            serviceFee2: r.readBigInt(),
        });
    }

    async getPendingWalletsLeft(provider: ContractProvider): Promise<bigint> {
        const r = StackReader.fromGetMethod(1, await provider.get('pendingWalletsLeft', []));
        return r.readBigInt();
    }

    async getAssetJettonWallet(provider: ContractProvider, idx: bigint): Promise<c.Address | null> {
        const r = StackReader.fromGetMethod(1, await provider.get('assetJettonWallet', [
            { type: 'int', value: idx },
        ]));
        return r.readNullable<c.Address>(
            (r) => r.readSlice().loadAddress()
        );
    }

    async getJettonWalletStatus(provider: ContractProvider, idx: bigint): Promise<[
        c.Address | null,
        boolean,
    ]> {
        const r = StackReader.fromGetMethod(2, await provider.get('jettonWalletStatus', [
            { type: 'int', value: idx },
        ]));
        return [
            r.readNullable<c.Address>(
                (r) => r.readSlice().loadAddress()
            ),
            r.readBoolean(),
        ];
    }

    async getDistributionProgress(provider: ContractProvider): Promise<[
        bigint,
        bigint,
    ]> {
        const r = StackReader.fromGetMethod(2, await provider.get('distributionProgress', []));
        return [
            r.readBigInt(),
            r.readBigInt(),
        ];
    }

    async getAssetStatus(provider: ContractProvider, idx: bigint): Promise<[
        boolean,
        boolean,
        bigint,
    ]> {
        const r = StackReader.fromGetMethod(3, await provider.get('assetStatus', [
            { type: 'int', value: idx },
        ]));
        return [
            r.readBoolean(),
            r.readBoolean(),
            r.readBigInt(),
        ];
    }

    async getClaimableAssets(provider: ContractProvider): Promise<c.Dictionary<uint16, boolean>> {
        const r = StackReader.fromGetMethod(1, await provider.get('claimableAssets', []));
        return r.readDictionary<uint16, boolean>(c.Dictionary.Keys.BigUint(16), c.Dictionary.Values.Bool());
    }

    async getSupervisor(provider: ContractProvider): Promise<c.Address> {
        const r = StackReader.fromGetMethod(1, await provider.get('supervisor', []));
        return r.readSlice().loadAddress();
    }
}
