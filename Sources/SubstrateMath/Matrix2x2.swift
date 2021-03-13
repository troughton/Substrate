// Copyright 2016 Stuart Carnie.
// License: https://github.com/SwiftGFX/SwiftMath#license-bsd-2-clause
//

import RealModule

/// A column-major 2x2 matrix.
@frozen
public struct Matrix2x2<Scalar: SIMDScalar & BinaryFloatingPoint> : Hashable {
    public var columns: SIMD4<Scalar> = .init(1, 0, 0, 1)
  
    @inlinable
    public init() {}
    
    /// Creates an instance using the vector to initialize the diagonal elements
    @inlinable
    public init(diagonal v: SIMD2<Scalar>) {
        self.columns = SIMD4(v.x, 0, 0, v.y)
    }
    
    /// Creates an instance with the specified columns
    ///
    /// - parameter c0: a vector representing column 0
    /// - parameter c1: a vector representing column 1
    /// - parameter c2: a vector representing column 2
    @inlinable
    public init(_ c0: SIMD2<Scalar>, _ c1: SIMD2<Scalar>) {
        self.columns = SIMD4(lowHalf: c0, highHalf: c1)
    }
    
    /// Creates a matrix with the elements in order c0.x, c0.y, c1.x, c1.y
    @inlinable
    public init(_ columns: SIMD4<Scalar>) {
        self.columns = columns
    }
    
    /// Access the `col`th column vector
    @inlinable
    public subscript(col: Int) -> SIMD2<Scalar> {
        get {
            switch col {
            case 0: return self.columns.xy
            case 1: return self.columns.zw
            default: preconditionFailure("Index out of bounds")
            }
        }
        
        set {
            switch col {
            case 0: self.columns.xy = newValue
            case 1: self.columns.zw = newValue
            default: preconditionFailure("Index out of bounds")
            }
        }
    }
    
    /// Access the `col`th column vector and then `row`th element
    @inlinable
    public subscript(row: Int, col: Int) -> Scalar {
        get {
            return self[col][row]
        }
        set {
            self[col][row] = newValue
        }
    }
    
    @inlinable
    public var transpose: Matrix2x2 {
        return Matrix2x2(self.columns[SIMD4(0, 2, 1, 3)])
    }
    
    @inlinable
    public static prefix func -(m: Matrix2x2) -> Matrix2x2 {
        return Matrix2x2(
            -m.columns
        )
    }
    
    @inlinable
    public static func *(lhs: Matrix2x2, rhs: Matrix2x2) -> Matrix2x2 {
        var result = lhs.columns * rhs.columns[SIMD4(0, 0, 3, 3)]
        result.addProduct(lhs.columns[SIMD4(2, 3, 0, 1)], rhs.columns[SIMD4(1, 1, 2, 2)])
        return Matrix2x2(result)
    }

    // 2x2 column major Matrix adjugate multiply (A#)*B
    @inlinable
    public static func mul_AAdj_B(_ lhs: Matrix2x2, _ rhs: Matrix2x2) -> Matrix2x2 {
        var result = lhs.columns[SIMD4(3, 0, 3, 0)] * rhs.columns
        result -= lhs.columns[SIMD4(2, 1, 2, 1)] * rhs.columns[SIMD4(1, 0, 3, 2)]
        return Matrix2x2(result)
    }
    
    // 2x2 column major Matrix adjugate multiply A*(B#)
    @inlinable
    public static func mul_A_BAdj(_ lhs: Matrix2x2, _ rhs: Matrix2x2) -> Matrix2x2 {
        var result = lhs.columns * rhs.columns[SIMD4(3, 3, 0, 0)]
        result -= lhs.columns[SIMD4(2, 3, 0, 1)] * rhs.columns[SIMD4(1, 1, 2, 2)]
        return Matrix2x2(result)
    }
    
    @inlinable
    public static func *(lhs: Matrix2x2, rhs: Scalar) -> Matrix2x2 {
        return Matrix2x2(
            lhs.columns * rhs
        )
    }
    
    @inlinable
    public static func *(lhs: Matrix2x2, rhs: SIMD2<Scalar>) -> SIMD2<Scalar> {
        var result = lhs.columns.xy * SIMD2(repeating: rhs.x)
        result.addProduct(lhs.columns.zw, SIMD2(repeating: rhs.y))
        return result
    }
    
    @inlinable
    public static func *(lhs: SIMD2<Scalar>, rhs: Matrix2x2) -> SIMD2<Scalar> {
        var result = rhs.columns[SIMD2(0, 2)] * SIMD2(repeating: lhs.x)
        result.addProduct(rhs.columns[SIMD2(1, 3)], SIMD2(repeating: lhs.y))
        return result
    }
    
}

extension Matrix2x2 {
    /// Returns the identity matrix
    @inlinable
    public static var identity : Matrix2x2 { return Matrix2x2(diagonal: SIMD2(repeating: 1.0)) }
    
    @inlinable
    public init(_ m: Matrix3x3<Scalar>) {
        self.init(m[0].xy, m[1].xy)
    }
    @inlinable
    public init(_ m: Matrix4x4<Scalar>) {
        self.init(m[0].xy, m[1].xy)
    }
    
    @inlinable
    public static func scale(sx: Scalar, sy: Scalar) -> Matrix2x2 {
        return Matrix2x2.scale(by: SIMD2<Scalar>(sx, sy))
    }
    
    @inlinable
    public static func scale(by s: SIMD2<Scalar>) -> Matrix2x2 {
        return Matrix2x2(diagonal: s)
    }
    
}

extension Matrix2x2 where Scalar: Real {
    /// Returns a transformation matrix that rotates clockwise around the z axis
    @inlinable
    public static func rotate(_ z: Angle<Scalar>) -> Matrix2x2 {
        let (sin: sz, cos: cz) = Angle<Scalar>.sincos(z)
        
        var r = Matrix2x2()
        r[0,0] = cz
        r[0,1] = sz
        r[1,0] = -sz
        r[1,1] = cz
        
        return r
    }
    
    // Reference: http://www.cs.cornell.edu/courses/cs4620/2014fa/lectures/polarnotes.pdf
    @inlinable
    public var polarDecomposition: (rotation: Angle<Scalar>, scale: Matrix2x2<Scalar>) {
        let theta = -Scalar.atan2(y: self[1, 0] - self[0, 1], x: self[0, 0] + self[1, 1])
        let R = Matrix2x2.rotate(Angle(radians: theta))
        
        let S = R.transpose * self
        
        return (Angle(radians: theta), S)
    }
}

extension Matrix2x2: CustomStringConvertible {
    
    /// Displays the matrix in column-major order
    public var description: String {
        return "Matrix2x2(\n\(self[0]), \(self[1]))\n)"
    }
}

extension Matrix2x2: Codable {
    @inlinable
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let c0 = try container.decode(SIMD2<Scalar>.self)
        let c1 = try container.decode(SIMD2<Scalar>.self)
        self.init(c0, c1)
    }
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.columns.xy)
        try container.encode(self.columns.zw)
    }
}

@inlinable
public func interpolate<Scalar>(from m1: Matrix2x2<Scalar>, to m2: Matrix2x2<Scalar>, factor t: Scalar) -> Matrix2x2<Scalar> {
    return Matrix2x2(
        m1.columns + (m2.columns - m1.columns) * t
    )
}

public typealias Matrix2x2f = Matrix2x2<Float>
