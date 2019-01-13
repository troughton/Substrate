//
//  Matrix4x4+nosimd.swift
//  SwiftMath
//
//  Created by Andrey Volodin on 06.10.16.
//
//

#if NOSIMD

@_fixed_layout
public struct Matrix4x4f : Equatable {
    @usableFromInline
    internal var m11: Float = 0.0
    @usableFromInline
    internal var m12: Float = 0.0
    @usableFromInline
    internal var m13: Float = 0.0
    @usableFromInline
    internal var m14: Float = 0.0
    @usableFromInline
    internal var m21: Float = 0.0
    @usableFromInline
    internal var m22: Float = 0.0
    @usableFromInline
    internal var m23: Float = 0.0
    @usableFromInline
    internal var m24: Float = 0.0
    @usableFromInline
    internal var m31: Float = 0.0
    @usableFromInline
    internal var m32: Float = 0.0
    @usableFromInline
    internal var m33: Float = 0.0
    @usableFromInline
    internal var m34: Float = 0.0
    @usableFromInline
    internal var m41: Float = 0.0
    @usableFromInline
    internal var m42: Float = 0.0
    @usableFromInline
    internal var m43: Float = 0.0
    @usableFromInline
    internal var m44: Float = 0.0
    
    public func toArray() -> [Float] {
        return [m11, m12, m13, m14, m21, m22, m23, m24, m31, m32, m33, m34, m41, m42, m43, m44]
    }
    
    public init() {}
    
    /// Creates an instance using the vector to initialize the diagonal elements
    public init(diagonal v: Vector4f) {
        m11 = v[0]
        m22 = v[1]
        m33 = v[2]
        m44 = v[3]
    }
    
    /// Creates an instance with the specified columns
    ///
    /// - parameter c0: a vector representing column 0
    /// - parameter c1: a vector representing column 1
    /// - parameter c2: a vector representing column 2
    /// - parameter c3: a vector representing column 3
    public init(_ c0: Vector4f, _ c1: Vector4f, _ c2: Vector4f, _ c3: Vector4f) {
        m11 = c0[0]
        m12 = c0[1]
        m13 = c0[2]
        m14 = c0[3]
        
        m21 = c1[0]
        m22 = c1[1]
        m23 = c1[2]
        m24 = c1[3]
        
        m31 = c2[0]
        m32 = c2[1]
        m33 = c2[2]
        m34 = c2[3]
        
        m41 = c3[0]
        m42 = c3[1]
        m43 = c3[2]
        m44 = c3[3]
    }
    
    /// Access the `col`th column vector
    @inlinable
    public subscript(col: Int) -> Vector4f {
        get {
            switch col {
            case 0: return Vector4f(m11, m12, m13, m14)
            case 1: return Vector4f(m21, m22, m23, m24)
            case 2: return Vector4f(m31, m32, m33, m34)
            case 3: return Vector4f(m41, m42, m43, m44)
            default: fatalError("Index outside of bounds")
            }
        }
        
        set {
            switch col {
            case 0: m11 = newValue[0]; m12 = newValue[1]; m13 = newValue[2]; m14 = newValue[3];
            case 1: m21 = newValue[0]; m22 = newValue[1]; m23 = newValue[2]; m24 = newValue[3];
            case 2: m31 = newValue[0]; m32 = newValue[1]; m33 = newValue[2]; m34 = newValue[3];
            case 3: m41 = newValue[0]; m42 = newValue[1]; m43 = newValue[2]; m44 = newValue[3];
            default: fatalError("Index outside of bounds")
            }
        }
    }
    
    /// Access the `col`th column vector and then `row`th element
    @inlinable
    public subscript(col: Int, row: Int) -> Float {
        get {
            switch col {
            case 0:
                switch row {
                case 0: return m11
                case 1: return m12
                case 2: return m13
                case 3: return m14
                default: fatalError("Index outside of bounds")
                }
            case 1:
                switch row {
                case 0: return m21
                case 1: return m22
                case 2: return m23
                case 3: return m24
                default: fatalError("Index outside of bounds")
                }
            case 2:
                switch row {
                case 0: return m31
                case 1: return m32
                case 2: return m33
                case 3: return m34
                default: fatalError("Index outside of bounds")
                }
            case 3:
                switch row {
                case 0: return m41
                case 1: return m42
                case 2: return m43
                case 3: return m44
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
                case 3: m14 = newValue
                default: fatalError("Index outside of bounds")
                }
            case 1:
                switch row {
                case 0: m21 = newValue
                case 1: m22 = newValue
                case 2: m23 = newValue
                case 3: m24 = newValue
                default: fatalError("Index outside of bounds")
                }
            case 2:
                switch row {
                case 0: m31 = newValue
                case 1: m32 = newValue
                case 2: m33 = newValue
                case 3: m34 = newValue
                default: fatalError("Index outside of bounds")
                }
            case 3:
                switch row {
                case 0: m41 = newValue
                case 1: m42 = newValue
                case 2: m43 = newValue
                case 3: m44 = newValue
                default: fatalError("Index outside of bounds")
                }
            default: fatalError("Index outside of bounds")
            }
        }
    }
}
    
extension Matrix4x4f {
    @inlinable
    public var adjugate: Matrix4x4f {
        var m = Matrix4x4f.identity
        
        m.m11 = m22 * m33 * m44 - m22 * m34 * m43
        m.m11 += -m32 * m23 * m44 + m32 * m24 * m43
        m.m11 += m42 * m23 * m34 - m42 * m24 * m33
        
        m.m21 = -m21 * m33 * m44 + m21 * m34 * m43
        m.m21 += m31 * m23 * m44 - m31 * m24 * m43
        m.m21 += -m41 * m23 * m34 + m41 * m24 * m33
        
        m.m31 = m21 * m32 * m44 - m21 * m34 * m42
        m.m31 += -m31 * m22 * m44 + m31 * m24 * m42
        m.m31 += m41 * m22 * m34 - m41 * m24 * m32
        
        m.m41 = -m21 * m32 * m43 + m21 * m33 * m42
        m.m41 += m31 * m22 * m43 - m31 * m23 * m42
        m.m41 += -m41 * m22 * m33 + m41 * m23 * m32
        
        m.m12 = -m12 * m33 * m44 + m12 * m34 * m43
        m.m12 += m32 * m13 * m44 - m32 * m14 * m43
        m.m12 += -m42 * m13 * m34 + m42 * m14 * m33
        
        m.m22 = m11 * m33 * m44 - m11 * m34 * m43
        m.m22 += -m31 * m13 * m44 + m31 * m14 * m43
        m.m22 += m41 * m13 * m34 - m41 * m14 * m33
        
        m.m32 = -m11 * m32 * m44 + m11 * m34 * m42
        m.m32 += m31 * m12 * m44 - m31 * m14 * m42
        m.m32 += -m41 * m12 * m34 + m41 * m14 * m32
        
        m.m42 = m11 * m32 * m43 - m11 * m33 * m42
        m.m42 += -m31 * m12 * m43 + m31 * m13 * m42
        m.m42 += m41 * m12 * m33 - m41 * m13 * m32
        
        m.m13 = m12 * m23 * m44 - m12 * m24 * m43
        m.m13 += -m22 * m13 * m44 + m22 * m14 * m43
        m.m13 += m42 * m13 * m24 - m42 * m14 * m23
        
        m.m23 = -m11 * m23 * m44 + m11 * m24 * m43
        m.m23 += m21 * m13 * m44 - m21 * m14 * m43
        m.m23 += -m41 * m13 * m24 + m41 * m14 * m23
        
        m.m33 = m11 * m22 * m44 - m11 * m24 * m42
        m.m33 += -m21 * m12 * m44 + m21 * m14 * m42
        m.m33 += m41 * m12 * m24 - m41 * m14 * m22
        
        m.m43 = -m11 * m22 * m43 + m11 * m23 * m42
        m.m43 += m21 * m12 * m43 - m21 * m13 * m42
        m.m43 += -m41 * m12 * m23 + m41 * m13 * m22
        
        m.m14 = -m12 * m23 * m34 + m12 * m24 * m33
        m.m14 += m22 * m13 * m34 - m22 * m14 * m33
        m.m14 += -m32 * m13 * m24 + m32 * m14 * m23
        
        m.m24 = m11 * m23 * m34 - m11 * m24 * m33
        m.m24 += -m21 * m13 * m34 + m21 * m14 * m33
        m.m24 += m31 * m13 * m24 - m31 * m14 * m23
        
        m.m34 = -m11 * m22 * m34 + m11 * m24 * m32
        m.m34 += m21 * m12 * m34 - m21 * m14 * m32
        m.m34 += -m31 * m12 * m24 + m31 * m14 * m22
        
        m.m44 = m11 * m22 * m33 - m11 * m23 * m32
        m.m44 += -m21 * m12 * m33 + m21 * m13 * m32
        m.m44 += m31 * m12 * m23 - m31 * m13 * m22
        
        return m
    }
    
    @usableFromInline
    internal func determinant(forAdjugate m: Matrix4x4f) -> Float {
        return m11 * m.m11 + m12 * m.m21 + m13 * m.m31 + m14 * m.m41
    }
    
    @inlinable
    public var determinant : Float {
        return determinant(forAdjugate: adjugate)
    }
    
    @inlinable
    public var transpose : Matrix4x4f {
        return Matrix4x4f(
            m11, m21, m31, m41,
            m12, m22, m32, m42,
            m13, m23, m33, m43,
            m14, m24, m34, m44
        )
    }
    
    @inlinable
    public var inverse: Matrix4x4f {
        let adjugate = self.adjugate // avoid recalculating
        return adjugate * (1 / determinant(forAdjugate: adjugate))
    }
    
    @inlinable
    public static func *(lhs: Matrix4x4f, rhs: Matrix4x4f) -> Matrix4x4f {
        var m = Matrix4x4f.identity
        
        m.m11 = lhs.m11 * rhs.m11 + lhs.m21 * rhs.m12
        m.m11 += lhs.m31 * rhs.m13 + lhs.m41 * rhs.m14
        
        m.m12 = lhs.m12 * rhs.m11 + lhs.m22 * rhs.m12
        m.m12 += lhs.m32 * rhs.m13 + lhs.m42 * rhs.m14
        
        m.m13 = lhs.m13 * rhs.m11 + lhs.m23 * rhs.m12
        m.m13 += lhs.m33 * rhs.m13 + lhs.m43 * rhs.m14
        
        m.m14 = lhs.m14 * rhs.m11 + lhs.m24 * rhs.m12
        m.m14 += lhs.m34 * rhs.m13 + lhs.m44 * rhs.m14
        
        m.m21 = lhs.m11 * rhs.m21 + lhs.m21 * rhs.m22
        m.m21 += lhs.m31 * rhs.m23 + lhs.m41 * rhs.m24
        
        m.m22 = lhs.m12 * rhs.m21 + lhs.m22 * rhs.m22
        m.m22 += lhs.m32 * rhs.m23 + lhs.m42 * rhs.m24
        
        m.m23 = lhs.m13 * rhs.m21 + lhs.m23 * rhs.m22
        m.m23 += lhs.m33 * rhs.m23 + lhs.m43 * rhs.m24
        
        m.m24 = lhs.m14 * rhs.m21 + lhs.m24 * rhs.m22
        m.m24 += lhs.m34 * rhs.m23 + lhs.m44 * rhs.m24
        
        m.m31 = lhs.m11 * rhs.m31 + lhs.m21 * rhs.m32
        m.m31 += lhs.m31 * rhs.m33 + lhs.m41 * rhs.m34
        
        m.m32 = lhs.m12 * rhs.m31 + lhs.m22 * rhs.m32
        m.m32 += lhs.m32 * rhs.m33 + lhs.m42 * rhs.m34
        
        m.m33 = lhs.m13 * rhs.m31 + lhs.m23 * rhs.m32
        m.m33 += lhs.m33 * rhs.m33 + lhs.m43 * rhs.m34
        
        m.m34 = lhs.m14 * rhs.m31 + lhs.m24 * rhs.m32
        m.m34 += lhs.m34 * rhs.m33 + lhs.m44 * rhs.m34
        
        m.m41 = lhs.m11 * rhs.m41 + lhs.m21 * rhs.m42
        m.m41 += lhs.m31 * rhs.m43 + lhs.m41 * rhs.m44
        
        m.m42 = lhs.m12 * rhs.m41 + lhs.m22 * rhs.m42
        m.m42 += lhs.m32 * rhs.m43 + lhs.m42 * rhs.m44
        
        m.m43 = lhs.m13 * rhs.m41 + lhs.m23 * rhs.m42
        m.m43 += lhs.m33 * rhs.m43 + lhs.m43 * rhs.m44
        
        m.m44 = lhs.m14 * rhs.m41 + lhs.m24 * rhs.m42
        m.m44 += lhs.m34 * rhs.m43 + lhs.m44 * rhs.m44
        
        return m
    }
    
    @inlinable
    public static func *(lhs: Matrix4x4f, rhs: Float) -> Matrix4x4f {
        return Matrix4x4f(
            lhs.m11 * rhs, lhs.m12 * rhs, lhs.m13 * rhs, lhs.m14 * rhs,
            lhs.m21 * rhs, lhs.m22 * rhs, lhs.m23 * rhs, lhs.m24 * rhs,
            lhs.m31 * rhs, lhs.m32 * rhs, lhs.m33 * rhs, lhs.m34 * rhs,
            lhs.m41 * rhs, lhs.m42 * rhs, lhs.m43 * rhs, lhs.m44 * rhs
        )
    }
    
    @inlinable
    public static prefix func -(lhs: Matrix4x4f) -> Matrix4x4f {
        return Matrix4x4f(
            -lhs.m11, -lhs.m12, -lhs.m13, -lhs.m14,
            -lhs.m21, -lhs.m22, -lhs.m23, -lhs.m24,
            -lhs.m31, -lhs.m32, -lhs.m33, -lhs.m34,
            -lhs.m41, -lhs.m42, -lhs.m43, -lhs.m44
        )
    }
}
    
#endif

extension Matrix4x4f {
    
    /// Creates a new instance from the values provided in column-major order
    public init(
        _ m00: Float, _ m01: Float, _ m02: Float, _ m03: Float,
        _ m10: Float, _ m11: Float, _ m12: Float, _ m13: Float,
        _ m20: Float, _ m21: Float, _ m22: Float, _ m23: Float,
        _ m30: Float, _ m31: Float, _ m32: Float, _ m33: Float) {
        self.init(
            vec4(m00, m01, m02, m03),
            vec4(m10, m11, m12, m13),
            vec4(m20, m21, m22, m23),
            vec4(m30, m31, m32, m33)
        )
    }
    
    public init(_ array: [Float]) {
        self = Matrix4x4f()
        for (i, val) in array.enumerated() {
            self[i / 4][i % 4] = val
        }
    }
    
    public init(quaternion q: Quaternion) {
        self = Matrix4x4f.identity
        
        let sqw = q.w*q.w
        let sqx = q.x*q.x
        let sqy = q.y*q.y
        let sqz = q.z*q.z
        
        // invs (inverse square length) is only required if quaternion is not already normalised
        let invs = 1.0 / (sqx + sqy + sqz + sqw)
        self[0, 0] = ( sqx - sqy - sqz + sqw)*invs // since sqw + sqx + sqy + sqz =1/invs*invs
        self[1, 1] = (-sqx + sqy - sqz + sqw)*invs
        self[2, 2] = (-sqx - sqy + sqz + sqw)*invs
        
        var tmp1 = q.x*q.y
        var tmp2 = q.z*q.w
        self[0, 1] = 2.0 * (tmp1 + tmp2)*invs
        self[1, 0] = 2.0 * (tmp1 - tmp2)*invs
        
        tmp1 = q.x*q.z
        tmp2 = q.y*q.w
        self[0, 2] = 2.0 * (tmp1 - tmp2)*invs
        self[2, 0] = 2.0 * (tmp1 + tmp2)*invs
        tmp1 = q.y*q.z
        tmp2 = q.x*q.w
        self[1, 2] = 2.0 * (tmp1 + tmp2)*invs
        self[2, 1] = 2.0 * (tmp1 - tmp2)*invs
    }
}


