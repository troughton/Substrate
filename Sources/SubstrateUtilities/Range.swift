//
//  Range.swift
//  
//
//  Created by Thomas Roughton on 18/02/23.
//


extension Range where Bound: AdditiveArithmetic {
    @inlinable
    public init(start: Bound, count: Bound) {
        self = start..<(start + count)
    }
    
    @inlinable
    public func offset(by: Bound) -> Self {
        return (self.lowerBound + by)..<(self.upperBound + by)
    }
}

extension Range {
    @inlinable
    public func contains(_ other: Range) -> Bool {
        return other.lowerBound >= self.lowerBound && other.upperBound <= self.upperBound
    }
}
