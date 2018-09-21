//
//  DependencyTable.swift
//  FrameGraph
//
//  Created by Thomas Roughton on 7/06/18.
//

import Utilities


public struct DependencyTable<T> {
    private var storage : [T]
    public let capacity : Int
    
    init(capacity: Int, defaultValue: T) {
        self.capacity = capacity
        
        // Using zero-based indices:
        // 0 can depend on nothing
        // 1 can depend on 0, index: 0
        // 2 can depend on 0 or 1, index: 1
        // 3 can depend on 0, 1, or 2, index: 3
        // 4 can depend on 0, 1, 2, or 3, index: 6
        self.storage = [T](repeating: defaultValue, count: (capacity * capacity + capacity) / 2)
    }
    
    private func baseIndexForDependenciesFor(row: Int) -> Int {
        let n = row - 1
        return (n * n + n) / 2
    }
    
    public mutating func setDependency(from: Int, on: Int, to: T) {
        let base = self.baseIndexForDependenciesFor(row: from)
        self.storage[base + on] = to
    }
    
    public func dependency(from: Int, on: Int) -> T {
        let base = self.baseIndexForDependenciesFor(row: from)
        return self.storage[base + on]
    }
}
