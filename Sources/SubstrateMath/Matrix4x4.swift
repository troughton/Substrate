// Copyright 2016 Stuart Carnie.
// License: https://github.com/SwiftGFX/SwiftMath#license-bsd-2-clause
//

import RealModule

@frozen
public struct Matrix4x4<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable {
    public var c0: SIMD4<Scalar> = SIMD4(1, 0, 0, 0)
    public var c1: SIMD4<Scalar> = SIMD4(0, 1, 0, 0)
    public var c2: SIMD4<Scalar> = SIMD4(0, 0, 1, 0)
    public var c3: SIMD4<Scalar> = SIMD4(0, 0, 0, 1)
    
    @inlinable
    public init() {}
    
    /// Creates an instance using the vector to initialize the diagonal elements
    @inlinable
    public init(diagonal v: SIMD4<Scalar>) {
        self.c0 = SIMD4(v.x, 0, 0, 0)
        self.c1 = SIMD4(0, v.y, 0, 0)
        self.c2 = SIMD4(0, 0, v.z, 0)
        self.c3 = SIMD4(0, 0, 0, v.w)
    }
    
    /// Creates an instance with the specified columns
    ///
    /// - parameter c0: a vector representing column 0
    /// - parameter c1: a vector representing column 1
    /// - parameter c2: a vector representing column 2
    /// - parameter c3: a vector representing column 3
    @inlinable
    public init(_ c0: SIMD4<Scalar>, _ c1: SIMD4<Scalar>, _ c2: SIMD4<Scalar>, _ c3: SIMD4<Scalar>) {
        self.c0 = c0
        self.c1 = c1
        self.c2 = c2
        self.c3 = c3
    }
    
    /// Access the `col`th column vector
    @inlinable
    public subscript(col: Int) -> SIMD4<Scalar> {
        get {
            switch col {
            case 0: return self.c0
            case 1: return self.c1
            case 2: return self.c2
            case 3: return self.c3
            default: preconditionFailure("Index out of bounds")
            }
        }
        
        set {
            switch col {
            case 0: self.c0 = newValue
            case 1: self.c1 = newValue
            case 2: self.c2 = newValue
            case 3: self.c3 = newValue
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
}
    
extension Matrix4x4 {
    
    @inlinable
    public var transpose : Matrix4x4 {
        return Matrix4x4(
            SIMD4<Scalar>(self.c0.x, self.c1.x, self.c2.x, self.c3.x),
            SIMD4<Scalar>(self.c0.y, self.c1.y, self.c2.y, self.c3.y),
            SIMD4<Scalar>(self.c0.z, self.c1.z, self.c2.z, self.c3.z),
            SIMD4<Scalar>(self.c0.w, self.c1.w, self.c2.w, self.c3.w)
        )
    }
    
    @inlinable
    public var inverse: Matrix4x4 {
        // https://lxjk.github.io/2017/09/03/Fast-4x4-Matrix-Inverse-with-SSE-SIMD-Explained.html#_general_matrix_inverse
        // use block matrix method
        // A is a matrix, then i(A) or iA means inverse of A, A# (or A_ in code) means adjugate of A, |A| (or detA in code) is determinant, tr(A) is trace

        // sub matrices
        let A = Matrix2x2(SIMD4(lowHalf: self.c0.xy, highHalf: self.c1.xy))
        let C = Matrix2x2(SIMD4(lowHalf: self.c0.zw, highHalf: self.c1.zw))
        let B = Matrix2x2(SIMD4(lowHalf: self.c2.xy, highHalf: self.c3.xy))
        let D = Matrix2x2(SIMD4(lowHalf: self.c2.zw, highHalf: self.c3.zw))

        // determinant as (|A| |C| |B| |D|)
        var detSub = SIMD4(lowHalf: self.c0.xz, highHalf: self.c2.xz) * SIMD4(lowHalf: self.c1.yw, highHalf: self.c3.yw)
        detSub -= SIMD4(lowHalf: self.c0.yw, highHalf: self.c2.yw) * SIMD4(lowHalf: self.c1.xz, highHalf: self.c3.xz)

        let detA = SIMD4(repeating: detSub.x)
        let detC = SIMD4(repeating: detSub.y)
        let detB = SIMD4(repeating: detSub.z)
        let detD = SIMD4(repeating: detSub.w)

        // let iM = 1/|M| * | X  Y |
        //                  | Z  W |

        // D#C
        let D_C = Matrix2x2.mul_AAdj_B(D, C)
        // A#B
        let A_B = Matrix2x2.mul_AAdj_B(A, B)
        // X# = |D|A - B(D#C)
        var X_ = detD * A.columns - (B * D_C).columns
        // W# = |A|D - C(A#B)
        var W_ = detA * D.columns - (C * A_B).columns

        // |M| = |A|*|D| + ... (continue later)
        var detM = detA * detD

        // Y# = |B|C - D(A#B)#
        var Y_ = detB * C.columns - Matrix2x2.mul_A_BAdj(D, A_B).columns
        // Z# = |C|B - A(D#C)#
        var Z_ = detC * B.columns - Matrix2x2.mul_A_BAdj(A, D_C).columns

        // |M| = |A|*|D| + |B|*|C| ... (continue later)
        detM.addProduct(detB, detC)

        // tr((A#B)(D#C))
        var tr = A_B.columns * D_C.columns[SIMD4(0, 2, 1, 3)]
        tr = SIMD4<Scalar>(tr.x + tr.y, tr.z + tr.w, tr.x + tr.y, tr.z + tr.w)
        tr = SIMD4<Scalar>(tr.x + tr.y, tr.z + tr.w, tr.x + tr.y, tr.z + tr.w)
        // |M| = |A|*|D| + |B|*|C| - tr((A#B)(D#C))
        detM -= tr

        let adjSignMask = SIMD4<Scalar>(1, -1, -1, 1)
        // (1/|M|, -1/|M|, -1/|M|, 1/|M|)
        let rDetM = adjSignMask / detM

        X_ *= rDetM
        Y_ *= rDetM
        Z_ *= rDetM
        W_ *= rDetM

        var r = Matrix4x4<Scalar>()

        // apply adjugate and store, here we combine adjugate shuffle and store shuffle
        r.c0 = SIMD4(lowHalf: X_[SIMD2(3, 1)], highHalf: Z_[SIMD2(3, 1)])
        r.c1 = SIMD4(lowHalf: X_[SIMD2(2, 0)], highHalf: Z_[SIMD2(2, 0)])
        r.c2 = SIMD4(lowHalf: Y_[SIMD2(3, 1)], highHalf: W_[SIMD2(3, 1)])
        r.c3 = SIMD4(lowHalf: Y_[SIMD2(2, 0)], highHalf: W_[SIMD2(2, 0)])

        return r
    }
    
    @inlinable
    public static func *(lhs: Matrix4x4, rhs: Matrix4x4) -> Matrix4x4 {
        let rhsT = rhs.transpose
        
        let lhsSelectionVector : SIMD16<UInt32> = SIMD16(0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3)
        let rhsSelectionVector : SIMD16<UInt32> = SIMD16(0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3)
        
        var columns = lhs.c0[lhsSelectionVector] * rhsT.c0[rhsSelectionVector]
        columns.addProduct(lhs.c1[lhsSelectionVector], rhsT.c1[rhsSelectionVector])
        columns.addProduct(lhs.c2[lhsSelectionVector], rhsT.c2[rhsSelectionVector])
        columns.addProduct(lhs.c3[lhsSelectionVector], rhsT.c3[rhsSelectionVector])
        
        return Matrix4x4(columns[SIMD4(0, 1, 2, 3)],
                         columns[SIMD4(4, 5, 6, 7)],
                         columns[SIMD4(8, 9, 10, 11)],
                         columns[SIMD4(12, 13, 14, 15)])
    }
    
    @inlinable
    public static func *(lhs: Matrix4x4, rhs: SIMD4<Scalar>) -> SIMD4<Scalar> {
        var result = lhs.c0 * SIMD4<Scalar>(repeating: rhs.x)
        result.addProduct(lhs.c1, SIMD4<Scalar>(repeating: rhs.y))
        result.addProduct(lhs.c2, SIMD4<Scalar>(repeating: rhs.z))
        result.addProduct(lhs.c3, SIMD4<Scalar>(repeating: rhs.w))
        return result
    }
    
    @inlinable
    public static func *(lhs: SIMD4<Scalar>, rhs: Matrix4x4) -> SIMD4<Scalar> {
        var result = SIMD4(rhs.c0.x, rhs.c1.x, rhs.c2.x, rhs.c3.x) * SIMD4(repeating: lhs.x)
        result.addProduct(SIMD4(rhs.c0.y, rhs.c1.y, rhs.c2.y, rhs.c3.y), SIMD4(repeating: lhs.y))
        result.addProduct(SIMD4(rhs.c0.z, rhs.c1.z, rhs.c2.z, rhs.c3.z), SIMD4(repeating: lhs.z))
        result.addProduct(SIMD4(rhs.c0.w, rhs.c1.w, rhs.c2.w, rhs.c3.w), SIMD4(repeating: lhs.w))
        return result
    }
    
    @inlinable
    public static func *(lhs: Matrix4x4, rhs: Scalar) -> Matrix4x4 {
        return Matrix4x4(
            lhs.c0 * SIMD4(repeating: rhs),
            lhs.c1 * SIMD4(repeating: rhs),
            lhs.c2 * SIMD4(repeating: rhs),
            lhs.c3 * SIMD4(repeating: rhs)
        )
    }
}

extension Matrix4x4 {
    /// Returns the identity matrix
    public static var identity : Matrix4x4 { return Matrix4x4(diagonal: SIMD4<Scalar>(repeating: 1)) }
}

extension Matrix4x4 where Scalar: Real {
    
    /// Creates a left-handed perspective projection matrix
    @inlinable
    public static func proj(fovy: Angle<Scalar>, aspect: Scalar, near: Scalar, far: Scalar) -> Matrix4x4 {
        let height : Scalar = 1 / Scalar.tan(fovy.radians * 0.5)
        let width : Scalar = height * 1 / aspect;
        return projLH(x: 0, y: 0, w: width, h: height, near: near, far: far)
    }
    
    /// Creates a left-handed perspective projection matrix with the near plane mapping to Z = 1.0 and infinity mapping to Z = 0.0
    @inlinable
    public static func projReversedZ(fovy: Angle<Scalar>, aspect: Scalar, near: Scalar) -> Matrix4x4 {
        let height : Scalar = 1 / Scalar.tan(fovy.radians * 0.5)
        let width : Scalar = height * 1 / aspect;
        return projLHReversedZ(x: 0, y: 0, w: width, h: height, near: near)
    }
    
    /// Creates a left-handed perspective projection matrix
    @inlinable
    public static func projLH(x: Scalar, y: Scalar, w: Scalar, h: Scalar, near: Scalar, far: Scalar) -> Matrix4x4 {
        let diff = far - near
        let aa   = far / diff
        let bb   = near * aa
        
        var r = Matrix4x4()
        r[0][0] = w
        r[1][1] = h
        r[2][0] = -x
        r[2][1] = -y
        r[2][2] = aa
        r[2][3] = 1
        r[3][2] = -bb
        r[3][3] = 0
        
        return r
    }
    
    /// Creates a left-handed perspective projection with the near plane mapping to Z = 1.0 and infinity mapping to Z = 0.0
    @inlinable
    public static func projLHReversedZ(x: Scalar, y: Scalar, w: Scalar, h: Scalar, near: Scalar) -> Matrix4x4 {
        var r = Matrix4x4()
        r[0][0] = w
        r[1][1] = h
        r[2][0] = -x
        r[2][1] = -y
        r[2][2] = 0
        r[2][3] = 1
        r[3][2] = near
        r[3][3] = 0
        
        return r
    }
    
    /// Creates a right-handed perspective projection matrix
    @inlinable
    public static func projRH(x: Scalar, y: Scalar, w: Scalar, h: Scalar, near: Scalar, far: Scalar) -> Matrix4x4 {
        let diff = far - near
        let aa   = far / diff
        let bb   = near * aa
        
        var r = Matrix4x4()
        r[0][0] = w
        r[1][1] = h
        r[2][0] = x
        r[2][1] = y
        r[2][2] = -aa
        r[2][3] = -1
        r[3][2] = -bb
        r[3][3] = 0
        
        return r
    }
    
    /// Creates a left-handed orthographic projection matrix
    @inlinable
    public static func ortho(left: Scalar, right: Scalar, bottom: Scalar, top: Scalar, near: Scalar, far: Scalar) -> Matrix4x4 {
        return orthoLH(left: left, right: right, bottom: bottom, top: top, near: near, far: far)
    }
    
    /// Creates a left-handed orthographic projection matrix
    @inlinable
    public static func orthoLH(left: Scalar, right: Scalar, bottom: Scalar, top: Scalar, near: Scalar, far: Scalar, offset: Scalar = 0) -> Matrix4x4 {
        let aa = 2.0 / (right - left)
        let bb = 2.0 / (top - bottom)
        let cc = 1 / (far - near)
        let dd = (left + right) / (left - right)
        let ee = (top + bottom) / (bottom - top)
        let ff = near * -cc
        
        var r = Matrix4x4()
        r[0][0] = aa
        r[1][1] = bb
        r[2][2] = cc
        r[3][0] = dd + offset
        r[3][1] = ee
        r[3][2] = ff
        r[3][3] = 1
        
        return r
    }
    
    /// Creates a right-handed orthographic projection matrix
    @inlinable
    public static func orthoRH(left: Scalar, right: Scalar, bottom: Scalar, top: Scalar, near: Scalar, far: Scalar, offset: Scalar = 0) -> Matrix4x4 {
        let aa = 2.0 / (right - left)
        let bb = 2.0 / (top - bottom)
        let cc = 1 / (far - near)
        let dd = (left + right) / (left - right)
        let ee = (top + bottom) / (bottom - top)
        let ff = near * -cc // Near > 0, so ff = -sign(cc)
        // If r[3,2] and r[2, 2] have the same sign, we're right-handed
        
        var r = Matrix4x4()
        r[0][0] = aa
        r[1][1] = bb
        r[2][2] = -cc
        r[3][0] = dd + offset
        r[3][1] = ee
        r[3][2] = ff
        r[3][3] = 1
        
        return r
    }
}

extension Matrix4x4: CustomStringConvertible {
    /// Displays the matrix in row-major order
    public var description: String {
        return "Matrix4x4(\n" +
            "m00: \(self[0,0]), m01: \(self[1,0]), m02: \(self[2,0]), m03: \(self[3,0]),\n" +
            "m10: \(self[0,1]), m11: \(self[1,1]), m12: \(self[2,1]), m13: \(self[3,1]),\n" +
            "m20: \(self[0,2]), m21: \(self[1,2]), m22: \(self[2,2]), m23: \(self[3,2]),\n" +
            "m30: \(self[0,3]), m31: \(self[1,3]), m32: \(self[2,3]), m33: \(self[3,3]),\n" +
        ")"
    }
}

extension Matrix4x4 : CustomDebugStringConvertible {
    public var debugDescription : String {
        return self.description
    }
}

extension Matrix4x4: Codable {
    @inlinable
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let c0 = try container.decode(SIMD4<Scalar>.self)
        let c1 = try container.decode(SIMD4<Scalar>.self)
        let c2 = try container.decode(SIMD4<Scalar>.self)
        let c3 = try container.decode(SIMD4<Scalar>.self)
        self.init(c0, c1, c2, c3)
    }
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.c0)
        try container.encode(self.c1)
        try container.encode(self.c2)
        try container.encode(self.c3)
    }
}

extension Matrix4x4 {
    
    @inlinable
    public var right : SIMD3<Scalar> {
        return self[0][SIMD3(0, 1, 2)]
    }
    
    @inlinable
    public var up : SIMD3<Scalar> {
        return self[1][SIMD3(0, 1, 2)]
    }
    
    @inlinable
    public var forward : SIMD3<Scalar> {
        return self[2][SIMD3(0, 1, 2)]
    }
    
    @inlinable
    public var translation : SIMD4<Scalar> {
        get {
            return self[3]
        }
        set {
            self[3] = newValue
        }
    }
}

public typealias Matrix4x4f = Matrix4x4<Float>
