//
//  Matrix3x3fx3+nosimd.swift
//  SwiftMath
//
//  Created by Andrey Volodin on 16.12.16.
//
//

#if NOSIMD
public struct Matrix3x3f {
    public var m11: Float = 0.0
    public var m12: Float = 0.0
    public var m13: Float = 0.0
    
    private let m14 : Float = 0.00
    
    public var m21: Float = 0.0
    public var m22: Float = 0.0
    public var m23: Float = 0.0
    
    private let m24 : Float = 0.00
    
    public var m31: Float = 0.0
    public var m32: Float = 0.0
    public var m33: Float = 0.0
    
    private let m34 : Float = 0.00
    
    public func toArray() -> [Float] {
        return [m11, m12, m13, m21, m22, m23, m31, m32, m33]
    }
  
    public init() {}
    
    /// Creates an instance using the vector to initialize the diagonal elements
    public init(diagonal v: Vector3f) {
        m11 = v[0]
        m22 = v[1]
        m33 = v[2]
    }
    
    /// Creates an instance with the specified columns
    ///
    /// - parameter c0: a vector representing column 0
    /// - parameter c1: a vector representing column 1
    /// - parameter c2: a vector representing column 2
    public init(_ c0: Vector3f, _ c1: Vector3f, _ c2: Vector3f) {
        m11 = c0[0]
        m12 = c0[1]
        m13 = c0[2]
        
        m21 = c1[0]
        m22 = c1[1]
        m23 = c1[2]
        
        m31 = c2[0]
        m32 = c2[1]
        m33 = c2[2]
    }
    
    /// Access the `col`th column vector
    public subscript(col: Int) -> Vector3f {
        get {
            switch col {
            case 0: return Vector3f(m11, m12, m13)
            case 1: return Vector3f(m21, m22, m23)
            case 2: return Vector3f(m31, m32, m33)
            default: fatalError("Index outside of bounds")
            }
        }
        
        set {
            switch col {
            case 0: m11 = newValue[0]; m12 = newValue[1]; m13 = newValue[2];
            case 1: m21 = newValue[0]; m22 = newValue[1]; m23 = newValue[2];
            case 2: m31 = newValue[0]; m32 = newValue[1]; m33 = newValue[2];
            default: fatalError("Index outside of bounds")
            }
        }
    }
    
    /// Access the `col`th column vector and then `row`th element
    public subscript(col: Int, row: Int) -> Float {
        get {
            switch col {
            case 0:
                switch row {
                case 0: return m11
                case 1: return m12
                case 2: return m13
                default: fatalError("Index outside of bounds")
                }
            case 1:
                switch row {
                case 0: return m21
                case 1: return m22
                case 2: return m23
                default: fatalError("Index outside of bounds")
                }
            case 2:
                switch row {
                case 0: return m31
                case 1: return m32
                case 2: return m33
                default: fatalError("Index outside of bounds")
                }
            default: fatalError("Index outside of bounds")
            }
        }
        
        set {
            switch col {
            case 0:
                switch row {
                case 0: m11 = newValue
                case 1: m12 = newValue
                case 2: m13 = newValue
                default: fatalError("Index outside of bounds")
                }
            case 1:
                switch row {
                case 0: m21 = newValue
                case 1: m22 = newValue
                case 2: m23 = newValue
                default: fatalError("Index outside of bounds")
                }
            case 2:
                switch row {
                case 0: m31 = newValue
                case 1: m32 = newValue
                case 2: m33 = newValue
                default: fatalError("Index outside of bounds")
                }
            default: fatalError("Index outside of bounds")
            }
        }
    }
    
    public var adjugate: Matrix3x3f {
        return Matrix3x3f(
            m22 * m33 - m23 * m32,
            m13 * m32 - m12 * m33,
            m12 * m23 - m13 * m22,
            m23 * m31 - m21 * m33,
            m11 * m33 - m13 * m31,
            m13 * m21 - m11 * m23,
            m21 * m32 - m22 * m31,
            m12 * m31 - m11 * m32,
            m11 * m22 - m12 * m21
        )
    }
    
    public var determinant: Float {
        return (m11 * m22 * m33 + m12 * m23 * m31 + m13 * m21 * m32)
            - (m13 * m22 * m31 + m11 * m23 * m32 + m12 * m21 * m33)
    }
    
    public var transpose: Matrix3x3f {
        return Matrix3x3f(m11, m21, m31, m12, m22, m32, m13, m23, m33)
    }
    
    public var inverse: Matrix3x3f {
        return adjugate * (1 / determinant)
    }
    
    public static prefix func -(m: Matrix3x3f) -> Matrix3x3f {
        return Matrix3x3f(
            -m.m11, -m.m12, -m.m13,
            -m.m21, -m.m22, -m.m23,
            -m.m31, -m.m32, -m.m33
        )
    }
    
    public static func *(lhs: Matrix3x3f, rhs: Matrix3x3f) -> Matrix3x3f {
        return Matrix3x3f(
            lhs.m11 * rhs.m11 + lhs.m21 * rhs.m12 + lhs.m31 * rhs.m13,
            lhs.m12 * rhs.m11 + lhs.m22 * rhs.m12 + lhs.m32 * rhs.m13,
            lhs.m13 * rhs.m11 + lhs.m23 * rhs.m12 + lhs.m33 * rhs.m13,
            lhs.m11 * rhs.m21 + lhs.m21 * rhs.m22 + lhs.m31 * rhs.m23,
            lhs.m12 * rhs.m21 + lhs.m22 * rhs.m22 + lhs.m32 * rhs.m23,
            lhs.m13 * rhs.m21 + lhs.m23 * rhs.m22 + lhs.m33 * rhs.m23,
            lhs.m11 * rhs.m31 + lhs.m21 * rhs.m32 + lhs.m31 * rhs.m33,
            lhs.m12 * rhs.m31 + lhs.m22 * rhs.m32 + lhs.m32 * rhs.m33,
            lhs.m13 * rhs.m31 + lhs.m23 * rhs.m32 + lhs.m33 * rhs.m33
        )
    }
    
    public static func *(lhs: Matrix3x3f, rhs: Float) -> Matrix3x3f {
        return Matrix3x3f(
            lhs.m11 * rhs, lhs.m12 * rhs, lhs.m13 * rhs,
            lhs.m21 * rhs, lhs.m22 * rhs, lhs.m23 * rhs,
            lhs.m31 * rhs, lhs.m32 * rhs, lhs.m33 * rhs
        )
    }
    
}
    
extension Matrix3x3f: Equatable {
    public static func ==(lhs: Matrix3x3f, rhs: Matrix3x3f) -> Bool {
        if lhs.m11 != rhs.m11 { return false }
        if lhs.m12 != rhs.m12 { return false }
        if lhs.m13 != rhs.m13 { return false }
        if lhs.m21 != rhs.m21 { return false }
        if lhs.m22 != rhs.m22 { return false }
        if lhs.m23 != rhs.m23 { return false }
        if lhs.m31 != rhs.m31 { return false }
        if lhs.m32 != rhs.m32 { return false }
        if lhs.m33 != rhs.m33 { return false }
        return true
    }
}
#endif

extension Matrix3x3f {
    /// Returns the identity matrix
    public static let identity = Matrix3x3f(diagonal: vec3(1.0))
    
    /// Creates a new instance from the values provided in column-major order
    public init(
        _ m00: Float, _ m01: Float, _ m02: Float,
        _ m10: Float, _ m11: Float, _ m12: Float,
        _ m20: Float, _ m21: Float, _ m22: Float) {
        self.init(
            vec3(m00, m01, m02),
            vec3(m10, m11, m12),
            vec3(m20, m21, m22)
        )
    }
    
    public init(_ array: [Float]) {
        self.init()
        for (i, val) in array.enumerated() {
            self[i / 3][i % 3] = val
        }
    }
    
}
