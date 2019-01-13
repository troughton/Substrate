// Copyright 2016 Stuart Carnie.
// License: https://github.com/SwiftGFX/SwiftMath#license-bsd-2-clause
//

#if !NOSIMD
    import simd
#endif

extension Matrix4x4f {
    /// Returns the identity matrix
    public static let identity = Matrix4x4f(diagonal: vec4(1.0))
    
    //MARK: matrix operations
    
    public static func lookAt(eye: Vector3f, at: Vector3f) -> Matrix4x4f {
        return lookAtLH(eye: eye, at: at)
    }
    
    public static func lookAtLH(eye: Vector3f, at: Vector3f) -> Matrix4x4f {
        let view = (at - eye).normalized
        return lookAt(eye: eye, view: view)
    }
    
    public static func lookAtLH(eye: Vector3f, at: Vector3f, up: Vector3f) -> Matrix4x4f {
        let view = (at - eye).normalized
        return lookAt(eye: eye, view: view, up: up)
    }
    
    static func lookAt(eye: Vector3f, view: Vector3f) -> Matrix4x4f {
        var up = vec3(0, 1, 0)
        if abs(dot(up, view)) > 0.99 {
            up = vec3(1, 0, 0)
        }
        
        return self.lookAt(eye: eye, view: view, up: up)
    }
    
    static func lookAt(eye: Vector3f, view: Vector3f, up: Vector3f) -> Matrix4x4f {
        
        let right = cross(up, view).normalized
        let u     = cross(view, right)
        
        return Matrix4x4f(
            vec4(right[0],        u[0],        view[0],        0.0),
            vec4(right[1],        u[1],        view[1],        0.0),
            vec4(right[2],        u[2],        view[2],        0.0),
            vec4(-dot(right, eye), -dot(u, eye), -dot(view, eye), 1.0)
        )
    }
    
    public static func lookAtInv(eye: Vector3f, at: Vector3f) -> Matrix4x4f {
        let view = (at - eye).normalized
        return lookAtInv(eye: eye, view: view)
    }
    
    public static func lookAtInv(eye: Vector3f, at: Vector3f, up: Vector3f) -> Matrix4x4f {
        let view = (at - eye).normalized
        return lookAtInv(eye: eye, view: view)
    }
    
    static func lookAtInv(eye: Vector3f, view: Vector3f, up: Vector3f) -> Matrix4x4f {
        let right = cross(up, view).normalized
        let u     = cross(view, right)
        
        return Matrix4x4f(
            vec4(right[0],          right[1],           right[2],        0.0),
            vec4(u[0],              u[1],               u[2],            0.0),
            vec4(view[0],           view[1],            view[2],         0.0),
            vec4(eye, 1.0)
        )
    }
    
    static func lookAtInv(eye: Vector3f, view: Vector3f) -> Matrix4x4f {
        var up = vec3(0, 1, 0)
        if abs(dot(up, view)) > 0.99 {
            up = vec3(1, 0, 0)
        }
        
        return self.lookAtInv(eye: eye, view: view, up: up)
    }
    
    public static func lookAt(forward: Vector3f) -> Matrix4x4f {
        var up = vec3(0, 1, 0)
        if abs(dot(up, forward)) > 0.99 {
            up = vec3(1, 0, 0)
        }
        
        let right = cross(up, forward).normalized
        let u     = cross(forward, right)
        
        return Matrix4x4f(
            vec4(right[0],          right[1],           right[2],        0.0),
            vec4(u[0],              u[1],               u[2],            0.0),
            vec4(forward[0],        forward[1],         forward[2],      0.0),
            vec4(0.0,               0.0,                0.0,             1.0)
        )
    }
    
    
    /// Creates a left-handed perspective projection matrix
    public static func proj(fovy: Angle, aspect: Float, near: Float, far: Float) -> Matrix4x4f {
        let height = 1.0 / tan(fovy * 0.5)
        let width  = height * 1.0/aspect;
        return projLH(x: 0, y: 0, w: width, h: height, near: near, far: far)
    }
    
    /// Creates a left-handed perspective projection matrix
    public static func projLH(x: Float, y: Float, w: Float, h: Float, near: Float, far: Float) -> Matrix4x4f {
        let diff = far - near
        let aa   = far / diff
        let bb   = near * aa
        
        var r = Matrix4x4f()
        r[0,0] = w
        r[1,1] = h
        r[2,0] = -x
        r[2,1] = -y
        r[2,2] = aa
        r[2,3] = 1.0
        r[3,2] = -bb
        
        return r
    }
    
    /// Creates a right-handed perspective projection matrix
    public static func projRH(x: Float, y: Float, w: Float, h: Float, near: Float, far: Float) -> Matrix4x4f {
        let diff = far - near
        let aa   = far / diff
        let bb   = near * aa
        
        var r = Matrix4x4f()
        r[0,0] = w
        r[1,1] = h
        r[2,0] = x
        r[2,1] = y
        r[2,2] = -aa
        r[2,3] = -1.0
        r[3,2] = -bb
        
        return r
    }
    
    /// Creates a left-handed orthographic projection matrix
    public static func ortho(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> Matrix4x4f {
        return orthoLH(left: left, right: right, bottom: bottom, top: top, near: near, far: far)
    }
    
    /// Creates a left-handed orthographic projection matrix
    public static func orthoLH(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float, offset: Float = 0.0) -> Matrix4x4f {
        let aa = 2.0 / (right - left)
        let bb = 2.0 / (top - bottom)
        let cc = 1.0 / (far - near)
        let dd = (left + right) / (left - right)
        let ee = (top + bottom) / (bottom - top)
        let ff = near / (near - far)
        
        var r = Matrix4x4f()
        r[0,0] = aa
        r[1,1] = bb
        r[2,2] = cc
        r[3,0] = dd + offset
        r[3,1] = ee
        r[3,2] = ff
        r[3,3] = 1.0
        
        return r
    }
    
    /// Creates a right-handed orthographic projection matrix
    public static func orthoRH(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float, offset: Float = 0.0) -> Matrix4x4f {
        let aa = 2.0 / (right - left)
        let bb = 2.0 / (top - bottom)
        let cc = 1.0 / (far - near)
        let dd = (left + right) / (left - right)
        let ee = (top + bottom) / (bottom - top)
        let ff = near / (near - far)
        
        var r = Matrix4x4f()
        r[0,0] = aa
        r[1,1] = bb
        r[2,2] = -cc
        r[3,0] = dd + offset
        r[3,1] = ee
        r[3,2] = ff
        r[3,3] = 1.0
        
        return r
    }
    
    //MARK: matrix operations
    
    public static func scale(by s: Vector3f) -> Matrix4x4f {
        return Matrix4x4f.scale(sx: s.x, sy: s.y, sz: s.z)
    }
    public static func scale(sx: Float, sy: Float, sz: Float) -> Matrix4x4f {
        return Matrix4x4f(diagonal: vec4(sx, sy, sz, 1.0))
    }
    
    public static func translate(by t: Vector3f) -> Matrix4x4f {
        return Matrix4x4f.translate(tx: t.x, ty: t.y, tz: t.z)
    }
    
    public static func translate(tx: Float, ty: Float, tz: Float) -> Matrix4x4f {
        return Matrix4x4f(
            vec4(1.0, 0.0, 0.0, 0.0),
            vec4(0.0, 1.0, 0.0, 0.0),
            vec4(0.0, 0.0, 1.0, 0.0),
            vec4(tx,  ty,  tz,  1.0)
        )
    }
    
    
    /// Create a matrix with rotates around the x axis
    ///
    /// - parameter x: angle
    ///
    /// - returns: a new rotation matrix
    public static func rotate(x: Angle) -> Matrix4x4f {
        let (sin: sx, cos: cx) = sincos(x)
        
        var r = Matrix4x4f()
        r[0,0] = 1.0
        r[1,1] = cx
        r[1,2] = -sx
        r[2,1] = sx
        r[2,2] = cx
        r[3,3] = 1.0
        
        return r
    }
    
	/// Returns a transformation matrix that rotates around the y axis
    public static func rotate(y: Angle) -> Matrix4x4f {
        let (sin: sy, cos: cy) = sincos(y)
        
        var r = Matrix4x4f()
        r[0,0] = cy
        r[0,2] = sy
        r[1,1] = 1.0
        r[2,0] = -sy
        r[2,2] = cy
        r[3,3] = 1.0
        
        return r
    }
    
    /// Returns a transformation matrix that rotates around the z axis
    public static func rotate(z: Angle) -> Matrix4x4f {
        let (sin: sz, cos: cz) = sincos(z)
        
        var r = Matrix4x4f()
        r[0,0] = cz
        r[0,1] = -sz
        r[1,0] = sz
        r[1,1] = cz
        r[2,2] = 1.0
        r[3,3] = 1.0
        
        return r
    }
    
    /// Returns a transformation matrix that rotates around the x and then y axes
    public static func rotate(x: Angle, y: Angle) -> Matrix4x4f {
        let (sin: sx, cos: cx) = sincos(x)
        let (sin: sy, cos: cy) = sincos(y)
        
        return Matrix4x4f(
            vec4(cy,     0.0, sy,     0.0),
            vec4(sx*sy,  cx,  -sx*cy, 0.0),
            vec4(-cx*sy, sx,  cx*cy,  0.0),
            vec4(0.0,    0.0, 0.0,    1.0)
        )
    }
    
	/// Returns a transformation matrix that rotates around the x, y and then z axes
    public static func rotate(x: Angle, y: Angle, z: Angle) -> Matrix4x4f {
        let (sin: sx, cos: cx) = sincos(x)
        let (sin: sy, cos: cy) = sincos(y)
        let (sin: sz, cos: cz) = sincos(z)
        
        var r = Matrix4x4f()
        r[0,0] = cy*cz
        r[0,1] = -cy*sz
        r[0,2] = sy
        r[1,0] = cz*sx*sy + cx*sz
        r[1,1] = cx*cz - sx*sy*sz
        r[1,2] = -cy*sx
        r[2,0] = -cx*cz*sy + sx*sz
        r[2,1] = cz*sx + cx*sy*sz
        r[2,2] = cx*cy
        r[3,3] = 1.0
        
        return r
    }
	
	/// Returns a transformation matrix that rotates around the z, y and then x axes
    public static func rotate(z: Angle, y: Angle, x: Angle) -> Matrix4x4f {
        let (sin: sx, cos: cx) = sincos(x)
        let (sin: sy, cos: cy) = sincos(y)
        let (sin: sz, cos: cz) = sincos(z)
        
        var r = Matrix4x4f()
        r[0,0] = cy*cz
        r[0,1] = cz*sx*sy-cx*sz
        r[0,2] = cx*cz*sy+sx*sz
        r[1,0] = cy*sz
        r[1,1] = cx*cz + sx*sy*sz
        r[1,2] = -cz*sx + cx*sy*sz
        r[2,0] = -sy
        r[2,1] = cy*sx
        r[2,2] = cx*cy
        r[3,3] = 1.0
        
        return r
    }
    
    /// Returns a transformation matrix which can be used to scale, rotate and translate vectors
    public static func scaleRotateTranslate(sx _sx: Float, sy _sy: Float, sz _sz: Float,
                                            ax: Angle, ay: Angle, az: Angle,
                                            tx: Float, ty: Float, tz: Float) -> Matrix4x4f {
        let (sin: sx, cos: cx) = sincos(ax)
        let (sin: sy, cos: cy) = sincos(ay)
        let (sin: sz, cos: cz) = sincos(az)
        
        let sxsz = sx*sz
        let cycz = cy*cz
        
        return Matrix4x4f(
            vec4(_sx * (cycz - sxsz*sy),   _sx * -cx*sz, _sx * (cz*sy + cy*sxsz), 0.0),
            vec4(_sy * (cz*sx*sy + cy*sz), _sy * cx*cz,  _sy * (sy*sz - cycz*sx), 0.0),
            vec4(_sz * -cx*sy,             _sz * sx,     cx*cy,                   0.0),
            vec4(tx,                       ty,           tz,                      1.0)
        )
    }
    
    /// Returns a transformation matrix which can be used to scale, rotate and translate vectors
    public static func scaleRotateTranslate(scale: Vector3f,
                                            rotation: Quaternion,
                                            translation: Vector3f) -> Matrix4x4f {
        let scale = Matrix4x4f.scale(sx: scale.x, sy: scale.y, sz: scale.z)
        let rotation = Matrix4x4f(quaternion: rotation)
        let translation = Matrix4x4f.translate(tx: translation.x, ty: translation.y, tz: translation.z)
        return translation * rotation * scale
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

extension Matrix4x4f: CustomStringConvertible {
    /// Displays the matrix in row-major order
    public var description: String {
        return "Matrix4x4f(\n" +
            "m00: \(self[0,0]), m01: \(self[1,0]), m02: \(self[2,0]), m03: \(self[3,0]),\n" +
            "m10: \(self[0,1]), m11: \(self[1,1]), m12: \(self[2,1]), m13: \(self[3,1]),\n" +
            "m20: \(self[0,2]), m21: \(self[1,2]), m22: \(self[2,2]), m23: \(self[3,2]),\n" +
            "m30: \(self[0,3]), m31: \(self[1,3]), m32: \(self[2,3]), m33: \(self[3,3]),\n" +
        ")"
    }
}

extension Matrix4x4f : CustomDebugStringConvertible {
    public var debugDescription : String {
        return self.description
    }
}

extension Matrix4x4f {
    
    @inlinable
    public var worldSpaceRight : Vector3f {
        return self[0].xyz.normalized
    }
    
    @inlinable
    public var worldSpaceUp : Vector3f {
        return self[1].xyz.normalized
    }
    
    @inlinable
    public var worldSpaceForward : Vector3f {
        return self[2].xyz.normalized
    }
    
    @inlinable
    public var worldSpaceTranslation : Vector4f {
        get {
            return self[3]
        }
        set {
            self[3] = newValue
        }
    }
}

