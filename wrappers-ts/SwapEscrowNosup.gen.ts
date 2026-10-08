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
