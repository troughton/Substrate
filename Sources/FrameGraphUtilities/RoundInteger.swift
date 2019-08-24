//
//  RoundInteger.swift
//  Utilities
//
//  Created by Thomas Roughton on 29/06/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

import Foundation

extension BinaryInteger {
    
    /* multiple must be a power of two. http://stackoverflow.com/questions/3407012/c-rounding-up-to-the-nearest-multiple-of-a-number */
    @inlinable
    public func roundedUpToMultipleOfPowerOfTwo(of multiple: Self) -> Self {
//        assert(multiple > 0 && ((multiple & (multiple - 1)) == 0))
        
        let notTerm : Self = ~(multiple - (1 as Self))
        var result = self + multiple
        result -= 1 as Self
        result &= notTerm
        return result
    }
    
    @inlinable
    public func roundedUpToMultiple(of multiple: Self) -> Self {
        if multiple == 0 {
            return self
        }
        
        let remainder : Self = self % multiple
        if remainder == 0 {
            return self
        }
        
        return self + multiple - remainder
    }
    
}
