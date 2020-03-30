//
//  HashSet.swift
//  
//
//  Created by Thomas Roughton on 30/03/20.
//

/// A cache-friendly hash table with open addressing, linear probing and power-of-two capacity
/// HashMap is a struct to avoid retains/releases, but that means that any user must manually
/// call `deinit` once they're finished.
/// Based off https://github.com/emilk/emilib/blob/master/emilib/hash_map.hpp
public struct HashSet<K : CustomHashable> {
    
    public let allocator : AllocatorType
    
    public typealias Index = Int
    
    public typealias State = UInt8
    
    @usableFromInline var states : UnsafeMutablePointer<State>! = nil
    @usableFromInline var keys : UnsafeMutablePointer<K>! = nil
    
    @usableFromInline var bucketCount = 0
    @usableFromInline var filledCount = 0
    // Our longest bucket-brigade is this long. ONLY when we have zero elements is this ever negative (-1).
    @usableFromInline var maxProbeLength = -1
    // bucketCount minus one
    @usableFromInline var mask = 0
    
    public init(allocator: AllocatorType = .system) {
        self.allocator = allocator
    }
    
    public func `deinit`() {
        for bucket in 0..<self.bucketCount {
            if self.states[bucket] == .filled {
                self.keys.advanced(by: bucket).deinitialize(count: 1)
            }
        }
        
        if self.bucketCount > 0 {
            Allocator.deallocate(self.states, allocator: self.allocator)
            Allocator.deallocate(self.keys, allocator: self.allocator)
        }
    }
    
    @inlinable
    public var count : Int {
        return self.filledCount
    }
    
    @inlinable
    public var isEmpty : Bool {
        return self.filledCount == 0
    }
    
    /// Returns average number of elements per bucket.
    @inlinable
    public var loadFactor : Float {
        return Float(self.filledCount) / Float(self.bucketCount)
    }
    
    // ------------------------------------------------------------
    
    @inlinable
    public func find(key: K) -> Index? {
        let bucket = self.findFilledBucket(key: key)
        if bucket == -1 {
            return nil
        }
        return bucket
    }
    
    @inlinable
    public func contains(key: K) -> Bool {
        return self.findFilledBucket(key: key) != -1
    }
    
    /// Returns a pair consisting of an iterator to the inserted element
    /// (or to the element that prevented the insertion)
    /// and a bool denoting whether the insertion took place.
    @inlinable
    @discardableResult
    public mutating func insert(key: K) -> (index: Index, inserted: Bool) {
        self.checkIfNeedsExpand()
        
        let bucket = self.findOrAllocate(key: key)
        
        if self.states[bucket] == .filled {
            return (bucket, inserted: false)
        } else {
            self.states[bucket] = .filled
            self.keys.advanced(by: bucket).initialize(to: key)
            self.filledCount += 1
            return (bucket, inserted: true)
        }
    }
    
    /// Same as above, but contains(key) MUST be false
    @inlinable
    public mutating func insertUnique(key: K) {
        assert(!self.contains(key: key))
        
        self.checkIfNeedsExpand()
        
        let bucket = self.findEmptyBucket(key: key)
        self.states[bucket] = .filled
        
        self.keys.advanced(by: bucket).initialize(to: key)
        self.filledCount += 1
    }
    
    /// bucket must be a valid, empty bucket that was previously allocated with e.g. findOrAllocate
    @inlinable
    public mutating func insertAtIndex(_ bucket: Index, key: K) {
        assert(!self.contains(key: key))
        
        self.states[bucket] = .filled
        
        self.keys.advanced(by: bucket).initialize(to: key)
        self.filledCount += 1
    }
    
    @inlinable
    @discardableResult
    public mutating func remove(key: K) -> Bool {
        let bucket = self.findFilledBucket(key: key)
        return self.remove(at: bucket)
    }
    
    @inlinable
    @discardableResult
    public mutating func remove(at bucket: Index) -> Bool {
        if bucket != -1 {
            self.states[bucket] = .active
            self.keys.advanced(by: bucket).deinitialize(count: 1)
            self.filledCount -= 1
            return true
        } else {
            return false
        }
    }
    
    @inlinable
    public mutating func removeAll() {
        for bucket in 0..<self.bucketCount {
            if self.states[bucket] == .filled {
                self.states[bucket] = .inactive
                self.keys.advanced(by: bucket).deinitialize(count: 1)
            }
        }
        
        self.filledCount = 0
        self.maxProbeLength = -1
    }
    
    @inlinable
    public mutating func removeAll(iterating iterator: (K) -> Void) {
        for bucket in 0..<self.bucketCount {
            if self.states[bucket] == .filled {
                iterator(self.keys[bucket])
                self.states[bucket] = .inactive
                self.keys.advanced(by: bucket).deinitialize(count: 1)
            }
        }
        
        self.filledCount = 0
        self.maxProbeLength = -1
    }
    
    @inlinable
    public mutating func removeAll(keepingCapacity: Bool) {
        assert(keepingCapacity)
        self.removeAll()
    }
    
    @inlinable
    public func forEach(_ body: ((K)) throws -> Void) rethrows {
        for bucket in 0..<bucketCount where self.states[bucket] == .filled {
            try body((self.keys[bucket]))
        }
    }
    
    @inlinable
    public mutating func forEachMutating(_ body: (K, _ deleteEntry: inout Bool) throws -> Void) rethrows {
        for bucket in 0..<bucketCount where self.states[bucket] == .filled {
            var deleteEntry = false
            try body(self.keys[bucket], &deleteEntry)
            if deleteEntry {
                _ = self.remove(at: bucket)
            }
        }
    }
    
    @usableFromInline
    mutating func _reserveCapacity(_ capacity: Int) {
        let requiredBucketCount = capacity + capacity/2 + 1
        
        var bucketCount = 4
        while bucketCount < requiredBucketCount {
            bucketCount <<= 1
        }
        
        let newStates : UnsafeMutablePointer<State> = Allocator.allocate(capacity: bucketCount, allocator: self.allocator)
        newStates.initialize(repeating: .inactive, count: bucketCount)
        
        let newKeys : UnsafeMutablePointer<K> = Allocator.allocate(capacity: bucketCount, allocator: self.allocator)
        
        let oldBucketCount = self.bucketCount
        let oldStates = self.states
        let oldKeys = self.keys
        
        self.bucketCount = bucketCount
        self.mask = self.bucketCount - 1
        self.states = newStates
        self.keys = newKeys
        
        self.maxProbeLength = -1
        
        for sourceBucket in 0..<oldBucketCount {
            if oldStates![sourceBucket] == .filled {
                let sourceKey = oldKeys!.advanced(by: sourceBucket).move()
                let destinationBucket = self.findEmptyBucket(key: sourceKey)
                
                assert(destinationBucket != -1)
                assert(self.states[destinationBucket] != .filled)
                self.states[destinationBucket] = .filled
                
                self.keys.advanced(by: destinationBucket).initialize(to: sourceKey)
            }
        }
        
        if oldBucketCount > 0 {
            Allocator.deallocate(oldStates!, allocator: self.allocator)
            Allocator.deallocate(oldKeys!, allocator: self.allocator)
        }
    }
    
    @inlinable
    public mutating func reserveCapacity(_ newCapacity: Int) {
        
        let requiredBuckets = newCapacity + newCapacity/2 + 1;
        if requiredBuckets <= self.bucketCount {
            return
        }
        
        self._reserveCapacity(newCapacity)
    }
    
    // Can we fit another element?
    @inlinable
    mutating func checkIfNeedsExpand() {
        self.reserveCapacity(self.filledCount + 1)
    }
    
    // Find the bucket with this key, or return -1
    @inlinable
    public func findFilledBucket(key: K) -> Int {
        if self.isEmpty { return -1 }
        
        let hashValue = key.customHashValue
        for offset in 0...self.maxProbeLength {
            let bucket = (hashValue &+ offset) & self.mask
            if self.states[bucket] == .filled {
                if self.keys[bucket] == key {
                    return bucket
                }
            } else if self.states[bucket] == .inactive {
                return -1 // End of the chain
            }
        }
        
        return -1
    }
    
    // Find the bucket with this key, or return a good empty bucket to place the key in.
    // In the latter case, the bucket is expected to be filled.
    @inlinable
    public mutating func findOrAllocate(key: K) -> Int {
        let hashValue = key.customHashValue
        
        var hole = -1
        var offset = 0
        while offset <= self.maxProbeLength {
            defer { offset += 1 }
            let bucket = (hashValue &+ offset) & self.mask
            
            if self.states[bucket] == .filled {
                if self.keys[bucket] == key {
                    return bucket
                }
            } else if self.states[bucket] == .inactive {
                return bucket
            } else {
                // ACTIVE: keep searching
                if hole == -1 {
                    hole = bucket
                }
            }
        }
        
        // No key found, but there may be a hole for it
        
        assert(offset == self.maxProbeLength + 1)
        
        if hole != -1 {
            return hole
        }
        
        // No hole found within _max_probe_length
        while true {
            defer { offset += 1 }
            let bucket = (hashValue &+ offset) & self.mask
            
            if self.states[bucket] != .filled {
                self.maxProbeLength = offset
                return bucket
            }
        }
    }
    
    // key is not in this map. Find a place to put it.
    @inlinable
    public mutating func findEmptyBucket(key: K) -> Int {
        let hashValue = key.customHashValue
        
        var offset = 0
        while true {
            let bucket = (hashValue &+ offset) & self.mask
            if self.states[bucket] != .filled {
                if offset > self.maxProbeLength {
                    self.maxProbeLength = offset
                }
                return bucket
            }
            offset += 1
        }
    }
}


extension HashSet : Sequence {
    
    public typealias Element = (K)
    
    public struct Iterator : IteratorProtocol {
        public typealias Element = (K)
        
        public let hashSet : HashSet<K>
        public var bucket = 0
        
        init(hashSet: HashSet<K>) {
            self.hashSet = hashSet
        }
        
        public mutating func next() -> K? {
            while self.bucket < hashSet.bucketCount {
                defer { self.bucket += 1 }
                
                if hashSet.states[bucket] == .filled {
                    return hashSet.keys[bucket]
                }
            }
            return nil
        }
    }
    
    public func makeIterator() -> HashSet<K>.Iterator {
        return Iterator(hashSet: self)
    }
}
