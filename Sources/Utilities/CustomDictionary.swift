// https://github.com/emilk/emilib/blob/master/emilib/hash_map.hpp


public protocol CustomHashable : Equatable {
    var customHashValue : Int { get }
}

extension ObjectIdentifier : CustomHashable {
    public var customHashValue : Int {
        return Int(bitPattern: self) >> 3
    }
}

/// A cache-friendly hash table with open addressing, linear probing and power-of-two capacity
/// HashMap is a struct to avoid retains/releases, but that means that any user must manually
/// call `deinit` once they're finished.
@_fixed_layout
public struct HashMap<K : CustomHashable, V> {
    
    public let allocator : AllocatorType
    
    public typealias Index = Int
    
    public typealias State = UInt8
    
    public private(set) var states : UnsafeMutablePointer<State>! = nil
    public private(set) var keys : UnsafeMutablePointer<K>! = nil
    public private(set) var values : UnsafeMutablePointer<V>! = nil
    
    public private(set) var bucketCount = 0
    public private(set) var filledCount = 0
    // Our longest bucket-brigade is this long. ONLY when we have zero elements is this ever negative (-1).
    public private(set) var maxProbeLength = -1
    // bucketCount minus one
    public private(set) var mask = 0
    
    public init(allocator: AllocatorType = .system) {
        self.allocator = allocator
    }
    
    public func `deinit`() {
        for bucket in 0..<self.bucketCount {
            if self.states[bucket] == .filled {
                self.keys.advanced(by: bucket).deinitialize(count: 1)
                self.values.advanced(by: bucket).deinitialize(count: 1)
            }
        }
        
        if self.bucketCount > 0 {
            Allocator.deallocate(self.states, allocator: self.allocator)
            Allocator.deallocate(self.keys, allocator: self.allocator)
            Allocator.deallocate(self.values, allocator: self.allocator)
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
    
    @inlinable
    public subscript(key: K) -> V? {
        get {
            let bucket = self.findFilledBucket(key: key)
            if bucket != -1 {
                return self.values[bucket]
            }
            return nil
        }
        set {
            if let value = newValue {
                self.insertOrAssign(key: key, value: value)
            } else {
                _ = self.removeValue(forKey: key)
            }
        }
    }
    
    @inlinable
    public subscript(guaranteedKey key: K) -> V {
        get {
            let bucket = self.findFilledBucket(key: key)
            return self.values[bucket]
        }
        set {
            self.insertOrAssign(key: key, value: newValue)
        }
    }
    
    @inlinable
    public subscript(key: K, default default: @autoclosure () -> V) -> V {
        get {
            let bucket = self.findFilledBucket(key: key)
            if bucket != -1 {
                return self.values[bucket]
            }
            return `default`()
        }
        set {
            self.insertOrAssign(key: key, value: newValue)
        }
    }
    
    /// Returns a pair consisting of an iterator to the inserted element
    /// (or to the element that prevented the insertion)
    /// and a bool denoting whether the insertion took place.
    @inlinable
    public mutating func insert(key: K, value: @autoclosure () -> V) -> (index: Index, inserted: Bool) {
        self.checkIfNeedsExpand()
        
        let bucket = self.findOrAllocate(key: key)
        
        if self.states[bucket] == .filled {
            return (bucket, inserted: false)
        } else {
            self.states[bucket] = .filled
            self.keys.advanced(by: bucket).initialize(to: key)
            self.values.advanced(by: bucket).initialize(to: value())
            self.filledCount += 1
            return (bucket, inserted: true)
        }
    }
    
    /// Same as above, but contains(key) MUST be false
    @inlinable
    public mutating func insertUnique(key: K, value: V) {
        assert(!self.contains(key: key))
        
        self.checkIfNeedsExpand()
        
        let bucket = self.findEmptyBucket(key: key)
        self.states[bucket] = .filled
        
        self.keys.advanced(by: bucket).initialize(to: key)
        self.values.advanced(by: bucket).initialize(to: value)
        self.filledCount += 1
    }
    
    /// bucket must be a valid, empty bucket that was previously allocated with e.g. findOrAllocate
    @inlinable
    public mutating func insertAtIndex(_ bucket: Index, key: K, value: V) {
        assert(!self.contains(key: key))
        
        self.states[bucket] = .filled
        
        self.keys.advanced(by: bucket).initialize(to: key)
        self.values.advanced(by: bucket).initialize(to: value)
        self.filledCount += 1
    }
    
    @inlinable
    public mutating func insertOrAssign(key: K, value: V) {
        self.checkIfNeedsExpand()
        
        let bucket = self.findOrAllocate(key: key)
        
        // Check if inserting a new value rather than overwriting an old entry
        if self.states[bucket] == .filled {
            self.values[bucket] = value
        } else {
            self.states[bucket] = .filled
            self.keys.advanced(by: bucket).initialize(to: key)
            self.values.advanced(by: bucket).initialize(to: value)
            self.filledCount += 1
        }
    }
    
    /// Returns the old value.
    @inlinable
    public mutating func replaceIfPresent(key: K, newValue: V) -> V? {
        self.checkIfNeedsExpand()
        
        let bucket = self.findOrAllocate(key: key)
        
        if self.states[bucket] == .filled {
            let oldValue = self.values[bucket]
            self.values[bucket] = newValue
            return oldValue
        } else {
            self.states[bucket] = .filled
            self.keys.advanced(by: bucket).initialize(to: key)
            self.values.advanced(by: bucket).initialize(to: newValue)
            self.filledCount += 1
            return nil
        }
    }
    
    @inlinable
    @discardableResult
    public mutating func removeValue(forKey key: K) -> V? {
        let bucket = self.findFilledBucket(key: key)
        return self.removeValue(at: bucket)
    }
    
    @inlinable
    public mutating func removeValue(at bucket: Index) -> V? {
        if bucket != -1 {
            self.states[bucket] = .active
            self.keys.advanced(by: bucket).deinitialize(count: 1)
            let oldValue = self.values.advanced(by: bucket).move()
            self.filledCount -= 1
            return oldValue
        } else {
            return nil
        }
    }
    
    @inlinable
    public mutating func removeAll() {
        for bucket in 0..<self.bucketCount {
            if self.states[bucket] == .filled {
                self.states[bucket] = .inactive
                self.keys.advanced(by: bucket).deinitialize(count: 1)
                self.values.advanced(by: bucket).deinitialize(count: 1)
            }
        }
        
        self.filledCount = 0
        self.maxProbeLength = -1
    }
    
    @inlinable
    public mutating func removeAll(iterating iterator: (K, V) -> Void) {
        for bucket in 0..<self.bucketCount {
            if self.states[bucket] == .filled {
                iterator(self.keys[bucket], self.values[bucket])
                self.states[bucket] = .inactive
                self.keys.advanced(by: bucket).deinitialize(count: 1)
                self.values.advanced(by: bucket).deinitialize(count: 1)
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
    public func forEach(_ body: ((K, V)) throws -> Void) rethrows {
        for bucket in 0..<bucketCount where self.states[bucket] == .filled {
            try body((self.keys[bucket], self.values[bucket]))
        }
    }
    
    @inlinable
    public mutating func forEachMutating(_ body: (K, inout V, _ deleteEntry: inout Bool) throws -> Void) rethrows {
        for bucket in 0..<bucketCount where self.states[bucket] == .filled {
            var deleteEntry = false
            try body(self.keys[bucket], &self.values[bucket], &deleteEntry)
            if deleteEntry {
                _ = self.removeValue(at: bucket)
            }
        }
    }
    
    /// Passes back a pointer to the address where the value should go for a given key.
    /// The bool argument indicates whether the pointer is currently initialised.
    @inlinable
    public mutating func withValue<T>(forKey key: K, perform: (UnsafeMutablePointer<V>, Bool) -> T) -> T {
        self.checkIfNeedsExpand()
        
        let bucket = self.findOrAllocate(key: key)
        return perform(self.values.advanced(by: bucket), self.states[bucket] == .filled)
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
        let newValues : UnsafeMutablePointer<V> = Allocator.allocate(capacity: bucketCount, allocator: self.allocator)
        
        let oldBucketCount = self.bucketCount
        let oldStates = self.states
        let oldKeys = self.keys
        let oldValues = self.values
        
        self.bucketCount = bucketCount
        self.mask = self.bucketCount - 1
        self.states = newStates
        self.keys = newKeys
        self.values = newValues
        
        self.maxProbeLength = -1
        
        for sourceBucket in 0..<oldBucketCount {
            if oldStates![sourceBucket] == .filled {
                let sourceKey = oldKeys!.advanced(by: sourceBucket).move()
                let destinationBucket = self.findEmptyBucket(key: sourceKey)
                
                assert(destinationBucket != -1)
                assert(self.states[destinationBucket] != .filled)
                self.states[destinationBucket] = .filled
                
                self.keys.advanced(by: destinationBucket).initialize(to: sourceKey)
                self.values.advanced(by: destinationBucket).moveInitialize(from: oldValues!.advanced(by: sourceBucket), count: 1)
            }
        }
        
        if oldBucketCount > 0 {
            Allocator.deallocate(oldStates!, allocator: self.allocator)
            Allocator.deallocate(oldKeys!, allocator: self.allocator)
            Allocator.deallocate(oldValues!, allocator: self.allocator)
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


extension HashMap : Sequence {
    
    public typealias Element = (K, V)
    
    @_fixed_layout
    public struct Iterator : IteratorProtocol {
        public typealias Element = (K, V)
        
        public let hashMap : HashMap<K, V>
        public var bucket = 0
        
        init(hashMap: HashMap<K, V>) {
          self.hashMap = hashMap
        }
        
        public mutating func next() -> (K, V)? {
            while self.bucket < hashMap.bucketCount {
                defer { self.bucket += 1 }
                
                if hashMap.states[bucket] == .filled {
                    return (hashMap.keys[bucket], hashMap.values[bucket])
                }
            }
            return nil
        }
    }
    
    public func makeIterator() -> HashMap<K, V>.Iterator {
        return Iterator(hashMap: self)
    }
}

extension HashMap {
    
    @_fixed_layout
    public struct ValuesIterator : IteratorProtocol {
        public typealias Element = V
        
        public let hashMap : HashMap<K, V>
        public var bucket = 0
        
        init(hashMap: HashMap<K, V>) {
            self.hashMap = hashMap
        }
        
        public mutating func next() -> V? {
            while self.bucket < hashMap.bucketCount {
                defer { self.bucket += 1 }
                
                if hashMap.states[bucket] == .filled {
                    return hashMap.values[bucket]
                }
            }
            return nil
        }
    }
    
    public struct ValuesSequence : Sequence {
        public let hashMap : HashMap<K, V>
        
        init(hashMap: HashMap<K, V>) {
            self.hashMap = hashMap
        }
        
        public func makeIterator() -> HashMap<K, V>.ValuesIterator {
            return ValuesIterator(hashMap: self.hashMap)
        }
    }
    
    public var valuesSequence : ValuesSequence {
        return ValuesSequence(hashMap: self)
    }
}

extension HashMap.State {
    /// Never been touched
    @inlinable
    public static var inactive : UInt8 { return 0 }
    /// Is inside a search-chain, but is empty
    @inlinable
    public static var active : UInt8 { return 1 }
    /// Is set with key/value
    @inlinable
    public static var filled : UInt8 { return 2 }
}
