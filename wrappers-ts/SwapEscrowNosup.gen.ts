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

    static createCellOfAcceptDeal(body: {
        queryId: uint64
        claims: c.Dictionary<c.Address, c.Address>
    }) {
        return AcceptDeal.toCell(AcceptDeal.create(body));
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
}
