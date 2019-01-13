// Copyright 2016 Stuart Carnie.
// License: https://github.com/SwiftGFX/SwiftMath#license-bsd-2-clause
//

#if !NOSIMD
import simd

/// Represents a standard 4x4 transformation matrix.
/// - remark:
/// Matrices are stored in column-major order
@_fixed_layout
public struct Matrix3x3f {
    public var d: float3x3 = float3x3()
    
    //MARK: - initializers
    
    /// Creates an instance initialized to zero
    @inlinable
    public init() {
    }
    
    /// Creates an instance using the vector to initialize the diagonal elements
    @inlinable
    public init(diagonal v: Vector3f) {
        self.init()
        self.d = float3x3(diagonal: v.d)
    }
    
    /// Creates an instance with the specified columns
    ///
    /// - parameter c0: a vector representing column 0
    /// - parameter c1: a vector representing column 1
    /// - parameter c2: a vector representing column 2
    public init(_ c0: Vector3f, _ c1: Vector3f, _ c2: Vector3f) {
        self.d = float3x3(columns: (c0.d, c1.d, c2.d))
    }
    
    //MARK:- properties
    
    @inlinable
    public var inverse: Matrix3x3f {
        return unsafeBitCast(d.inverse, to: Matrix3x3f.self)
    }
    
    @inlinable
    public var transpose: Matrix3x3f {
        return unsafeBitCast(d.transpose, to: Matrix3x3f.self)
    }
    
    //MARK:- operators
    
    @inlinable
    public static prefix func -(lhs: Matrix3x3f) -> Matrix3x3f {
        return unsafeBitCast(-lhs.d, to: Matrix3x3f.self)
    }
    
    @inlinable
    public static func *(lhs: Matrix3x3f, rhs: Float) -> Matrix3x3f {
        return unsafeBitCast(lhs.d * rhs, to: Matrix3x3f.self)
    }
    
    @inlinable
    public static func *(lhs: Matrix3x3f, rhs: Matrix3x3f) -> Matrix3x3f {
        return unsafeBitCast(lhs.d * rhs.d, to: Matrix3x3f.self)
    }
    
    // MARK: - subscript operations
    
    /// Access the `col`th column vector
    @inlinable
    public subscript(col: Int) -> Vector3f {
        get {
            return unsafeBitCast(d[col], to: Vector3f.self)
        }
        
        set {
            d[col] = newValue.d
        }
    }
    
    /// Access the `col`th column vector and then `row`th element
    @inlinable
    public subscript(col: Int, row: Int) -> Float {
        get {
            return d[col, row]
        }
        
        set {
            d[col, row] = newValue
        }
    }
}
    
#endif
