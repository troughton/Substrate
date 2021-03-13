//
//  Matrix4x4+Extensions.swift
//  org.SwiftGFX.SwiftMath
//
//  Created by Andrey Volodin on 10.08.16.
//
//

extension Matrix4x4 {
    @inlinable
    public func translated(by v: SIMD3<Scalar>) -> Matrix4x4 {
        let col3 : SIMD4<Scalar> = self * SIMD4<Scalar>(v, 1)
        return Matrix4x4(
            self.c0,
            self.c1,
            self.c2,
            col3
        )
    }
    
    @inlinable
    public func withTranslation(_ v: SIMD3<Scalar>) -> Matrix4x4 {
        let col3 = SIMD4<Scalar>(v, 1)
        return Matrix4x4(
            self.c0,
            self.c1,
            self.c2,
            col3
        )
    }
    
    /// Multiplies a 4×4 matrix by a position vector to create a vector in
    /// homogenous coordinates, then projects the result to a 3-component vector.
    ///
    /// - parameter v: the position vector
    ///
    /// - remark:
    ///
    ///     ```
    ///     var r = self × SIMD4<Scalar>(v)
    ///     r *= 1.0/r.w
    ///     return SIMD3<Scalar>(r.x, r.y, r.z)
    ///     ```
    ///
    /// - returns: 
    /// A new vector created by first multiplying the matrix by the
    /// vector and then performing perspective division on the result vector.
    @inlinable
    public func multiplyAndProject(_ v: SIMD3<Scalar>) -> SIMD3<Scalar> {
        var r : SIMD4<Scalar> = self * SIMD4<Scalar>(v, 1)
        r *= SIMD4(repeating: 1.0 / r.w)
        return SIMD3<Scalar>(r.x, r.y, r.z)
    }
}

extension AffineMatrix {
    @inlinable
    public func translated(by v: SIMD3<Scalar>) -> AffineMatrix {
        let col3 = self * SIMD4<Scalar>(v, 1)
        
        var result = self
        result.r0.w = col3.x
        result.r1.w = col3.y
        result.r2.w = col3.z
        
        return result
    }
    
    @inlinable
    public func withTranslation(_ v: SIMD3<Scalar>) -> AffineMatrix {
        var result = self
        result.r0.w = v.x
        result.r1.w = v.y
        result.r2.w = v.z
        
        return result
    }
}
