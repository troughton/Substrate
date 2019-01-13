//
//  random.swift
//  org.SwiftGFX.SwiftMath
//
//  Created by Andrey Volodin on 29.09.16.
//
//

// @note copied from SwiftRandom which is MIT Licensed

#if (os(OSX) || os(iOS) || os(tvOS) || os(watchOS))
import Darwin
#elseif os(Linux)
import Foundation

internal func arc4random() -> UInt32 {
    return UInt32(random())
}
    
internal func arc4random_uniform(_ val: UInt32) -> UInt32 {
    return UInt32(random()) % val
}

#elseif os(Windows)

import Foundation

let timeSeed : Bool = {
    srand(UInt32(time(nil)))
    return true
}()

internal func arc4random() -> UInt32 {
    let _ = timeSeed
    return UInt32(rand())
}
    
internal func arc4random_uniform(_ val: UInt32) -> UInt32 {
    let _ = timeSeed
    return UInt32(rand()) % val
}

#endif

extension Vector2f {
    /**  
     Returns a random Vector2f with a length equal to 1.0.
     */
    public var randomOnUnitCircle: Vector2f {
        while true {
            let p = p2d(Float.random(in: -1...1), Float.random(in: -1...1))
            let lsq = p.lengthSquared
            if 0.1 < lsq && lsq < 1.0 {
                return p * Float(1.0 / sqrtf(lsq))
            }
        }
    }
    
    /**
     Returns a random Vector2f with a length less than 1.0.
    */
    public var randomInUnitCircle: Vector2f {
        while true {
            let p = p2d(Float.random(in: -1...1), Float.random(in: -1...1))
            let lsq = p.lengthSquared
            if lsq < 1.0 { return p }
        }
    }
}
