//
//  DependencyTable.swift
//  RenderGraph
//
//  Created by Thomas Roughton on 7/06/18.
//

public struct DependencyTable<T> {
    @usableFromInline var storage : [T]
    public /* internal(set) */ var capacity : Int
    
    @inlinable
    public init(capacity: Int, defaultValue: T) {
        self.capacity = capacity
        
        // Using zero-based indices:
        // 0 can depend on nothing
        // 1 can depend on 0, index: 0
        // 2 can depend on 0 or 1, index: 1
        // 3 can depend on 0, 1, or 2, index: 3
        // 4 can depend on 0, 1, 2, or 3, index: 6
        self.storage = [T](repeating: defaultValue, count: (capacity * capacity + capacity) / 2)
    }
    
    @inlinable
    public mutating func resizeAndClear(capacity: Int, clearValue value: T) {
        self.capacity = capacity
        
        let elementCount = (capacity * capacity + capacity) / 2
        if self.storage.count > elementCount {
            self.storage.removeSubrange(elementCount..<self.storage.count)
        }
        
        for i in 0..<self.storage.count {
            self.storage[i] = value
        }
        
        if elementCount > self.storage.count {
            self.storage.append(contentsOf: repeatElement(value, count: elementCount - self.storage.count))
        }
    }
    
    @inlinable
    func baseIndexForDependenciesFor(row: Int) -> Int {
        let n = row - 1
        return (n * n + n) / 2
    }
    
    @inlinable
    public mutating func setDependency(from: Int, on: Int, to: T) {
        assert(on < from, "Indices can only depend on earlier indices.")
        
        let base = self.baseIndexForDependenciesFor(row: from)
        self.storage[base + on] = to
    }
    
    @inlinable
    public func dependency(from: Int, on: Int) -> T {
        assert(on < from, "Indices can only depend on earlier indices.")
        let base = self.baseIndexForDependenciesFor(row: from)
        return self.storage[base + on]
    }
    

    @inlinable
    public func transitiveReduction(hasDependency: (T) -> Bool) -> DependencyBitset {
        // Floyd-Warshall algorithm for finding the shortest path.
        // https://en.wikipedia.org/wiki/Floyd–Warshall_algorithm
        
        var reductionMatrix = DependencyBitset(table: self, hasDependency: hasDependency)
        
        reductionMatrix.formTransitiveReduction()
        return reductionMatrix
    }
}

extension DependencyTable where T == Bool {
    @inlinable
    public mutating func formTransitiveReduction()  {
        // Floyd-Warshall algorithm for finding the shortest path.
        // https://en.wikipedia.org/wiki/Floyd–Warshall_algorithm
        for k in 0..<self.capacity {
            for i in min(k + 1, self.capacity)..<self.capacity {
                if self.dependency(from: i, on: k) {
                    for j in min(i + 1, self.capacity)..<self.capacity {
                        self.setDependency(from: j, on: k, to: self.dependency(from: j, on: k) || self.dependency(from: j, on: i))
                    }
                }
            }
        }
        
        // Transitive reduction:
        // https://stackoverflow.com/questions/1690953/transitive-reduction-algorithm-pseudocode
        for i in 0..<self.capacity {
            for j in 0..<i {
                if self.dependency(from: i, on: j) {
                    for k in 0..<j {
                        self.setDependency(from: i, on: k, to: !self.dependency(from: j, on: k) && self.dependency(from: i, on: k))
                    }
                }
            }
        }
    }
}

extension DependencyTable: Equatable where T: Equatable {}
extension DependencyTable: Sendable where T: Sendable {}

public struct DependencyBitset {
    @usableFromInline var storage : [UInt]
    public /* internal(set) */ var capacity : Int
    
    @inlinable static var bitsPerElement : Int {
        return UInt.bitWidth
    }
    
    @inlinable
    public init(capacity: Int) {
        self.capacity = capacity
        
        // Using zero-based indices:
        // 0 can depend on nothing
        // 1 can depend on 0, index: 0
        // 2 can depend on 0 or 1, index: 1
        // 3 can depend on 0, 1, or 2, index: 3
        // 4 can depend on 0, 1, 2, or 3, index: 6
        
        // Note: each dependency "row" starts at the 0th bit of a UInt, rather than being tightly packed.
        // This layout makes transitive reduction more efficient.
        
        let storageCount = DependencyBitset.uintIndexForDependenciesFor(row: capacity)
        self.storage = [UInt](repeating: 0, count: storageCount)
    }
    
    @inlinable
    public init<T>(table: DependencyTable<T>, hasDependency: (T) -> Bool) {
        self.init(capacity: table.capacity)
        for i in 0..<self.capacity {
            for j in 0..<i {
                self.setDependency(from: i, on: j, to: hasDependency(table.dependency(from: i, on: j)))
            }
        }
        
        for i in 0..<self.capacity {
            for j in 0..<i {
                assert(self.dependency(from: i, on: j) == hasDependency(table.dependency(from: i, on: j)))
            }
        }
    }
    
    @inlinable
    static func uintIndexForDependenciesFor(row: Int) -> Int {
        var dependencyCount = row
        
        var total = 0
        while dependencyCount > 0 {
            total += row * ((dependencyCount + bitsPerElement - 1) / bitsPerElement)
            dependencyCount /= bitsPerElement
        }
        
        return total
    }
    
    @inlinable
    public subscript(bitIndex: Int) -> Bool {
        get {
            let (uintIndex, offset) = bitIndex.quotientAndRemainder(dividingBy: DependencyBitset.bitsPerElement)
            return self.storage[uintIndex][bit: offset]
        }
        set {
            let (uintIndex, offset) = bitIndex.quotientAndRemainder(dividingBy: DependencyBitset.bitsPerElement)
            self.storage[uintIndex][bit: offset] = newValue
        }
    }
    
    @inlinable
    public mutating func setDependency(from: Int, on: Int, to: Bool) {
        assert(on < from, "Indices can only depend on earlier indices.")
        
        let base = DependencyBitset.uintIndexForDependenciesFor(row: from) * DependencyBitset.bitsPerElement
        self[base  + on] = to
    }
    
    @inlinable
    public func dependency(from: Int, on: Int) -> Bool {
        assert(on < from, "Indices can only depend on earlier indices.")
        let base = DependencyBitset.uintIndexForDependenciesFor(row: from) * DependencyBitset.bitsPerElement
        return self[base + on]
    }
    
    public mutating func formTransitiveReduction() {
        // Floyd-Warshall algorithm for finding the shortest path.
        // https://en.wikipedia.org/wiki/Floyd–Warshall_algorithm
        for i in 0..<self.capacity {
            let iBase = DependencyBitset.uintIndexForDependenciesFor(row: i)
            for j in 0..<i {
                let jBase = DependencyBitset.uintIndexForDependenciesFor(row: j)
                if self.dependency(from: i, on: j) {
                    let uintCount = (j + DependencyBitset.bitsPerElement - 1) / DependencyBitset.bitsPerElement
                    for k in 0..<uintCount {
                        self.storage[iBase + k] |= self.storage[jBase + k]
                    }
                }
            }
        }
        
        // Transitive reduction:
        // https://stackoverflow.com/questions/1690953/transitive-reduction-algorithm-pseudocode
        for i in 0..<self.capacity {
            let iBase = DependencyBitset.uintIndexForDependenciesFor(row: i)
            for j in 0..<i {
                let jBase = DependencyBitset.uintIndexForDependenciesFor(row: j)
                if self.dependency(from: i, on: j) {
                    let uintCount = (j + DependencyBitset.bitsPerElement - 1) / DependencyBitset.bitsPerElement
                    for k in 0..<uintCount {
                        self.storage[iBase + k] &= ~self.storage[jBase + k]
                    }
                }
            }
        }
    }
    
    
    public func transitiveReduction() -> DependencyBitset {
        var copy = self
        copy.formTransitiveReduction()
        return copy
    }
}
