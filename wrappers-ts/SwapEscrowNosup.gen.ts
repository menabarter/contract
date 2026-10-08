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
