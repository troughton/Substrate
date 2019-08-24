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
}
