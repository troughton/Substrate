//
//  ResourceMap.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 20/05/19.
//

import SubstrateUtilities
import Atomics

struct PersistentResourceMap<R : ResourceProtocolImpl & Equatable, V> {
    struct Chunk {
        @usableFromInline var keys : UnsafeMutablePointer<R?>
        @usableFromInline var values : UnsafeMutablePointer<V>
        
        init(allocator: AllocatorType) {
            let capacity = R.itemsPerChunk
            self.keys = Allocator.allocate(capacity: capacity, allocator: allocator)
            self.keys.initialize(repeating: nil, count: capacity)
            self.values = Allocator.allocate(capacity: capacity, allocator: allocator)
        }
        
        func `deinit`(allocator: AllocatorType) {
            for i in 0..<R.itemsPerChunk {
                if self.keys[i] != nil {
                    self.values.advanced(by: i).deinitialize(count: 1)
                }
            }
            Allocator.deallocate(self.keys, allocator: allocator)
            Allocator.deallocate(self.values, allocator: allocator)
        }
    }
    
    public typealias Index = Int
    
    let lock = SpinLock()
    
    let allocator: AllocatorType
    let chunks: UnsafeMutablePointer<Chunk>
    @usableFromInline var allocatedChunkCount: UnsafeMutablePointer<Int.AtomicRepresentation>
    
    public init(allocator: AllocatorType = .system) {
        self.allocator = allocator
        self.chunks = Allocator.allocate(capacity: R.PersistentRegistry.maxChunks, allocator: allocator)
        self.allocatedChunkCount = Allocator.allocate(capacity: 1, allocator: allocator)
        Int.AtomicRepresentation.atomicStore(0, at: self.allocatedChunkCount, ordering: .relaxed)
    }
    
    public func `deinit`() {
        for i in 0..<Int.AtomicRepresentation.atomicLoad(at: self.allocatedChunkCount, ordering: .relaxed) {
            self.chunks[i].deinit(allocator: self.allocator)
        }
        Allocator.deallocate(self.chunks, allocator: allocator)
        Allocator.deallocate(self.allocatedChunkCount, allocator: allocator)
        self.lock.deinit()
    }
    
    func keyAndValue(for resource: R) -> (key: UnsafeMutablePointer<R?>, value: UnsafeMutablePointer<V>)? {
        let (chunkIndex, indexInChunk) = resource.index.quotientAndRemainder(dividingBy: R.itemsPerChunk)
        if chunkIndex >= Int.AtomicRepresentation.atomicLoad(at: self.allocatedChunkCount, ordering: .relaxed) {
            return nil
        }
        if self.chunks[chunkIndex].keys[indexInChunk] == resource {
            return (self.chunks[chunkIndex].keys.advanced(by: indexInChunk),
                    self.chunks[chunkIndex].values.advanced(by: indexInChunk))
        }
        return nil
    }
    
    func allocateKeyAndValue(for resource: R) -> (key: UnsafeMutablePointer<R?>, value: UnsafeMutablePointer<V>) {
        let (chunkIndex, indexInChunk) = resource.index.quotientAndRemainder(dividingBy: R.itemsPerChunk)
        let allocatedChunkCount = Int.AtomicRepresentation.atomicLoad(at: self.allocatedChunkCount, ordering: .relaxed)
        if chunkIndex >= allocatedChunkCount {
            self.lock.lock()
            while chunkIndex >= Int.AtomicRepresentation.atomicLoad(at: self.allocatedChunkCount, ordering: .relaxed) {
                let newChunkIndex = Int.AtomicRepresentation.atomicLoadThenWrappingIncrement(by: 1, at: self.allocatedChunkCount, ordering: .relaxed)
                self.chunks.advanced(by: newChunkIndex).initialize(to: .init(allocator: self.allocator))
            }
            self.lock.unlock()
        }
        return (self.chunks[chunkIndex].keys.advanced(by: indexInChunk),
                self.chunks[chunkIndex].values.advanced(by: indexInChunk))
    }
    
    @inlinable
    public func contains(_ resource: R) -> Bool {
        if resource._usesPersistentRegistry {
            return self.keyAndValue(for: resource) != nil
        } else {
            return false
        }
    }
    
    @inlinable
    public subscript(resource: R) -> V? {
        _read {
            yield self.keyAndValue(for: resource)?.value.pointee
        }
        set {
            assert(resource._usesPersistentRegistry)
            
            let (keyPtr, valuePtr) = self.allocateKeyAndValue(for: resource)
            
            if let newValue = newValue {
                if keyPtr.pointee != nil {
                    valuePtr.pointee = newValue
                } else {
                    valuePtr.initialize(to: newValue)
                }
                
                keyPtr.pointee = resource
            } else {
                if keyPtr.pointee != nil {
                    valuePtr.deinitialize(count: 1)
                }
                
                keyPtr.pointee = nil
            }
        }
    }
    
    @inlinable
    public subscript(resource: R, default default: @autoclosure () -> V) -> V {
        get {
            return self[resource] ?? `default`()
        }
        set {
            self[resource] = newValue
        }
    }
    
    @inlinable
    @discardableResult
    public mutating func removeValue(forKey resource: R) -> V? {
        if resource._usesPersistentRegistry {
            guard let (keyPtr, valuePtr) = self.keyAndValue(for: resource) else {
                return nil
            }
            keyPtr.pointee = nil
            return valuePtr.move()
        } else {
            return nil
        }
    }
    
    @inlinable
    public mutating func removeAll() {
        for chunkIndex in 0..<Int.AtomicRepresentation.atomicLoad(at: self.allocatedChunkCount, ordering: .relaxed) {
            let chunk = self.chunks[chunkIndex]
            for i in 0..<R.itemsPerChunk {
                if chunk.keys[i] != nil {
                    chunk.keys[i] = nil
                    chunk.values.advanced(by: 1).deinitialize(count: 1)
                }
            }
        }
    }
    
    @inlinable
    public mutating func removeAll(iterating iterator: (R, V, _ isPersistent: Bool) -> Void) {
        for chunkIndex in 0..<Int.AtomicRepresentation.atomicLoad(at: self.allocatedChunkCount, ordering: .relaxed) {
            let chunk = self.chunks[chunkIndex]
            for i in 0..<R.itemsPerChunk {
                if let key = chunk.keys[i] {
                    iterator(key, chunk.values.advanced(by: i).move(), true)
                    chunk.keys[i] = nil
                }
            }
        }
    }
    
    @inlinable
    public func forEach(_ body: ((R, V)) throws -> Void) rethrows {
        for chunkIndex in 0..<Int.AtomicRepresentation.atomicLoad(at: self.allocatedChunkCount, ordering: .relaxed) {
            let chunk = self.chunks[chunkIndex]
            for i in 0..<R.itemsPerChunk {
                if let key = chunk.keys[i] {
                    try body((key, chunk.values[i]))
                }
            }
        }
    }
    
    @inlinable
    public mutating func forEachMutating(_ body: (R, inout V, _ deleteEntry: inout Bool) throws -> Void) rethrows {
        for chunkIndex in 0..<Int.AtomicRepresentation.atomicLoad(at: self.allocatedChunkCount, ordering: .relaxed) {
            let chunk = self.chunks[chunkIndex]
            for i in 0..<R.itemsPerChunk {
                guard let key = chunk.keys[i] else { continue }
                var deleteEntry = false
                try body(key, &chunk.values[i], &deleteEntry)
                if deleteEntry {
                    chunk.keys[i] = nil
                    chunk.values.advanced(by: i).deinitialize(count: 1)
                }
            }
        }
    }
    
    /// Passes back a pointer to the address where the value should go for a given key.
    /// The bool argument indicates whether the pointer is currently initialised.
    @inlinable
    public mutating func withValue<T>(forKey resource: R, perform: (UnsafeMutablePointer<V>, Bool) -> T) -> T {
        assert(resource._usesPersistentRegistry)
        let (keyPtr, valuePtr) = self.allocateKeyAndValue(for: resource)
        if let key = keyPtr.pointee, key != resource {
            valuePtr.deinitialize(count: 1)
            keyPtr.pointee = resource
            return perform(valuePtr, false)
        } else {
            return perform(valuePtr, keyPtr.pointee == resource)
        }
    }
}


public struct TransientResourceMap<R : ResourceProtocol & Equatable, V> {
    
    public let allocator : AllocatorType
    let transientRegistryIndex : Int
    
    public typealias Index = Int
    
    @usableFromInline var keys : UnsafeMutablePointer<R?>! = nil
    
    @usableFromInline var values : UnsafeMutablePointer<V>! = nil
    
    @usableFromInline var capacity = 0
    
    @usableFromInline var count = 0
    
    public init(allocator: AllocatorType = .system, transientRegistryIndex: Int) {
        self.allocator = allocator
        self.transientRegistryIndex = transientRegistryIndex
        
        if self.transientRegistryIndex < 0 {
            return
        }
        
        switch R.self {
        case is Buffer.Type:
            self.reserveCapacity(TransientBufferRegistry.instances[self.transientRegistryIndex].capacity)
        case is Texture.Type:
            self.reserveCapacity(TransientTextureRegistry.instances[self.transientRegistryIndex].capacity)
        case is ArgumentBuffer.Type:
            break
        case is ArgumentBufferArray.Type:
            self.reserveCapacity(TransientArgumentBufferArrayRegistry.instances[self.transientRegistryIndex].capacity)
        case is Heap.Type:
            break
        default:
            if #available(macOS 11.0, iOS 14.0, *), R.self is AccelerationStructure.Type {
                break
            } else {
                fatalError()
            }
        }
    }

    public mutating func prepareFrame() {
        if self.transientRegistryIndex < 0 {
            return
        }
        
        switch R.self {
        case is Buffer.Type:
            self.count = Int.AtomicRepresentation.atomicLoad(at: TransientBufferRegistry.instances[self.transientRegistryIndex].count, ordering: .relaxed)
        case is Texture.Type:
            self.count = Int.AtomicRepresentation.atomicLoad(at: TransientTextureRegistry.instances[self.transientRegistryIndex].count, ordering: .relaxed)
        case is ArgumentBuffer.Type:
            let count = TransientArgumentBufferRegistry.instances[self.transientRegistryIndex].count
            self.reserveCapacity(count)
            self.count = count
        case is ArgumentBufferArray.Type:
            self.count = TransientArgumentBufferRegistry.instances[self.transientRegistryIndex].count
        case is Heap.Type:
            break
        default:
            fatalError()
        }
    }
    
    @inlinable
    mutating func reserveCapacity(_ capacity: Int) {
        if capacity <= self.capacity {
            return
        }
        
        let oldCapacity = self.capacity
        
        let newKeys : UnsafeMutablePointer<R?> = Allocator.allocate(capacity: capacity, allocator: self.allocator)
        newKeys.initialize(repeating: nil, count: capacity)
        
        let newValues : UnsafeMutablePointer<V> = Allocator.allocate(capacity: capacity, allocator: self.allocator)
        
        let oldKeys = self.keys
        let oldValues = self.values
        
        self.capacity = capacity
        self.keys = newKeys
        self.values = newValues
        
        for index in 0..<oldCapacity {
            if oldKeys.unsafelyUnwrapped[index] != nil {
                let sourceKey = oldKeys!.advanced(by: index).move()
                
                self.keys.advanced(by: index).initialize(to: sourceKey)
                self.values.advanced(by: index).moveInitialize(from: oldValues.unsafelyUnwrapped.advanced(by: index), count: 1)
            }
        }
        
        if oldCapacity > 0 {
            Allocator.deallocate(oldKeys!, allocator: self.allocator)
            Allocator.deallocate(oldValues!, allocator: self.allocator)
        }
    }
    
    public func `deinit`() {
        for bucket in 0..<self.capacity {
            if self.keys[bucket] != nil {
                self.values.advanced(by: bucket).deinitialize(count: 1)
            }
        }
        if self.capacity > 0 {
            Allocator.deallocate(self.keys, allocator: self.allocator)
            Allocator.deallocate(self.values, allocator: self.allocator)
        }
    }
    
    @inlinable
    public func contains(_ resource: R) -> Bool {
        if resource._usesPersistentRegistry {
            return false
        } else {
            return self.keys[resource.index] == resource
        }
    }
    
    @inlinable
    public subscript(resource: R) -> V? {
        _read {
            if resource._usesPersistentRegistry {
                yield nil
            } else {
                assert(resource.index < self.capacity)
                
                if self.keys[resource.index] == resource {
                    yield self.values[resource.index]
                } else {
                    yield nil
                }
            }
        }
        set {
            assert(!resource._usesPersistentRegistry)
            assert(resource.index < self.capacity)
            
            if let newValue = newValue {
                if self.keys[resource.index] != nil {
                    self.values[resource.index] = newValue
                } else {
                    self.values.advanced(by: resource.index).initialize(to: newValue)
                }
                
                self.keys[resource.index] = resource
            } else {
                if self.keys[resource.index] != nil {
                    self.values.advanced(by: resource.index).deinitialize(count: 1)
                }
                
                self.keys[resource.index] = nil
            }
        }
    }
    
    @inlinable
    public subscript(resource: R, default default: @autoclosure () -> V) -> V {
        get {
            return self[resource] ?? `default`()
        }
        set {
            self[resource] = newValue
        }
    }
    
    @inlinable
    @discardableResult
    public mutating func removeValue(forKey resource: R) -> V? {
        if resource._usesPersistentRegistry {
            return nil
        } else {
            if self.keys[resource.index] != resource {
                return nil
            }
            
            self.keys[resource.index] = nil
            return self.values.advanced(by: resource.index).move()
        }
        
    }
    
    @inlinable
    public mutating func removeAll() {
        for bucket in 0..<self.count {
            if self.keys[bucket] != nil {
                self.keys[bucket] = nil
                self.values.advanced(by: bucket).deinitialize(count: 1)
            }
        }
    }
    
    @inlinable
    public mutating func removeAll(iterating iterator: (R, V, _ isPersistent: Bool) -> Void) {
        for bucket in 0..<self.count {
            if let key = self.keys[bucket] {
                iterator(key, self.values[bucket], false)
                self.keys[bucket] = nil
                self.values.advanced(by: bucket).deinitialize(count: 1)
            }
        }
    }
    
    @inlinable
    public func forEach(_ body: ((R, V)) throws -> Void) rethrows {
        for bucket in 0..<self.count {
            if let key = self.keys[bucket] {
                try body((key, self.values[bucket]))
            }
        }
    }
    
    @inlinable
    public mutating func forEachMutating(_ body: (R, inout V, _ deleteEntry: inout Bool) throws -> Void) rethrows {
        for bucket in 0..<self.count {
            guard let key = self.keys[bucket] else { continue }
            var deleteEntry = false
            try body(key, &self.values[bucket], &deleteEntry)
            if deleteEntry {
                self.keys[bucket] = nil
                self.values.advanced(by: bucket).deinitialize(count: 1)
            }
        }
    }
    
    /// Passes back a pointer to the address where the value should go for a given key.
    /// The bool argument indicates whether the pointer is currently initialised.
    @inlinable
    public mutating func withValue<T>(forKey resource: R, perform: (UnsafeMutablePointer<V>, Bool) -> T) -> T {
        assert(!resource._usesPersistentRegistry)
        return perform(self.values.advanced(by: resource.index), self.keys[resource.index] == resource)
    }
}


/// A resource-specific constant-time access map specifically for RenderGraph resources.
<<<<<<< HEAD
public struct ResourceMap<R : ResourceProtocol & Equatable, V> {
=======
struct ResourceMap<R : ResourceProtocolImpl & Equatable, V> {
>>>>>>> main
    
    public let allocator : AllocatorType
    
    public typealias Index = Int
    
    public var transientMap : TransientResourceMap<R, V>
    public var persistentMap : PersistentResourceMap<R, V>
    
    public init(allocator: AllocatorType = .system, transientRegistryIndex: Int) {
        self.allocator = allocator
        
        self.transientMap = TransientResourceMap(allocator: allocator, transientRegistryIndex: transientRegistryIndex)
        self.persistentMap = PersistentResourceMap(allocator: allocator)
    }

    public mutating func prepareFrame() {
        self.transientMap.prepareFrame()
    }
    
    public func `deinit`() {
        self.transientMap.deinit()
        self.persistentMap.deinit()
    }
    
    @inlinable
    public func contains(_ resource: R) -> Bool {
        if resource._usesPersistentRegistry {
            return self.persistentMap.contains(resource)
        } else {
            return self.transientMap.contains(resource)
        }
    }
    
    @inlinable
    public subscript(resource: R) -> V? {
        _read {
            if resource._usesPersistentRegistry {
                yield self.persistentMap[resource]
            } else {
                yield self.transientMap[resource]
            }
        }
        set {
            if resource._usesPersistentRegistry {
                self.persistentMap[resource] = newValue
            } else {
                self.transientMap[resource] = newValue
            }
        }
    }
    
    @inlinable
    public subscript(resource: R, default default: @autoclosure () -> V) -> V {
        get {
            return self[resource] ?? `default`()
        }
        set {
            self[resource] = newValue
        }
    }
    
    @inlinable
    @discardableResult
    public mutating func removeValue(forKey resource: R) -> V? {
        if resource._usesPersistentRegistry {
            return self.persistentMap.removeValue(forKey: resource)
        } else {
            return self.transientMap.removeValue(forKey: resource)
        }
        
    }
    
    @inlinable
    public mutating func removeAll() {
        self.transientMap.removeAll()
        self.persistentMap.removeAll()
    }
    
    @inlinable
    public mutating func removeAll(iterating iterator: (R, V, _ isPersistent: Bool) -> Void) {
        self.transientMap.removeAll(iterating: iterator)
        self.persistentMap.removeAll(iterating: iterator)
    }
    
    @inlinable
    public func forEach(_ body: ((R, V)) throws -> Void) rethrows {
        try self.transientMap.forEach(body)
        try self.persistentMap.forEach(body)
    }
    
    @inlinable
    public mutating func forEachMutating(_ body: (R, inout V, _ deleteEntry: inout Bool) throws -> Void) rethrows {
        try self.transientMap.forEachMutating(body)
        try self.persistentMap.forEachMutating(body)
    }
    
    /// Passes back a pointer to the address where the value should go for a given key.
    /// The bool argument indicates whether the pointer is currently initialised.
    @inlinable
    public mutating func withValue<T>(forKey resource: R, perform: (UnsafeMutablePointer<V>, Bool) -> T) -> T {
        if resource._usesPersistentRegistry {
            return self.persistentMap.withValue(forKey: resource, perform: perform)
        } else {
            return self.transientMap.withValue(forKey: resource, perform: perform)
        }
    }
}
