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
