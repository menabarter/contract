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
