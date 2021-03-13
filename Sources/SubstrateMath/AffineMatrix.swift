//
//  AffineMatrix.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 3/08/18.
//

import RealModule

/// A matrix that can represent 3D affine transformations.
/// Internally, the data is stored in row-major format for size reasons;
/// however, all operations treat it as a column-major type
/// It's conceptually a Matrix4x3f but happens to be stored as a 3x4f.
public struct AffineMatrix<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable, Codable, CustomStringConvertible {
    public var r0 : SIMD4<Scalar> = SIMD4(1, 0, 0, 0)
    public var r1 : SIMD4<Scalar> = SIMD4(0, 1, 0, 0)
    public var r2 : SIMD4<Scalar> = SIMD4(0, 0, 1, 0)
    
    @inlinable
    public init() {
    }
    
    @inlinable
    public init(diagonal: SIMD3<Scalar>) {
        self.r0 = SIMD4(diagonal.x, 0, 0, 0)
        self.r1 = SIMD4(0, diagonal.y, 0, 0)
        self.r2 = SIMD4(0, 0, diagonal.z, 0)
    }
    
    /// Creates an instance with the specified columns
    ///
    /// - parameter c0: a vector representing column 0
    /// - parameter c1: a vector representing column 1
    /// - parameter c2: a vector representing column 2
    /// - parameter c3: a vector representing column 3
    @inlinable
    public init(_ c0: SIMD4<Scalar>, _ c1: SIMD4<Scalar>, _ c2: SIMD4<Scalar>, _ c3: SIMD4<Scalar>) {
        self.r0 = SIMD4(c0.x, c1.x, c2.x, c3.x)
        self.r1 = SIMD4(c0.y, c1.y, c2.y, c3.y)
        self.r2 = SIMD4(c0.z, c1.z, c2.z, c3.z)
        
        assert(SIMD4(c0.w, c1.w, c2.w, c3.w) == SIMD4(0, 0, 0, 1), "Columns cannot be represented as an affine transform.")
    }
    
    @inlinable
    public init(rows r0: SIMD4<Scalar>, _ r1: SIMD4<Scalar>, _ r2: SIMD4<Scalar>) {
        self.r0 = r0
        self.r1 = r1
        self.r2 = r2
    }
    
    @inlinable
    public init(_ matrix: Matrix4x4<Scalar>) {
        let transpose = matrix.transpose
        assert(transpose[3] == SIMD4<Scalar>(0, 0, 0, 1))
        self.init(rows: transpose[0], transpose[1], transpose[2])
    }
    
    @inlinable
    public init(_ matrix: Matrix3x3<Scalar>) {
        self.init(rows: SIMD4<Scalar>(matrix[0].x, matrix[1].x, matrix[2].x, 0), SIMD4<Scalar>(matrix[0].y, matrix[1].y, matrix[2].y, 0), SIMD4<Scalar>(matrix[0].z, matrix[1].z, matrix[2].z, 0))
    }
    
    /// Access the `col`th column vector
    @inlinable
    public subscript(col: Int) -> SIMD4<Scalar> {
        get {
            switch col {
            case 0: return SIMD4(r0.x, r1.x, r2.x, 0)
            case 1: return SIMD4(r0.y, r1.y, r2.y, 0)
            case 2: return SIMD4(r0.z, r1.z, r2.z, 0)
            case 3: return SIMD4(r0.w, r1.w, r2.w, 1)
            default: preconditionFailure("Index out of bounds")
            }
        }
        
        set {
            switch col {
            case 0: self.r0.x = newValue.x; self.r1.x = newValue.y; self.r2.x = newValue.z; assert(newValue.w == 0)
            case 1: self.r0.y = newValue.x; self.r1.y = newValue.y; self.r2.y = newValue.z; assert(newValue.w == 0)
            case 2: self.r0.z = newValue.x; self.r1.z = newValue.y; self.r2.z = newValue.z; assert(newValue.w == 0)
            case 3: self.r0.w = newValue.x; self.r1.w = newValue.y; self.r2.w = newValue.z; assert(newValue.w == 1)
            default: preconditionFailure("Index out of bounds")
            }
        }
    }
    
    @inlinable
    public subscript(row row: Int) -> SIMD4<Scalar> {
        get {
            switch row {
            case 0: return self.r0
            case 1: return self.r1
            case 2: return self.r2
            case 3: return SIMD4(0, 0, 0, 1)
            default: preconditionFailure("Index out of bounds")
            }
        }
        
        set {
            switch row {
            case 0: self.r0 = newValue
            case 1: self.r1 = newValue
            case 2: self.r2 = newValue
            case 3: assert(newValue == SIMD4(0, 0, 0, 1))
            default: preconditionFailure("Index out of bounds")
            }
        }
    }
    
    @inlinable
    public subscript(row: Int, col: Int) -> Scalar {
        get {
            switch row {
            case 0:
               return self.r0[col]
            case 1:
                return self.r1[col]
            case 2:
                return self.r2[col]
            case 3:
                return SIMD4<Scalar>(0, 0, 0, 1)[col]
            default: preconditionFailure("Index out of bounds")
            }
        }
        
        set {
            switch row {
            case 0:
                self.r0[col] = newValue
            case 1:
                self.r1[col] = newValue
            case 2:
                self.r2[col] = newValue
            case 3:
                break
            default: preconditionFailure("Index out of bounds")
            }
        }
    }
    
    @inlinable
    public var inverse : AffineMatrix {
        // https://lxjk.github.io/2017/09/03/Fast-4x4-Matrix-Inverse-with-SSE-SIMD-Explained.html#_general_matrix_inverse
        
        var result = AffineMatrix()

        // transpose 3x3, we know m30 = m31 = m32 = 0
        let t0 = SIMD4(lowHalf: self.r0.lowHalf, highHalf: self.r1.lowHalf)
        let t1 = SIMD4(self.r0.z, 0.0, self.r1.z, 0.0)
        result.r0 = SIMD4(lowHalf: t0.evenHalf, highHalf: SIMD2(self.r2.x, 0.0))
        result.r1 = SIMD4(lowHalf: t0.oddHalf, highHalf: SIMD2(self.r2.y, 0.0))
        result.r2 = SIMD4(lowHalf: t1.evenHalf, highHalf: SIMD2(self.r2.z, 0.0))

        // (SizeSqr(mVec[0]), SizeSqr(mVec[1]), SizeSqr(mVec[2]), 0)
        var sizeSqr = self.r0.xyz * self.r0.xyz
        sizeSqr.addProduct(self.r1.xyz, self.r1.xyz)
        sizeSqr.addProduct(self.r2.xyz, self.r2.xyz)

        // optional test to avoid divide by 0
        // for each component, if(sizeSqr < SMALL_NUMBER) sizeSqr = 1;
        let rSizeSqr = (1.0 / sizeSqr).replacing(with: 1.0, where: sizeSqr .< 1.0e-8)

        result.r0 *= rSizeSqr.x
        result.r1 *= rSizeSqr.y
        result.r2 *= rSizeSqr.z

        // translation = -(result * self.translation)
        var translation = SIMD3(result.r0.x, result.r1.x, result.r2.x) * self.r0.w
        translation.addProduct(SIMD3(result.r0.y, result.r1.y, result.r2.y), self.r1.w)
        translation.addProduct(SIMD3(result.r0.z, result.r1.z, result.r2.z), self.r2.w)
        
        result.r0.w = -translation.x
        result.r1.w = -translation.y
        result.r2.w = -translation.z
        
        return result
    }
    
    @inlinable
    public var inverseNoScale : AffineMatrix {
        var result = AffineMatrix()
        
        // Transpose the 3x3 matrix.
        let t0 = SIMD4(lowHalf: self.r0.lowHalf, highHalf: self.r1.lowHalf)
        let t1 = SIMD4(self.r0.z, 0.0, self.r1.z, 0.0)
        result.r0 = SIMD4(lowHalf: t0.evenHalf, highHalf: SIMD2(self.r2.x, 0.0))
        result.r1 = SIMD4(lowHalf: t0.oddHalf, highHalf: SIMD2(self.r2.y, 0.0))
        result.r2 = SIMD4(lowHalf: t1.evenHalf, highHalf: SIMD2(self.r2.z, 0.0))
        
        // translation = -(result * self.translation)
        var translation = SIMD3(result.r0.x, result.r1.x, result.r2.x) * self.r0.w
        translation.addProduct(SIMD3(result.r0.y, result.r1.y, result.r2.y), self.r1.w)
        translation.addProduct(SIMD3(result.r0.z, result.r1.z, result.r2.z), self.r2.w)
        
        result.r0.w = -translation.x
        result.r1.w = -translation.y
        result.r2.w = -translation.z

        return result
    }
    
    /// Returns the maximum scale along any axis.
    @inlinable
    public var maximumScale : Scalar {
        let s0 = SIMD3<Scalar>(self.r0.x, self.r1.x, self.r2.x).lengthSquared
        let s1 = SIMD3<Scalar>(self.r0.y, self.r1.y, self.r2.y).lengthSquared
        let s2 = SIMD3<Scalar>(self.r0.z, self.r1.z, self.r2.z).lengthSquared
        
        return max(s0, max(s1, s2)).squareRoot()
    }
    
    public var description : String {
        return """
                AffineMatrix( \(self.r0.x), \(self.r0.y), \(self.r0.z), \(self.r0.w),
                              \(self.r1.x), \(self.r1.y), \(self.r1.z), \(self.r1.w),
                              \(self.r2.x), \(self.r2.y), \(self.r2.z), \(self.r2.w) )
               """
    }
}
extension AffineMatrix {

    @inlinable
    public static func *(lhs: AffineMatrix, rhs: AffineMatrix) -> AffineMatrix {
        var r0 = SIMD4(0, 0, 0, lhs.r0.w)
        r0.addProduct(SIMD4(repeating: lhs.r0.x), rhs.r0)
        r0.addProduct(SIMD4(repeating: lhs.r0.y), rhs.r1)
        r0.addProduct(SIMD4(repeating: lhs.r0.z), rhs.r2)
        
        var r1 = SIMD4(0, 0, 0, lhs.r1.w)
        r1.addProduct(SIMD4(repeating: lhs.r1.x), rhs.r0)
        r1.addProduct(SIMD4(repeating: lhs.r1.y), rhs.r1)
        r1.addProduct(SIMD4(repeating: lhs.r1.z), rhs.r2)
        
        var r2 = SIMD4(0, 0, 0, lhs.r2.w)
        r2.addProduct(SIMD4(repeating: lhs.r2.x), rhs.r0)
        r2.addProduct(SIMD4(repeating: lhs.r2.y), rhs.r1)
        r2.addProduct(SIMD4(repeating: lhs.r2.z), rhs.r2)
        
        return AffineMatrix(rows: r0, r1, r2)
    }
    
    @inlinable
    public static func *(lhs: Matrix4x4<Scalar>, rhs: AffineMatrix) -> Matrix4x4<Scalar> {
        return lhs * Matrix4x4(rhs)
    }
    
    @inlinable
    public static func *(lhs: AffineMatrix, rhs: SIMD4<Scalar>) -> SIMD4<Scalar> {
        var result = SIMD3(lhs.r0.x, lhs.r1.x, lhs.r2.x) * SIMD3(repeating: rhs.x)
        result.addProduct(SIMD3(lhs.r0.y, lhs.r1.y, lhs.r2.y), SIMD3(repeating: rhs.y))
        result.addProduct(SIMD3(lhs.r0.z, lhs.r1.z, lhs.r2.z), SIMD3(repeating: rhs.z))
        result.addProduct(SIMD3(lhs.r0.w, lhs.r1.w, lhs.r2.w), SIMD3(repeating: rhs.w))
        return SIMD4(result, rhs.w)
    }
}

extension Matrix3x3 {
    @inlinable
    public init(_ affineMatrix: AffineMatrix<Scalar>) {
        self.init(SIMD3(affineMatrix.r0.x, affineMatrix.r1.x, affineMatrix.r2.x),
                  SIMD3(affineMatrix.r0.y, affineMatrix.r1.y, affineMatrix.r2.y),
                  SIMD3(affineMatrix.r0.z, affineMatrix.r1.z, affineMatrix.r2.z))
    }
}


extension Matrix4x4 {
    @inlinable
    public init(_ affineMatrix: AffineMatrix<Scalar>) {
        self.init(SIMD4<Scalar>(affineMatrix.r0.x, affineMatrix.r1.x, affineMatrix.r2.x, 0),
                  SIMD4<Scalar>(affineMatrix.r0.y, affineMatrix.r1.y, affineMatrix.r2.y, 0),
                  SIMD4<Scalar>(affineMatrix.r0.z, affineMatrix.r1.z, affineMatrix.r2.z, 0),
                  SIMD4<Scalar>(affineMatrix.r0.w, affineMatrix.r1.w, affineMatrix.r2.w, 1))
    }
}

extension AffineMatrix {
    /// Returns the identity matrix
    @inlinable
    public static var identity : AffineMatrix { return AffineMatrix(diagonal: SIMD3<Scalar>(repeating: 1.0)) }
    
    //MARK: matrix operations
    
    @inlinable
    public static func lookAt(eye: SIMD3<Scalar>, at: SIMD3<Scalar>, up: SIMD3<Scalar> = SIMD3(0, 1, 0)) -> AffineMatrix {
        return lookAtLH(eye: eye, at: at, up: up)
    }
    
    @inlinable
    public static func lookAtLH(eye: SIMD3<Scalar>, at: SIMD3<Scalar>, up: SIMD3<Scalar> = SIMD3(0, 1, 0)) -> AffineMatrix {
        let view = normalize(at - eye)
        return lookAtLH(eye: eye, forward: view, up: up)
    }
    
    @inlinable
    public static func lookAtLH(eye: SIMD3<Scalar>, forward view: SIMD3<Scalar>, up: SIMD3<Scalar> = SIMD3(0, 1, 0)) -> AffineMatrix {
        var up = up
        if abs(dot(up, view)) > 0.99 {
            up = SIMD3<Scalar>(1, 0, 0)
        }
        
        let right = normalize(cross(up, view))
        let u     = cross(view, right)
        
        return AffineMatrix(rows: SIMD4<Scalar>(right, -dot(right, eye)),
                                SIMD4<Scalar>(u, -dot(u, eye)),
                                SIMD4<Scalar>(view, -dot(view, eye))
            )
    }
    
    @inlinable
    public static func lookAtInv(eye: SIMD3<Scalar>, at: SIMD3<Scalar>, up: SIMD3<Scalar> = SIMD3(0, 1, 0)) -> AffineMatrix {
        let view = normalize(at - eye)
        return lookAtInv(eye: eye, forward: view, up: up)
    }
    
    @inlinable
    public static func lookAtInv(eye: SIMD3<Scalar>, forward view: SIMD3<Scalar>, up: SIMD3<Scalar> = SIMD3(0, 1, 0)) -> AffineMatrix {
        var up = up
        if abs(dot(up, view)) > 0.99 {
            up = SIMD3<Scalar>(1, 0, 0)
        }
        
        let right = normalize(cross(up, view))
        let u     = cross(view, right)
        
        return AffineMatrix(rows: SIMD4<Scalar>(right.x, u.x, view.x, eye.x),
                            SIMD4<Scalar>(right.y, u.y, view.y, eye.y),
                            SIMD4<Scalar>(right.z, u.z, view.z, eye.z)
            )
    }
    
    @inlinable
    public static func lookAt(forward: SIMD3<Scalar>) -> AffineMatrix {
        var up = SIMD3<Scalar>(0, 1, 0)
        if abs(dot(up, forward)) > 0.99 {
            up = SIMD3<Scalar>(1, 0, 0)
        }
        
        let right = normalize(cross(up, forward))
        let u     = cross(forward, right)
        
        return AffineMatrix(rows: SIMD4<Scalar>(right.x, u.x, forward.x, 0),
                            SIMD4<Scalar>(right.y, u.y, forward.y, 0),
                            SIMD4<Scalar>(right.z, u.z, forward.z, 0)
        )
    }
    
    
    //MARK: matrix operations
    
    @inlinable
    public static func scale(by s: SIMD3<Scalar>) -> AffineMatrix {
        return AffineMatrix.scale(sx: s.x, sy: s.y, sz: s.z)
    }
    
    @inlinable
    public static func scale(sx: Scalar, sy: Scalar, sz: Scalar) -> AffineMatrix {
        return AffineMatrix(diagonal: SIMD3<Scalar>(sx, sy, sz))
    }
    
    @inlinable
    public static func translate(by t: SIMD3<Scalar>) -> AffineMatrix {
        return AffineMatrix.translate(tx: t.x, ty: t.y, tz: t.z)
    }
    
    @inlinable
    public static func translate(tx: Scalar, ty: Scalar, tz: Scalar) -> AffineMatrix {
        return AffineMatrix(rows: SIMD4<Scalar>(1, 0, 0, tx),
                            SIMD4<Scalar>(0, 1, 0, ty),
                            SIMD4<Scalar>(0, 0, 1, tz))
    }
    
}

extension AffineMatrix where Scalar : Real {
    
    @inlinable
    public init(quaternion q: Quaternion<Scalar>) {
        self.init()
        let sqw : Scalar = q.w*q.w
        let sqx : Scalar = q.x*q.x
        let sqy : Scalar = q.y*q.y
        let sqz : Scalar = q.z*q.z
        
        let n : Scalar = sqx + sqy + sqz + sqw
        let s : Scalar = n == 0 ? 0 : 2.0 / n
        
        let wx = s * q.w * q.x
        let wy = s * q.w * q.y
        let wz = s * q.w * q.z
        let xx = s * sqx
        let xy = s * q.x * q.y
        let xz = s * q.x * q.z
        let yy = s * sqy
        let yz = s * q.y * q.z
        let zz = s * sqz
        
        self[0,0] = 1.0 - (yy + zz)
        self[0,1] = xy - wz
        self[0,2] = xz + wy
        self[1,0] = xy + wz
        self[1,1] = 1.0 - (xx + zz)
        self[1,2] = yz - wx
        self[2,0] = xz - wy
        self[2,1] = yz + wx
        self[2,2] = 1.0 - (xx + yy)
    }
    
    
    @inlinable
    public static func rotate(_ quaternion: Quaternion<Scalar>) -> AffineMatrix {
        return AffineMatrix(quaternion: quaternion)
    }
    
    /// Create a matrix with rotates clockwise around the x axis
    @inlinable
    public static func rotate(x: Angle<Scalar>) -> AffineMatrix {
        let (sin: sx, cos: cx) = Angle<Scalar>.sincos(x)
        
        var r = AffineMatrix()
        r[0, 0] = 1.0
        r[1, 1] = cx
        r[1, 2] = sx
        r[2, 1] = -sx
        r[2, 2] = cx
        
        return r
    }
    
    /// Returns a transformation matrix that rotates clockwise around the y axis
    @inlinable
    public static func rotate(y: Angle<Scalar>) -> AffineMatrix {
        let (sin: sy, cos: cy) = Angle<Scalar>.sincos(y)
        
        var r = AffineMatrix()
        r[0,0] = cy
        r[0,2] = -sy
        r[1,1] = 1.0
        r[2,0] = sy
        r[2,2] = cy
        
        return r
    }
    
    /// Returns a transformation matrix that rotates clockwise around the z axis
    @inlinable
    public static func rotate(z: Angle<Scalar>) -> AffineMatrix {
        let (sin: sz, cos: cz) = Angle<Scalar>.sincos(z)
        
        var r = AffineMatrix()
        r[0,0] = cz
        r[0,1] = sz
        r[1,0] = -sz
        r[1,1] = cz
        r[2,2] = 1.0
        
        return r
    }
    
    /// Returns a transformation matrix that rotates clockwise around the given axis
    @inlinable
    public static func rotate(angle: Angle<Scalar>, axis: SIMD3<Scalar>) -> AffineMatrix {
        let (sin: st, cos: ct) = Angle<Scalar>.sincos(angle)
        
        let oneMinusCT = 1.0 - ct
        
        var r = AffineMatrix()
        r[0,0] = (axis.x * axis.x * oneMinusCT as Scalar) + (ct as Scalar)
        r[0,1] = (axis.x * axis.y * oneMinusCT as Scalar) + (axis.z * st as Scalar)
        r[0,2] = (axis.x * axis.z * oneMinusCT as Scalar) - (axis.y * st as Scalar)
        r[1,0] = (axis.x * axis.y * oneMinusCT as Scalar) - (axis.z * st as Scalar)
        r[1,1] = (axis.y * axis.y * oneMinusCT as Scalar) + (ct as Scalar)
        r[1,2] = (axis.y * axis.z * oneMinusCT as Scalar) + (axis.x * st as Scalar)
        r[2,0] = (axis.x * axis.z * oneMinusCT as Scalar) + (axis.y * st as Scalar)
        r[2,1] = (axis.y * axis.z * oneMinusCT as Scalar) - (axis.x * st as Scalar)
        r[2,2] = (axis.z * axis.z * oneMinusCT as Scalar) + (ct as Scalar)
        
        return r
    }
    
    /// Returns a transformation matrix that rotates clockwise around the x and then y axes
    @inlinable
    public static func rotate(x: Angle<Scalar>, y: Angle<Scalar>) -> AffineMatrix {
        // TODO: optimize.
        return AffineMatrix.rotate(y: y) * AffineMatrix.rotate(x: x)
    }
    
    /// Returns a transformation matrix that rotates clockwise around the x, y, and then z axes
    @inlinable
    public static func rotate(x: Angle<Scalar>, y: Angle<Scalar>, z: Angle<Scalar>) -> AffineMatrix {
        // TODO: optimize.
        return AffineMatrix.rotate(z: z) * AffineMatrix.rotate(y: y) * AffineMatrix.rotate(x: x)
    }
    
    /// Returns a transformation matrix that rotates clockwise around the y, x, and then z axes
    @inlinable
    public static func rotate(y: Angle<Scalar>, x: Angle<Scalar>, z: Angle<Scalar>) -> AffineMatrix {
        // TODO: optimize.
        return AffineMatrix.rotate(z: z) * AffineMatrix.rotate(x: x) * AffineMatrix.rotate(y: y)
    }
    
    /// Returns a transformation matrix that rotates clockwise around the z, y, and then x axes
    @inlinable
    public static func rotate(z: Angle<Scalar>, y: Angle<Scalar>, x: Angle<Scalar>) -> AffineMatrix {
        let (sx, cx) = Angle<Scalar>.sincos(x)
        let (sy, cy) = Angle<Scalar>.sincos(y)
        let (sz, cz) = Angle<Scalar>.sincos(z)
        
        var r = AffineMatrix()
        r[0,0] = (cy * cz) as Scalar
        r[1,0] = (cz * sx * sy) as Scalar - (cx * sz) as Scalar
        r[2,0] = (cx * cz * sy) as Scalar + (sx * sz) as Scalar
        r[0,1] = (cy * sz) as Scalar
        r[1,1] = (cx * cz) as Scalar + (sx * sy * sz) as Scalar
        r[2,1] = -(cz * sx) as Scalar + (cx * sy * sz) as Scalar
        r[0,2] = -sy as Scalar
        r[1,2] = (cy * sx) as Scalar
        r[2,2] = (cx * cy) as Scalar
        
        return r
    }
    
    /// Returns a transformation matrix which can be used to scale, rotate and translate vectors
    @inlinable
    public static func scaleRotateTranslate(scale: SIMD3<Scalar>,
                                            rotation: Quaternion<Scalar>,
                                            translation: SIMD3<Scalar>) -> AffineMatrix {
        
        let sqw : Scalar = rotation.w * rotation.w
        let sqx : Scalar = rotation.x * rotation.x
        let sqy : Scalar = rotation.y * rotation.y
        let sqz : Scalar = rotation.z * rotation.z
        
        var r0 = SIMD4<Scalar>(repeating: 0)
        var r1 = SIMD4<Scalar>(repeating: 0)
        var r2 = SIMD4<Scalar>(repeating: 0)
        
        r0.x = ( sqx - sqy - sqz + sqw) // since sqw + sqx + sqy + sqz =1/invs*invs
        r1.y = (-sqx + sqy - sqz + sqw)
        r2.z = (-sqx - sqy + sqz + sqw)
        
        var tmp1 : Scalar = rotation.x * rotation.y
        var tmp2 : Scalar = rotation.z * rotation.w
        r1.x = 2.0 * (tmp1 + tmp2)
        r0.y = 2.0 * (tmp1 - tmp2)
        
        tmp1 = rotation.x * rotation.z
        tmp2 = rotation.y * rotation.w
        r2.x = 2.0 * (tmp1 - tmp2)
        r0.z = 2.0 * (tmp1 + tmp2)
        tmp1 = rotation.y * rotation.z
        tmp2 = rotation.x * rotation.w
        r2.y = 2.0 * (tmp1 + tmp2)
        r1.z = 2.0 * (tmp1 - tmp2)
        
        let sqLength : Scalar = sqx + sqy + sqz + sqw
        let scale = scale / sqLength
        r0.xyz *= scale
        r1.xyz *= scale
        r2.xyz *= scale
        
        r0.w = translation.x
        r1.w = translation.y
        r2.w = translation.z
        
        return AffineMatrix(rows: r0, r1, r2)
    }
    
    @inlinable
    public var decomposed : (translation: SIMD3<Scalar>, rotation: Quaternion<Scalar>, scale: SIMD3<Scalar>) {
        var currentTransform = self
        let translation = currentTransform[3].xyz
        
        currentTransform[3] = SIMD4<Scalar>(0, 0, 0, 1)
        var scale = SIMD3<Scalar>(currentTransform[0].xyz.length, currentTransform[1].xyz.length, currentTransform[2].xyz.length)
        
        let tempZ = cross(currentTransform[0].xyz, currentTransform[1].xyz)
        if dot(tempZ, currentTransform[2].xyz) < 0 {
            scale.x *= -1
        }
        
        currentTransform[0] /= max(scale.x, .leastNormalMagnitude)
        currentTransform[1] /= max(scale.y, .leastNormalMagnitude)
        currentTransform[2] /= max(scale.z, .leastNormalMagnitude)
        
        let rotation = Quaternion(currentTransform)
        return (translation, rotation, scale)
    }
}

extension AffineMatrix {
    
    @inlinable
    public var right : SIMD3<Scalar> {
        get {
            return SIMD3<Scalar>(r0.x, r1.x, r2.x)
        }
        set {
            self.r0.x = newValue.x
            self.r1.x = newValue.y
            self.r2.x = newValue.z
        }
    }
    
    @inlinable
    public var up : SIMD3<Scalar> {
        get {
            return SIMD3<Scalar>(r0.y, r1.y, r2.y)
        }
        set {
            self.r0.y = newValue.x
            self.r1.y = newValue.y
            self.r2.y = newValue.z
        }
    }
    
    @inlinable
    public var forward : SIMD3<Scalar> {
        get {
            return SIMD3<Scalar>(r0.z, r1.z, r2.z)
        }
        set {
            self.r0.z = newValue.x
            self.r1.z = newValue.y
            self.r2.z = newValue.z
        }
    }
    
    @inlinable
    public var translation : SIMD4<Scalar> {
        get {
            return SIMD4<Scalar>(r0.w, r1.w, r2.w, 1.0)
        }
        set {
            self.r0.w = newValue.x
            self.r1.w = newValue.y
            self.r2.w = newValue.z
            assert(newValue.w == 1.0)
        }
    }
}
