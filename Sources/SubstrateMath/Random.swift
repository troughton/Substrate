//
//  random.swift
//  org.SwiftGFX.SwiftMath
//
//  Created by Andrey Volodin on 29.09.16.
//
//

import RealModule

extension SIMD2 where Scalar : Real, Scalar: BinaryFloatingPoint, Scalar.RawSignificand: BinaryInteger & FixedWidthInteger {
    /**  
     Returns a random SIMD2<Scalar> with a length equal to 1.0.
     */
    @inlinable
    public var randomOnUnitCircle: SIMD2<Scalar> {
        let theta = Scalar.random(in: 0...(2 * Scalar.pi as Scalar))
        return SIMD2<Scalar>(Scalar.cos(theta), Scalar.sin(theta))
    }
    
    /**
     Returns a random SIMD2<Scalar> with a length less than 1.0.
    */
    @inlinable
    public var randomInUnitCircle: SIMD2<Scalar> {
        let theta : Scalar = Scalar.random(in: 0...(2 * Scalar.pi as Scalar))
        var r : Scalar = Scalar.random(in: 0...1)
        r.formSquareRoot()
        return SIMD2<Scalar>(r * Scalar.cos(theta), r * Scalar.sin(theta))
    }
}
