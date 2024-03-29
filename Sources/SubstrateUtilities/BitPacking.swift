//
//  BitPacking.swift
//  Utilities
//
//  Created by Thomas Roughton on 16/03/18.
//

import Swift

extension UInt64 {
    @inlinable @inline(__always)
    public func bits(in range: Range<Int>) -> UInt64 {
        let rangeSize = UInt64(truncatingIfNeeded: range.count)
        let maskBits = rangeSize == self.bitWidth ? UInt64.max : (1 << rangeSize) &- 1 as UInt64
        
        return (self >> UInt64(truncatingIfNeeded: range.lowerBound)) & maskBits
    }
    
    @inlinable @inline(__always)
    public mutating func setBits(in range: Range<Int>, to value: UInt64) {
        let rangeSize = UInt64(truncatingIfNeeded: range.count)
        let maskBits = (1 << rangeSize) &- 1 as UInt64
        var value = value
        value &= maskBits
        
        self &= ~(maskBits << range.lowerBound)
        self |= value << range.lowerBound
    }
    
    @inlinable @inline(__always)
    public mutating func setBits(in range: Range<UInt64>, to value: UInt64) {
        let rangeSize = UInt64(truncatingIfNeeded: range.count)
        let maskBits = (1 << rangeSize) &- 1 as UInt64
        var value = value
        value &= maskBits
        
        self &= ~(maskBits << range.lowerBound)
        self |= value << range.lowerBound
    }
    
    @inlinable @inline(__always)
    public static func maskForClearingBits(in range: Range<Int>) -> UInt64 {
        if range.count == self.bitWidth {
            return 0 // zero out all bits
        }
        
        let rangeSize = UInt64(truncatingIfNeeded: range.count)
        let maskBits = (1 << rangeSize) &- 1 as UInt64
        return ~(maskBits << range.lowerBound)
    }
    
    /// Assumes that value is within the valid range.
    @inlinable @inline(__always)
    public mutating func setBits(in range: Range<Int>, to value: UInt64, clearMask: UInt64) {
        self &= clearMask
        self |= value << range.lowerBound
    }
}
