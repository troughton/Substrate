//
//  RoundInteger.swift
//  Utilities
//
//  Created by Thomas Roughton on 29/06/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

import Foundation

public extension BinaryInteger {
    
    /* multiple must be a power of two. http://stackoverflow.com/questions/3407012/c-rounding-up-to-the-nearest-multiple-of-a-number */
    @inlinable
    public func roundedUpToPowerOfTwoMultiple(of multiple: Self) -> Self {
        assert(multiple > 0 && ((multiple & (multiple - 1)) == 0))
        
        let notTerm = ~(multiple - 1)
        return (self + multiple - 1) & notTerm
    }
    
    @inlinable
    public func roundedUpToMultiple(of multiple: Self) -> Self {
        if multiple == 0 {
            return self
        }
        
        let remainder = self % multiple
        if remainder == 0 {
            return self
        }
        
        return self + multiple - remainder
    }
    
}
