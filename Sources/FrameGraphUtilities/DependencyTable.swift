//
//  DependencyTable.swift
//  FrameGraph
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
        
        self.storage.removeAll(keepingCapacity: true)
        self.storage.append(contentsOf: repeatElement(value, count: (capacity * capacity + capacity) / 2))
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
    public func transitiveReduction(hasDependency: (T) -> Bool) -> DependencyTable<Bool> {
        // Floyd-Warshall algorithm for finding the shortest path.
        // https://en.wikipedia.org/wiki/Floyd–Warshall_algorithm{
        var reductionMatrix = DependencyTable<Bool>(capacity: self.capacity, defaultValue: false)
        for sourceIndex in 0..<self.capacity {
            for dependentIndex in min(sourceIndex + 1, self.capacity)..<self.capacity {
                if hasDependency(self.dependency(from: dependentIndex, on: sourceIndex)) {
                    reductionMatrix.setDependency(from: dependentIndex, on: sourceIndex, to: true) // true
                }
            }
        }
        
        for k in 0..<self.capacity {
            for i in min(k + 1, self.capacity)..<self.capacity {
                for j in min(i + 1, self.capacity)..<self.capacity {
                    let candidatePath = reductionMatrix.dependency(from: i, on: k) && reductionMatrix.dependency(from: j, on: i)
                    reductionMatrix.setDependency(from: j, on: k, to: reductionMatrix.dependency(from: j, on: k) || candidatePath)
                }
            }
        }
        
        // Transitive reduction:
        // https://stackoverflow.com/questions/1690953/transitive-reduction-algorithm-pseudocode
        for i in 0..<self.capacity {
            for j in 0..<i {
                if reductionMatrix.dependency(from: i, on: j) {
                    for k in 0..<j {
                        if reductionMatrix.dependency(from: j, on: k) {
                            reductionMatrix.setDependency(from: i, on: k, to: false)
                        }
                    }
                }
            }
        }
        
        return reductionMatrix
    }
}
