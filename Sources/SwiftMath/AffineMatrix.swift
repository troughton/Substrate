//
//  AffineMatrix.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 3/08/18.
//

/// A matrix that can represent 3D affine transformations.
/// Internally, the data is stored in row-major format for size reasons;
/// however, all operations treat it as a column-major type
/// It's conceptually a Matrix4x3f but happens to be stored as a 3x4f.
@_fixed_layout
public struct AffineMatrix : Equatable, CustomStringConvertible {
    public var r0 : Vector4f
    public var r1 : Vector4f
    public var r2 : Vector4f
    
    @inlinable
    public init() {
        self.init(diagonal: Vector3f(1))
    }
    
    @inlinable
    public init(diagonal: Vector3f) {
        self.r0 = Vector4f(diagonal.x, 0, 0, 0)
        self.r1 = Vector4f(0, diagonal.y, 0, 0)
        self.r2 = Vector4f(0, 0, diagonal.z, 0)
    }
    
    /// Creates an instance with the specified columns
    ///
    /// - parameter c0: a vector representing column 0
    /// - parameter c1: a vector representing column 1
    /// - parameter c2: a vector representing column 2
    /// - parameter c3: a vector representing column 3
    @inlinable
    public init(_ c0: Vector4f, _ c1: Vector4f, _ c2: Vector4f, _ c3: Vector4f) {
        self.r0 = Vector4f(c0.x, c1.x, c2.x, c3.x)
        self.r1 = Vector4f(c0.y, c1.y, c2.y, c3.y)
        self.r2 = Vector4f(c0.z, c1.z, c2.z, c3.z)
        
        assert(Vector4f(c0.w, c1.w, c2.w, c3.w) == Vector4f(0, 0, 0, 1), "Columns cannot be represented as an affine transform.")
    }
    
    @inlinable
    public init(rows r0: Vector4f, _ r1: Vector4f, _ r2: Vector4f) {
        self.r0 = r0
        self.r1 = r1
        self.r2 = r2
    }
    
    @inlinable
    public init(_ matrix: Matrix4x4f) {
        let transpose = matrix.transpose
        assert(transpose[3] == Vector4f(0, 0, 0, 1))
        self.init(rows: transpose[0], transpose[1], transpose[2])
    }
    
    @inlinable
    public init(_ matrix: Matrix3x3f) {
        self.init(rows: Vector4f(matrix[0].x, matrix[1].x, matrix[2].x, 0), Vector4f(matrix[0].y, matrix[1].y, matrix[2].y, 0), Vector4f(matrix[0].z, matrix[1].z, matrix[2].z, 0))
    }
    
    /// Access the `col`th column vector
    @inlinable
    public subscript(col: Int) -> Vector4f {
        get {
            switch col {
            case 0: return Vector4f(r0.x, r1.x, r2.x, 0)
            case 1: return Vector4f(r0.y, r1.y, r2.y, 0)
            case 2: return Vector4f(r0.z, r1.z, r2.z, 0)
            case 3: return Vector4f(r0.w, r1.w, r2.w, 1)
            default: fatalError("Index outside of bounds")
            }
        }
        
        set {
            switch col {
            case 0: self.r0.x = newValue.x; self.r1.x = newValue.y; self.r2.x = newValue.z; assert(newValue.w == 0.0)
            case 1: self.r0.y = newValue.x; self.r1.y = newValue.y; self.r2.y = newValue.z; assert(newValue.w == 0.0)
            case 2: self.r0.z = newValue.x; self.r1.z = newValue.y; self.r2.z = newValue.z; assert(newValue.w == 0.0)
            case 3: self.r0.w = newValue.x; self.r1.w = newValue.y; self.r2.w = newValue.z; assert(newValue.w == 1.0)
            default: fatalError("Index outside of bounds")
            }
        }
    }
    
    /// Access the `col`th column vector and then `row`th element
    @inlinable
    public subscript(col: Int, row: Int) -> Float {
        get {
            switch row {
            case 0:
               return self.r0[col]
            case 1:
                return self.r1[col]
            case 2:
                return self.r2[col]
            case 3:
                return Vector4f(0, 0, 0, 1)[col]
            default: fatalError("Index outside of bounds")
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
            default: fatalError("Index outside of bounds")
            }
        }
    }
    
    @inlinable
    public var inverse : AffineMatrix {
        let scaleRotation = Matrix3x3f(self)
        let scaleRotationInverse = scaleRotation.inverse
        
        let negativeNewRotation = scaleRotationInverse * Vector3f(r0.w, r1.w, r2.w)
        
        return AffineMatrix(rows: Vector4f(scaleRotationInverse[0][0], scaleRotationInverse[1][0], scaleRotationInverse[2][0], -negativeNewRotation.x),
                            Vector4f(scaleRotationInverse[0][1], scaleRotationInverse[1][1], scaleRotationInverse[2][1], -negativeNewRotation.y),
                            Vector4f(scaleRotationInverse[0][2], scaleRotationInverse[1][2], scaleRotationInverse[2][2], -negativeNewRotation.z)
        )
    }
    
    /// Returns the maximum scale along any axis.
    @inlinable
    public var maximumScale : Float {
        let s0 = Vector3f(self.r0.x, self.r1.x, self.r2.x).lengthSquared
        let s1 = Vector3f(self.r0.y, self.r1.y, self.r2.y).lengthSquared
        let s2 = Vector3f(self.r0.z, self.r1.z, self.r2.z).lengthSquared
        
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
    
    public init(quaternion q: Quaternion) {
        self = AffineMatrix.identity
        
        let sqw = q.w*q.w
        let sqx = q.x*q.x
        let sqy = q.y*q.y
        let sqz = q.z*q.z
        
        // invs (inverse square length) is only required if quaternion is not already normalised
        let invs = 1.0 / (sqx + sqy + sqz + sqw)
        self.r0.x = ( sqx - sqy - sqz + sqw)*invs // since sqw + sqx + sqy + sqz =1/invs*invs
        self.r1.y = (-sqx + sqy - sqz + sqw)*invs
        self.r2.z = (-sqx - sqy + sqz + sqw)*invs
        
        var tmp1 = q.x*q.y
        var tmp2 = q.z*q.w
        self.r1.x = 2.0 * (tmp1 + tmp2)*invs
        self.r0.y = 2.0 * (tmp1 - tmp2)*invs
        
        tmp1 = q.x*q.z
        tmp2 = q.y*q.w
        self.r2.x = 2.0 * (tmp1 - tmp2)*invs
        self.r0.z = 2.0 * (tmp1 + tmp2)*invs
        tmp1 = q.y*q.z
        tmp2 = q.x*q.w
        self.r2.y = 2.0 * (tmp1 + tmp2)*invs
        self.r1.z = 2.0 * (tmp1 - tmp2)*invs
    }
}

extension AffineMatrix {

    @inlinable
    public static func *(lhs: AffineMatrix, rhs: AffineMatrix) -> AffineMatrix {
        var r0 = Vector4f()
        r0.x = lhs.r0.x * rhs.r0.x + lhs.r0.y * rhs.r1.x + lhs.r0.z * rhs.r2.x
        r0.y = lhs.r0.x * rhs.r0.y + lhs.r0.y * rhs.r1.y + lhs.r0.z * rhs.r2.y
        r0.z = lhs.r0.x * rhs.r0.z + lhs.r0.y * rhs.r1.z + lhs.r0.z * rhs.r2.z
        r0.w = lhs.r0.x * rhs.r0.w + lhs.r0.y * rhs.r1.w + lhs.r0.z * rhs.r2.w + lhs.r0.w
        
        var r1 = Vector4f()
        r1.x = lhs.r1.x * rhs.r0.x + lhs.r1.y * rhs.r1.x + lhs.r1.z * rhs.r2.x
        r1.y = lhs.r1.x * rhs.r0.y + lhs.r1.y * rhs.r1.y + lhs.r1.z * rhs.r2.y
        r1.z = lhs.r1.x * rhs.r0.z + lhs.r1.y * rhs.r1.z + lhs.r1.z * rhs.r2.z
        r1.w = lhs.r1.x * rhs.r0.w + lhs.r1.y * rhs.r1.w + lhs.r1.z * rhs.r2.w + lhs.r1.w
        
        var r2 = Vector4f()
        r2.x = lhs.r2.x * rhs.r0.x + lhs.r2.y * rhs.r1.x + lhs.r2.z * rhs.r2.x
        r2.y = lhs.r2.x * rhs.r0.y + lhs.r2.y * rhs.r1.y + lhs.r2.z * rhs.r2.y
        r2.z = lhs.r2.x * rhs.r0.z + lhs.r2.y * rhs.r1.z + lhs.r2.z * rhs.r2.z
        r2.w = lhs.r2.x * rhs.r0.w + lhs.r2.y * rhs.r1.w + lhs.r2.z * rhs.r2.w + lhs.r2.w
        
        return AffineMatrix(rows: r0, r1, r2)
    }
    
    @inlinable
    public static func *(lhs: Matrix4x4f, rhs: AffineMatrix) -> Matrix4x4f {
        return lhs * Matrix4x4f(rhs)
    }
    
    @inlinable
    public static func *(lhs: AffineMatrix, rhs: Vector4f) -> Vector4f {
        let x = dot(lhs.r0, rhs)
        let y = dot(lhs.r1, rhs)
        let z = dot(lhs.r2, rhs)
        return Vector4f(x, y, z, rhs.w)
    }
    
    @inlinable
    public static func *(lhs: AffineMatrix, rhs: Vector3f) -> Vector3f {
        let x = dot(lhs.r0.xyz, rhs)
        let y = dot(lhs.r1.xyz, rhs)
        let z = dot(lhs.r2.xyz, rhs)
        return Vector3f(x, y, z)
    }
}

extension Matrix3x3f {
    @inlinable
    public init(_ affineMatrix: AffineMatrix) {
        self.init(Vector3f(affineMatrix.r0.x, affineMatrix.r1.x, affineMatrix.r2.x), Vector3f(affineMatrix.r0.y, affineMatrix.r1.y, affineMatrix.r2.y), Vector3f(affineMatrix.r0.z, affineMatrix.r1.z, affineMatrix.r2.z))
    }
}


extension Matrix4x4f {

    @inlinable
    public init(_ affineMatrix: AffineMatrix) {
        self.init(Vector4f(affineMatrix.r0.x, affineMatrix.r1.x, affineMatrix.r2.x, 0), Vector4f(affineMatrix.r0.y, affineMatrix.r1.y, affineMatrix.r2.y, 0), Vector4f(affineMatrix.r0.z, affineMatrix.r1.z, affineMatrix.r2.z, 0), Vector4f(affineMatrix.r0.w, affineMatrix.r1.w, affineMatrix.r2.w, 1))
    }
}

extension AffineMatrix {
    /// Returns the identity matrix
    public static let identity = AffineMatrix(diagonal: Vector3f(1.0))
    
    //MARK: matrix operations
    
    public static func lookAt(eye: Vector3f, at: Vector3f) -> AffineMatrix {
        return lookAtLH(eye: eye, at: at)
    }
    
    public static func lookAtLH(eye: Vector3f, at: Vector3f) -> AffineMatrix {
        let view = (at - eye).normalized
        return lookAt(eye: eye, view: view)
    }
    
    public static func lookAtLH(eye: Vector3f, at: Vector3f, up: Vector3f) -> AffineMatrix {
        let view = (at - eye).normalized
        return lookAt(eye: eye, view: view, up: up)
    }
    
    static func lookAt(eye: Vector3f, view: Vector3f) -> AffineMatrix {
        var up = vec3(0, 1, 0)
        if abs(dot(up, view)) > 0.99 {
            up = vec3(1, 0, 0)
        }
        
        return self.lookAt(eye: eye, view: view, up: up)
    }
    
    static func lookAt(eye: Vector3f, view: Vector3f, up: Vector3f) -> AffineMatrix {
        
        let right = cross(up, view).normalized
        let u     = cross(view, right)
        
        return AffineMatrix(rows: Vector4f(right, -dot(right, eye)),
                                Vector4f(u, -dot(u, eye)),
                                Vector4f(view, -dot(view, eye))
            )
    }
    
    public static func lookAtInv(eye: Vector3f, at: Vector3f) -> AffineMatrix {
        let view = (at - eye).normalized
        return lookAtInv(eye: eye, view: view)
    }
    
    public static func lookAtInv(eye: Vector3f, at: Vector3f, up: Vector3f) -> AffineMatrix {
        let view = (at - eye).normalized
        return lookAtInv(eye: eye, view: view)
    }
    
    static func lookAtInv(eye: Vector3f, view: Vector3f, up: Vector3f) -> AffineMatrix {
        let right = cross(up, view).normalized
        let u     = cross(view, right)
        
        return AffineMatrix(rows: Vector4f(right.x, u.x, view.x, eye.x),
                            Vector4f(right.y, u.y, view.y, eye.y),
                            Vector4f(right.z, u.z, view.z, eye.z)
            )
    }
    
    static func lookAtInv(eye: Vector3f, view: Vector3f) -> AffineMatrix {
        var up = vec3(0, 1, 0)
        if abs(dot(up, view)) > 0.99 {
            up = vec3(1, 0, 0)
        }
        
        return self.lookAtInv(eye: eye, view: view, up: up)
    }
    
    public static func lookAt(forward: Vector3f) -> AffineMatrix {
        var up = vec3(0, 1, 0)
        if abs(dot(up, forward)) > 0.99 {
            up = vec3(1, 0, 0)
        }
        
        let right = cross(up, forward).normalized
        let u     = cross(forward, right)
        
        return AffineMatrix(rows: Vector4f(right.x, u.x, forward.x, 0),
                            Vector4f(right.y, u.y, forward.y, 0),
                            Vector4f(right.z, u.z, forward.z, 0)
        )
    }
    
    
    //MARK: matrix operations
    
    public static func scale(by s: Vector3f) -> AffineMatrix {
        return AffineMatrix.scale(sx: s.x, sy: s.y, sz: s.z)
    }
    public static func scale(sx: Float, sy: Float, sz: Float) -> AffineMatrix {
        return AffineMatrix(diagonal: Vector3f(sx, sy, sz))
    }
    
    public static func translate(by t: Vector3f) -> AffineMatrix {
        return AffineMatrix.translate(tx: t.x, ty: t.y, tz: t.z)
    }
    
    public static func translate(tx: Float, ty: Float, tz: Float) -> AffineMatrix {
        return AffineMatrix(rows: Vector4f(1, 0, 0, tx), Vector4f(0, 1, 0, ty), Vector4f(0, 0, 1, tz))
    }
    
    
    /// Create a matrix with rotates around the x axis
    ///
    /// - parameter x: angle
    ///
    /// - returns: a new rotation matrix
    public static func rotate(x: Angle) -> AffineMatrix {
        let (sin: sx, cos: cx) = sincos(x)
        
        var r = AffineMatrix()
        r[0, 0] = 1.0
        r[1, 1] = cx
        r[1, 2] = -sx
        r[2, 1] = sx
        r[2, 2] = cx
        
        return r
    }
    
    /// Returns a transformation matrix that rotates around the y axis
    public static func rotate(y: Angle) -> AffineMatrix {
        let (sin: sy, cos: cy) = sincos(y)
        
        var r = AffineMatrix()
        r[0,0] = cy
        r[0,2] = sy
        r[1,1] = 1.0
        r[2,0] = -sy
        r[2,2] = cy
        
        return r
    }
    
    /// Returns a transformation matrix that rotates around the z axis
    public static func rotate(z: Angle) -> AffineMatrix {
        let (sin: sz, cos: cz) = sincos(z)
        
        var r = AffineMatrix()
        r[0,0] = cz
        r[0,1] = -sz
        r[1,0] = sz
        r[1,1] = cz
        r[2,2] = 1.0
        
        return r
    }
    
    /// Returns a transformation matrix that rotates around the x and then y axes
    public static func rotate(x: Angle, y: Angle) -> AffineMatrix {
        let (sin: sx, cos: cx) = sincos(x)
        let (sin: sy, cos: cy) = sincos(y)
        
        return AffineMatrix(rows: Vector4f(cy, sx*sy, -cx*sy, 0.0),
                            Vector4f(0.0, cx, sx, 0.0),
                            Vector4f(sy, -sx * cy, cx * cy, 0.0)
            )
    }
    
    /// Returns a transformation matrix that rotates around the x, y and then z axes
    public static func rotate(x: Angle, y: Angle, z: Angle) -> AffineMatrix {
        let (sin: sx, cos: cx) = sincos(x)
        let (sin: sy, cos: cy) = sincos(y)
        let (sin: sz, cos: cz) = sincos(z)
        
        var r = AffineMatrix()
        r[0,0] = cy*cz
        r[0,1] = -cy*sz
        r[0,2] = sy
        r[1,0] = cz*sx*sy + cx*sz
        r[1,1] = cx*cz - sx*sy*sz
        r[1,2] = -cy*sx
        r[2,0] = -cx*cz*sy + sx*sz
        r[2,1] = cz*sx + cx*sy*sz
        r[2,2] = cx*cy
        
        return r
    }
    
    /// Returns a transformation matrix that rotates around the z, y and then x axes
    public static func rotate(z: Angle, y: Angle, x: Angle) -> AffineMatrix {
        let (sin: sx, cos: cx) = sincos(x)
        let (sin: sy, cos: cy) = sincos(y)
        let (sin: sz, cos: cz) = sincos(z)
        
        var r = AffineMatrix()
        r[0,0] = cy*cz
        r[0,1] = cz*sx*sy-cx*sz
        r[0,2] = cx*cz*sy+sx*sz
        r[1,0] = cy*sz
        r[1,1] = cx*cz + sx*sy*sz
        r[1,2] = -cz*sx + cx*sy*sz
        r[2,0] = -sy
        r[2,1] = cy*sx
        r[2,2] = cx*cy
        
        return r
    }
    
    /// Returns a transformation matrix which can be used to scale, rotate and translate vectors
    public static func scaleRotateTranslate(sx _sx: Float, sy _sy: Float, sz _sz: Float,
                                            ax: Angle, ay: Angle, az: Angle,
                                            tx: Float, ty: Float, tz: Float) -> AffineMatrix {
        let (sin: sx, cos: cx) = sincos(ax)
        let (sin: sy, cos: cy) = sincos(ay)
        let (sin: sz, cos: cz) = sincos(az)
        
        let sxsz = sx*sz
        let cycz = cy*cz
        
        return AffineMatrix(rows:
                            Vector4f(_sx * (cycz - sxsz*sy), _sy * (cz*sx*sy + cy*sz), _sz * -cx*sy, tx),
                            Vector4f(_sx * -cx*sz, _sy * cx*cz, _sz * sx, ty),
                            Vector4f(_sx * (cz*sy + cy*sxsz), _sy * (sy*sz - cycz*sx), cx*cy, tz)
        )
    }
    
    /// Returns a transformation matrix which can be used to scale, rotate and translate vectors
    public static func scaleRotateTranslate(scale: Vector3f,
                                            rotation: Quaternion,
                                            translation: Vector3f) -> AffineMatrix {
        
        let sqw = rotation.w * rotation.w
        let sqx = rotation.x * rotation.x
        let sqy = rotation.y * rotation.y
        let sqz = rotation.z * rotation.z
        
        var r0 = Vector4f(0)
        var r1 = Vector4f(0)
        var r2 = Vector4f(0)
        
        // invs (inverse square length) is only required if quaternion is not already normalised
        let invs = 1.0 / (sqx + sqy + sqz + sqw)
        r0.x = ( sqx - sqy - sqz + sqw) * invs * scale.x // since sqw + sqx + sqy + sqz =1/invs*invs
        r1.y = (-sqx + sqy - sqz + sqw) * invs * scale.y
        r2.z = (-sqx - sqy + sqz + sqw) * invs * scale.z
        
        var tmp1 = rotation.x * rotation.y
        var tmp2 = rotation.z * rotation.w
        r1.x = 2.0 * (tmp1 + tmp2) * invs * scale.x
        r0.y = 2.0 * (tmp1 - tmp2) * invs * scale.y
        
        tmp1 = rotation.x * rotation.z
        tmp2 = rotation.y * rotation.w
        r2.x = 2.0 * (tmp1 - tmp2) * invs * scale.x
        r0.z = 2.0 * (tmp1 + tmp2) * invs * scale.z
        tmp1 = rotation.y * rotation.z
        tmp2 = rotation.x * rotation.w
        r2.y = 2.0 * (tmp1 + tmp2) * invs * scale.y
        r1.z = 2.0 * (tmp1 - tmp2) * invs * scale.z
        
        r0.w = translation.x
        r1.w = translation.y
        r2.w = translation.z
        
        return AffineMatrix(rows: r0, r1, r2)
    }
    
    public var decomposed : (translation: Vector3f, rotation: Quaternion, scale: Vector3f) {
        var currentTransform = self
        let translation = currentTransform[3].xyz
        
        currentTransform[3] = vec4(0, 0, 0, 1)
        var scale = vec3(currentTransform[0].xyz.length, currentTransform[1].xyz.length, currentTransform[2].xyz.length)
        
        let tempZ = cross(currentTransform[0].xyz, currentTransform[1].xyz)
        if dot(tempZ, currentTransform[2].xyz) < 0 {
            scale.x *= -1
        }
        
        currentTransform[0] /= scale.x
        currentTransform[1] /= scale.y
        currentTransform[2] /= scale.z
        
        let rotation = quat(currentTransform)
        return (translation, rotation, scale)
    }
}

extension AffineMatrix {
    
    @inlinable
    public var worldSpaceRight : Vector3f {
        return Vector3f(r0.x, r1.x, r2.x).normalized
    }
    
    @inlinable
    public var worldSpaceUp : Vector3f {
        return Vector3f(r0.y, r1.y, r2.y).normalized
    }
    
    @inlinable
    public var worldSpaceForward : Vector3f {
        return Vector3f(r0.z, r1.z, r2.z).normalized
    }
    
    @inlinable
    public var worldSpaceTranslation : Vector4f {
        get {
            return Vector4f(r0.w, r1.w, r2.w, 1.0)
        }
        set {
            self.r0.w = newValue.x
            self.r1.w = newValue.y
            self.r2.w = newValue.z
            assert(newValue.w == 1.0)
        }
    }
}

