//
//  BitPacking.swift
//  Utilities
//
//  Created by Thomas Roughton on 16/03/18.
//

import Swift

extension UInt64 {
    public func bits(in range: Range<Int>) -> UInt64 {
        let rangeSize = UInt64(range.count)
        let maskBits = (1 << rangeSize) - 1
        
        return (self >> UInt64(range.lowerBound)) & maskBits
    }
    
    public mutating func setBits(in range: Range<Int>, to value: UInt64) {
        let rangeSize = UInt64(range.count)
        let maskBits = (1 << rangeSize) - 1
        var value = value
        value &= maskBits
        
        self &= ~(maskBits << range.lowerBound)
        self |= value << range.lowerBound
    }
}
