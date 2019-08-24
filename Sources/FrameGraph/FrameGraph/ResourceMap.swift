//
//  ResourceMap.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 20/05/19.
//

import FrameGraphUtilities

/// A resource-specific constant-time access map specifically for FrameGraph resources.
public struct ResourceMap<R : ResourceProtocol, V> {
    
    public let allocator : AllocatorType
    
    public typealias Index = Int
    
    @usableFromInline var transientKeys : UnsafeMutablePointer<R>! = nil
    @usableFromInline var persistentKeys : UnsafeMutablePointer<R>! = nil
    
    @usableFromInline var transientValues : UnsafeMutablePointer<V>! = nil
    @usableFromInline var persistentValues : UnsafeMutablePointer<V>! = nil
    
    @usableFromInline var transientResourceCapacity = 0
    @usableFromInline var persistentResourceCapacity = 0
    
    public init(allocator: AllocatorType = .system) {
        self.allocator = allocator
    }

    public mutating func prepareFrame() {
        switch R.self {
        case is Buffer.Type:
            self.reserveTransientCapacity(TransientBufferRegistry.instance.capacity)
            self.reservePersistentCapacity(PersistentBufferRegistry.instance.maxIndex)
        case is Texture.Type:
            self.reserveTransientCapacity(TransientTextureRegistry.instance.capacity)
            self.reservePersistentCapacity(PersistentTextureRegistry.instance.maxIndex)
        case is _ArgumentBuffer.Type:
            self.reserveTransientCapacity(TransientArgumentBufferRegistry.instance.count)
            self.reservePersistentCapacity(PersistentArgumentBufferRegistry.instance.maxIndex)
        case is _ArgumentBufferArray.Type:
            self.reserveTransientCapacity(TransientArgumentBufferArrayRegistry.instance.capacity)
            self.reservePersistentCapacity(PersistentArgumentBufferArrayRegistry.instance.maxIndex)
        default:
            fatalError()
        }
    }
    
    @inlinable
    mutating func reserveTransientCapacity(_ capacity: Int) {
        if capacity <= self.transientResourceCapacity {
            return
        }
        
        let oldCapacity = self.transientResourceCapacity
        
        let newKeys : UnsafeMutablePointer<R> = Allocator.allocate(capacity: capacity, allocator: self.allocator)
        newKeys.initialize(repeating: R(handle: Resource.invalidResource.handle), count: capacity)
        
        let newValues : UnsafeMutablePointer<V> = Allocator.allocate(capacity: capacity, allocator: self.allocator)
        
        let oldKeys = self.transientKeys
        let oldValues = self.transientValues
        
        self.transientResourceCapacity = capacity
        self.transientKeys = newKeys
        self.transientValues = newValues
        
        for index in 0..<oldCapacity {
            if oldKeys.unsafelyUnwrapped[index].handle != Resource.invalidResource.handle {
                let sourceKey = oldKeys!.advanced(by: index).move()
                
                self.transientKeys.advanced(by: index).initialize(to: sourceKey)
                self.transientValues.advanced(by: index).moveInitialize(from: oldValues.unsafelyUnwrapped.advanced(by: index), count: 1)
            }
        }
        
        if oldCapacity > 0 {
            Allocator.deallocate(oldKeys!, allocator: self.allocator)
            Allocator.deallocate(oldValues!, allocator: self.allocator)
        }
    }
    
    @inlinable mutating func reservePersistentCapacity(_ capacity: Int) {
        if capacity <= self.persistentResourceCapacity {
            return
        }
        let capacity = max(capacity, 2 * self.persistentResourceCapacity)
        
        let oldCapacity = self.persistentResourceCapacity
        
        let newKeys : UnsafeMutablePointer<R> = Allocator.allocate(capacity: capacity, allocator: self.allocator)
        newKeys.initialize(repeating: R(handle: Resource.invalidResource.handle), count: capacity)
        
        let newValues : UnsafeMutablePointer<V> = Allocator.allocate(capacity: capacity, allocator: self.allocator)
        
        let oldKeys = self.persistentKeys
        let oldValues = self.persistentValues
        
        self.persistentResourceCapacity = capacity
        self.persistentKeys = newKeys
        self.persistentValues = newValues
        
        for index in 0..<oldCapacity {
            if oldKeys.unsafelyUnwrapped[index].handle != Resource.invalidResource.handle {
                let sourceKey = oldKeys!.advanced(by: index).move()
                
                self.persistentKeys.advanced(by: index).initialize(to: sourceKey)
                self.persistentValues.advanced(by: index).moveInitialize(from: oldValues.unsafelyUnwrapped.advanced(by: index), count: 1)
            }
        }
        
        if oldCapacity > 0 {
            Allocator.deallocate(oldKeys!, allocator: self.allocator)
            Allocator.deallocate(oldValues!, allocator: self.allocator)
        }
    }
    
    
    public func `deinit`() {
        for bucket in 0..<self.transientResourceCapacity {
            if self.transientKeys[bucket].handle != Resource.invalidResource.handle {
                self.transientValues.advanced(by: bucket).deinitialize(count: 1)
            }
        }
        
        for bucket in 0..<self.persistentResourceCapacity {
            if self.persistentKeys[bucket].handle != Resource.invalidResource.handle {
                self.persistentValues.advanced(by: bucket).deinitialize(count: 1)
            }
        }
        
        if self.transientResourceCapacity > 0 {
            Allocator.deallocate(self.transientKeys, allocator: self.allocator)
            Allocator.deallocate(self.transientValues, allocator: self.allocator)
        }
        
        if self.persistentResourceCapacity > 0 {
            Allocator.deallocate(self.persistentKeys, allocator: self.allocator)
            Allocator.deallocate(self.persistentValues, allocator: self.allocator)
        }
    }
    
    @inlinable
    public func contains(resource: R) -> Bool {
        if resource._usesPersistentRegistry {
            return self.persistentKeys[resource.index] == resource
        } else {
            return self.transientKeys[resource.index] == resource
        }
    }
    
    @inlinable
    public subscript(resource: R) -> V? {
        _read {
            if resource._usesPersistentRegistry {
                assert(resource.index < self.persistentResourceCapacity)
                
                if self.persistentKeys[resource.index] == resource {
                    yield self.persistentValues[resource.index]
                } else {
                    yield nil
                }
            } else {
                assert(resource.index < self.transientResourceCapacity)
                
                if self.transientKeys[resource.index] == resource {
                    yield self.transientValues[resource.index]
                } else {
                    yield nil
                }
            }
        }
        set {
            if let newValue = newValue {
                if resource._usesPersistentRegistry {
                    assert(resource.index < self.persistentResourceCapacity)
                    
                    if self.persistentKeys[resource.index] != R(handle: Resource.invalidResource.handle) {
                        self.persistentValues[resource.index] = newValue
                    } else {
                        self.persistentValues.advanced(by: resource.index).initialize(to: newValue)
                    }
                    
                    self.persistentKeys[resource.index] = resource
                } else {
                    assert(resource.index < self.transientResourceCapacity)
                    
                    if self.transientKeys[resource.index] != R(handle: Resource.invalidResource.handle) {
                        self.transientValues[resource.index] = newValue
                    } else {
                        self.transientValues.advanced(by: resource.index).initialize(to: newValue)
                    }
                    
                    self.transientKeys[resource.index] = resource
                }
            } else {
                if resource._usesPersistentRegistry {
                    assert(resource.index < self.persistentResourceCapacity)
                    
                    if self.persistentKeys[resource.index] != R(handle: Resource.invalidResource.handle) {
                        self.persistentValues.advanced(by: resource.index).deinitialize(count: 1)
                    }
                    
                    self.persistentKeys[resource.index] = R(handle: Resource.invalidResource.handle)
                } else {
                    assert(resource.index < self.transientResourceCapacity)
                    
                    if self.transientKeys[resource.index] != R(handle: Resource.invalidResource.handle) {
                        self.transientValues.advanced(by: resource.index).deinitialize(count: 1)
                    }
                    
                    self.transientKeys[resource.index] = R(handle: Resource.invalidResource.handle)
                }
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
            if self.persistentKeys[resource.index] != resource {
                return nil
            }
            
            self.persistentKeys[resource.index] = R(handle: Resource.invalidResource.handle)
            return self.persistentValues.advanced(by: resource.index).move()
        } else {
            if self.transientKeys[resource.index] != resource {
                return nil
            }
            
            self.transientKeys[resource.index] = R(handle: Resource.invalidResource.handle)
            return self.transientValues.advanced(by: resource.index).move()
        }
        
    }
    
    @inlinable
    public mutating func removeAllTransient() {
        for bucket in 0..<self.transientResourceCapacity {
            if self.transientKeys[bucket] != R(handle: Resource.invalidResource.handle) {
                self.transientKeys[bucket] = R(handle: Resource.invalidResource.handle)
                self.transientValues.advanced(by: bucket).deinitialize(count: 1)
            }
        }
    }
    
    @inlinable
    public mutating func removeAll() {
        for bucket in 0..<self.transientResourceCapacity {
            if self.transientKeys[bucket] != R(handle: Resource.invalidResource.handle) {
                self.transientKeys[bucket] = R(handle: Resource.invalidResource.handle)
                self.transientValues.advanced(by: bucket).deinitialize(count: 1)
            }
        }
        
        for bucket in 0..<self.persistentResourceCapacity {
            if self.persistentKeys[bucket] != R(handle: Resource.invalidResource.handle) {
                self.persistentKeys[bucket] = R(handle: Resource.invalidResource.handle)
                self.persistentValues.advanced(by: bucket).deinitialize(count: 1)
            }
        }
    }
    
    @inlinable
    public mutating func removeAll(iterating iterator: (R, V, _ isPersistent: Bool) -> Void) {
        for bucket in 0..<self.transientResourceCapacity {
            if self.transientKeys[bucket] != R(handle: Resource.invalidResource.handle) {
                iterator(self.transientKeys[bucket], self.transientValues[bucket], false)
                self.transientKeys[bucket] = R(handle: Resource.invalidResource.handle)
                self.transientValues.advanced(by: bucket).deinitialize(count: 1)
            }
        }
        
        for bucket in 0..<self.persistentResourceCapacity {
            if self.persistentKeys[bucket] != R(handle: Resource.invalidResource.handle) {
                iterator(self.persistentKeys[bucket], self.persistentValues[bucket], true)
                self.persistentKeys[bucket] = R(handle: Resource.invalidResource.handle)
                self.persistentValues.advanced(by: bucket).deinitialize(count: 1)
            }
        }
    }
    
    @inlinable
    public func forEach(_ body: ((R, V)) throws -> Void) rethrows {
        for bucket in 0..<self.transientResourceCapacity {
            if self.transientKeys[bucket] != R(handle: Resource.invalidResource.handle) {
                try body((self.transientKeys[bucket], self.transientValues[bucket]))
            }
        }
        
        for bucket in 0..<self.persistentResourceCapacity {
            if self.persistentKeys[bucket] != R(handle: Resource.invalidResource.handle) {
                try body((self.persistentKeys[bucket], self.persistentValues[bucket]))
            }
        }
    }
    
    @inlinable
    public mutating func forEachMutating(_ body: (R, inout V, _ deleteEntry: inout Bool) throws -> Void) rethrows {
        for bucket in 0..<self.transientResourceCapacity where self.transientKeys[bucket] != R(handle: Resource.invalidResource.handle) {
            var deleteEntry = false
            try body(self.transientKeys[bucket], &self.transientValues[bucket], &deleteEntry)
            if deleteEntry {
                self.transientKeys[bucket] = R(handle: Resource.invalidResource.handle)
                self.transientValues.advanced(by: bucket).deinitialize(count: 1)
            }
        }
        
        for bucket in 0..<self.persistentResourceCapacity where self.persistentKeys[bucket] != R(handle: Resource.invalidResource.handle) {
            var deleteEntry = false
            try body(self.persistentKeys[bucket], &self.persistentValues[bucket], &deleteEntry)
            if deleteEntry {
                self.persistentKeys[bucket] = R(handle: Resource.invalidResource.handle)
                self.persistentValues.advanced(by: bucket).deinitialize(count: 1)
            }
        }
    }
    
    /// Passes back a pointer to the address where the value should go for a given key.
    /// The bool argument indicates whether the pointer is currently initialised.
    @inlinable
    public mutating func withValue<T>(forKey resource: R, perform: (UnsafeMutablePointer<V>, Bool) -> T) -> T {
        if resource._usesPersistentRegistry {
            return perform(self.persistentValues.advanced(by: resource.index), self.persistentKeys[resource.index] == resource)
        } else {
           return perform(self.transientValues.advanced(by: resource.index), self.transientKeys[resource.index] == resource)
        }
    }
}
