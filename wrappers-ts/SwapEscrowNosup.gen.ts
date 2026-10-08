// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// AUTO-GENERATED, do not edit
// It's a TypeScript wrapper for a SwapEscrowNosup contract in Tolk.
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
        storeCellRef<DistState>(self.dist, b, DistState.store);
    },
    toCell(self: Storage): c.Cell {
        return makeCellFrom<Storage>(self, Storage.store);
    }
}

// ————————————————————————————————————————————
//    class SwapEscrowNosup
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

export class SwapEscrowNosup implements c.Contract {
    static CodeCell = c.Cell.fromBase64('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');

    static Errors = {
        'Errors.NotOwner1': 401,
        'Errors.NotOwner2': 402,
        'Errors.NotOwners': 403,
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
        return new SwapEscrowNosup(address);
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
        dist: CellRef<DistState>
    }, deployedOptions?: DeployedAddrOptions) {
        const initialState = {
            code: deployedOptions?.overrideContractCode ?? SwapEscrowNosup.CodeCell,
            data: Storage.toCell(Storage.create(emptyStorage)),
        };
        const address = calculateDeployedAddress(initialState.code, initialState.data, deployedOptions ?? {});
        return new SwapEscrowNosup(address, initialState);
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
}
