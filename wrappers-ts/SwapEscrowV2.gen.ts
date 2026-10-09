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
