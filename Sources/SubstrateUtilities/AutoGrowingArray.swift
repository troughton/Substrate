//
//  AutoGrowingArray.swift
//  
//
//  Created by Thomas Roughton on 20/06/22.
//

import Foundation

public struct AutoGrowingArray<Element>: Collection {
    public var contents: [Element?]
    
    @inlinable
    public init() {
        self.contents = []
    }
    
    @inlinable
    public init(contents: [Element?]) {
        self.contents = contents
    }
    
    @inlinable
    public init(repeating element: Element?, count: Int) {
        self.contents = .init(repeating: element, count: count)
    }
    
    @inlinable
    public init<S: Sequence>(_ sequence: S) where S.Element == Element {
        self.contents = sequence.map { .some($0) }
    }
    
    @inlinable
    public init<S: Sequence>(_ sequence: S) where S.Element == Element? {
        self.contents = .init(sequence)
    }
    
    @inlinable
    public var startIndex: Int {
        return self.contents.startIndex
    }
    
    @inlinable
    public var endIndex: Int {
        return self.contents.endIndex
    }
    
    @inlinable
    public func index(after i: Int) -> Int {
        return self.contents.index(after: i)
    }
    
    @inlinable
    public mutating func resize(_ minimumSize: Int) {
        if minimumSize > self.contents.count {
            self.contents.append(contentsOf: repeatElement(nil, count: minimumSize - self.contents.count))
        }
    }
    
    @inlinable
    public subscript(position: Int) -> Element? {
        get {
            if position >= self.contents.endIndex {
                return nil
            }
            return self.contents[position]
        }
        set {
            self.resize(position + 1)
            self.contents[position] = newValue
        }
    }
}
