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
