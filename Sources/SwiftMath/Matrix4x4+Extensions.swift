//
//  Matrix4x4+Extensions.swift
//  org.SwiftGFX.SwiftMath
//
//  Created by Andrey Volodin on 10.08.16.
//
//

extension Matrix4x4f {
    @inlinable
    public func translated(by v: Vector3f) -> Matrix4x4f {
        let col3 = self * vec4(v)
        return Matrix4x4f(
            self[0],
            self[1],
            self[2],
            col3
        )
    }
    
    @inlinable
    public func withTranslation(_ v: Vector3f) -> Matrix4x4f {
        let col3 = vec4(v, 1)
        return Matrix4x4f(
            self[0],
            self[1],
            self[2],
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
    ///     var r = self × vec4(v)
    ///     r *= 1.0/r.w
    ///     return vec3(r.x, r.y, r.z)
    ///     ```
    ///
    /// - returns: 
    /// A new vector created by first multiplying the matrix by the
    /// vector and then performing perspective division on the result vector.
    @inlinable
    public func multiplyAndProject(_ v: Vector3f) -> Vector3f {
        var r = self * Vector4f(v)
        r *= 1.0/r.w
        return Vector3f(r.x, r.y, r.z)
    }
}



extension AffineMatrix {
    @inlinable
    public func translated(by v: Vector3f) -> AffineMatrix {
        let col3 = self * vec4(v)
        
        var result = self
        result.r0.w = col3.x
        result.r1.w = col3.y
        result.r2.w = col3.z
        
        return result
    }
    
    @inlinable
    public func withTranslation(_ v: Vector3f) -> AffineMatrix {
        var result = self
        result.r0.w = v.x
        result.r1.w = v.y
        result.r2.w = v.z
        
        return result
    }
}
