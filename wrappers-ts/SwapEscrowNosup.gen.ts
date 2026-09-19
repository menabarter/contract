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
 > struct (0xd1735400) TakeWalletAddress {
 >     queryId: uint64
 >     walletAddress: address
 >     rest: RemainingBitsAndRefs
 > }
 */
export interface TakeWalletAddress {
    readonly $: 'TakeWalletAddress'
    queryId: uint64
    walletAddress: c.Address
    rest: RemainingBitsAndRefs
}

export const TakeWalletAddress = {
    PREFIX: 0xd1735400,

    create(args: {
        queryId: uint64
        walletAddress: c.Address
        rest: RemainingBitsAndRefs
    }): TakeWalletAddress {
        return {
            $: 'TakeWalletAddress',
            ...args
        }
    },
    fromSlice(s: c.Slice): TakeWalletAddress {
        loadAndCheckPrefix32(s, 0xd1735400, 'TakeWalletAddress');
        return {
            $: 'TakeWalletAddress',
            queryId: s.loadUintBig(64),
            walletAddress: s.loadAddress(),
            rest: loadTolkRemaining(s),
        }
    },
    store(self: TakeWalletAddress, b: c.Builder): void {
        b.storeUint(0xd1735400, 32);
        b.storeUint(self.queryId, 64);
        b.storeAddress(self.walletAddress);
        storeTolkRemaining(self.rest, b);
    },
    toCell(self: TakeWalletAddress): c.Cell {
        return makeCellFrom<TakeWalletAddress>(self, TakeWalletAddress.store);
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
 >     sent: bool
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
    sent: boolean
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
        sent: boolean
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
            sent: s.loadBoolean(),
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
        b.storeBit(self.sent);
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

    static createCellOfTakeWalletAddress(body: {
        queryId: uint64
        walletAddress: c.Address
        rest: RemainingBitsAndRefs
    }) {
        return TakeWalletAddress.toCell(TakeWalletAddress.create(body));
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

    async sendTakeWalletAddress(provider: ContractProvider, via: Sender, msgValue: coins, body: {
        queryId: uint64
        walletAddress: c.Address
        rest: RemainingBitsAndRefs
    }, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: TakeWalletAddress.toCell(TakeWalletAddress.create(body)),
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
