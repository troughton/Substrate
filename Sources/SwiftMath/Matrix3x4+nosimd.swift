#if NOSIMD
@_fixed_layout
public struct Matrix3x4f {
    public var m11: Float = 0.0
    public var m12: Float = 0.0
    public var m13: Float = 0.0
    public var m14 : Float = 0.0
    
    public var m21: Float = 0.0
    public var m22: Float = 0.0
    public var m23: Float = 0.0
    public var m24 : Float = 0.0
    
    public var m31: Float = 0.0
    public var m32: Float = 0.0
    public var m33: Float = 0.0
    public var m34 : Float = 0.0
    
    public func toArray() -> [Float] {
        return [m11, m12, m13, m14, m21, m22, m23, m24, m31, m32, m33, m34]
    }
  
    @inlinable
    public init() {}
    
    /// Creates an instance with the specified columns
    ///
    /// - parameter c0: a vector representing column 0
    /// - parameter c1: a vector representing column 1
    /// - parameter c2: a vector representing column 2
    
    @inlinable
    public init(_ c0: Vector4f, _ c1: Vector4f, _ c2: Vector4f) {
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
    }
    
    /// Access the `col`th column vector
    @inlinable
    public subscript(col: Int) -> Vector4f {
        get {
            switch col {
            case 0: return Vector4f(m11, m12, m13, m14)
            case 1: return Vector4f(m21, m22, m23, m24)
            case 2: return Vector4f(m31, m32, m33, m34)
            default: fatalError("Index outside of bounds")
            }
        }
        
        set {
            switch col {
            case 0: m11 = newValue[0]; m12 = newValue[1]; m13 = newValue[2]; m14 = newValue[3];
            case 1: m21 = newValue[0]; m22 = newValue[1]; m23 = newValue[2]; m24 = newValue[3];
            case 2: m31 = newValue[0]; m32 = newValue[1]; m33 = newValue[2]; m34 = newValue[3];
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
            default: fatalError("Index outside of bounds")
            }
        }
    }
    
    @inlinable
    public static prefix func -(m: Matrix3x4f) -> Matrix3x4f {
        return Matrix3x4f(
            -m.m11, -m.m12, -m.m13, -m.m14,
            -m.m21, -m.m22, -m.m23, -m.m24,
            -m.m31, -m.m32, -m.m33, -m.m34
        )
    }
    
    @inlinable
    public static func *(lhs: Matrix3x4f, rhs: Float) -> Matrix3x4f {
        return Matrix3x4f(
            lhs.m11 * rhs, lhs.m12 * rhs, lhs.m13 * rhs, lhs.m14 * rhs,
            lhs.m21 * rhs, lhs.m22 * rhs, lhs.m23 * rhs, lhs.m24 * rhs,
            lhs.m31 * rhs, lhs.m32 * rhs, lhs.m33 * rhs, lhs.m34 * rhs
        )
    }
    
}

#endif // NOSIMD


extension Matrix3x4f {
    
    /// Creates a new instance from the values provided in column-major order
    @inlinable
    public init(
        _ m00: Float, _ m01: Float, _ m02: Float, _ m03: Float,
        _ m10: Float, _ m11: Float, _ m12: Float, _ m13: Float,
        _ m20: Float, _ m21: Float, _ m22: Float, _ m23: Float) {
        self.init(
            vec4(m00, m01, m02, m03),
            vec4(m10, m11, m12, m13),
            vec4(m20, m21, m22, m23)
        )
    }
    
}

extension Matrix3x4f {
    @inlinable
    public init(transposing matrix: Matrix4x4f) {
        let transpose = matrix.transpose
        self.init(transpose[0], transpose[1], transpose[2])
    }
}
