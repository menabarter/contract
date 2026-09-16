// Copyright (C) 2026 MENA
// SPDX-License-Identifier: AGPL-3.0-or-later

// AUTO-GENERATED, do not edit
// It's a TypeScript wrapper for a SwapEscrow contract in Tolk.
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
 > struct DistState {
 >     mode: uint3
 >     cursor: uint16
 >     retryCount: uint16
 >     retry: map<uint16, bool>
 > }
 */
export interface DistState {
    readonly $: 'DistState'
    mode: uint3
    cursor: uint16
    retryCount: uint16
    retry: c.Dictionary<uint16, boolean>
}

export const DistState = {
    create(args: {
        mode: uint3
        cursor: uint16
        retryCount: uint16
        retry: c.Dictionary<uint16, boolean>
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
            retryCount: s.loadUintBig(16),
            retry: c.Dictionary.load<uint16, boolean>(c.Dictionary.Keys.BigUint(16), c.Dictionary.Values.Bool(), s),
        }
    },
    store(self: DistState, b: c.Builder): void {
        b.storeUint(self.mode, 3);
        b.storeUint(self.cursor, 16);
        b.storeUint(self.retryCount, 16);
        b.storeDict<uint16, boolean>(self.retry, c.Dictionary.Keys.BigUint(16), c.Dictionary.Values.Bool());
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
 >     abandoned: bool
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
    abandoned: boolean
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
        abandoned: boolean
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
            abandoned: s.loadBoolean(),
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
        b.storeBit(self.abandoned);
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
//    class SwapEscrow
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

export class SwapEscrow implements c.Contract {
    static CodeCell = c.Cell.fromBase64('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');

    static Errors = {
        'Errors.NotOwner1': 401,
        'Errors.NotOwner2': 402,
        'Errors.NotOwners': 403,
        'Errors.NotSupervisor': 404,
        'Errors.AlreadyFinalized': 410,
        'Errors.NotEnoughTon1': 420,
        'Errors.NotEnoughTon2': 421,
        'Errors.ServiceFee1': 422,
        'Errors.ServiceFee2': 423,
        'Errors.NftsNotReceived': 424,
        'Errors.InsufficientBalance': 430,
        'Errors.BadAssetIndex': 431,
        'Errors.UnknownOp': 65535,
    }

    readonly address: c.Address
    readonly init: { code: c.Cell, data: c.Cell } | undefined

    protected constructor(address: c.Address, init?: { code: c.Cell, data: c.Cell }) {
        this.address = address;
        this.init = init;
    }

    static fromAddress(address: c.Address) {
        return new SwapEscrow(address);
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
            code: deployedOptions?.overrideContractCode ?? SwapEscrow.CodeCell,
            data: Storage.toCell(Storage.create(emptyStorage)),
        };
        const address = calculateDeployedAddress(initialState.code, initialState.data, deployedOptions ?? {});
        return new SwapEscrow(address, initialState);
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
        bigint,
    ]> {
        const r = StackReader.fromGetMethod(3, await provider.get('distributionProgress', []));
        return [
            r.readBigInt(),
            r.readBigInt(),
            r.readBigInt(),
        ];
    }
}
