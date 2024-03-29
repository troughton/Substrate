//
//  Quaternion.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 10/01/17.
//
//

import RealModule

public struct Quaternion<Scalar : SIMDScalar & BinaryFloatingPoint & Real>: Hashable {
    @inlinable
    public static var identity : Quaternion { return Quaternion(0, 0, 0, 1) }
    
    public var storage : SIMD4<Scalar>
    
    @inlinable
    public init(_ x: Scalar, _ y: Scalar, _ z: Scalar, _ w: Scalar) {
        self.storage = SIMD4(x, y, z, w)
    }
    
    @inlinable
    public init(_ storage: SIMD4<Scalar>) {
        self.storage = storage
    }
    
    @inlinable
    public init<Other>(_ other: Quaternion<Other>) {
        self.storage = .init(other.storage)
    }
    
    @inlinable
    public init(angle: Angle<Scalar>, axis: SIMD3<Scalar>) {
        let halfAngle = -angle.radians * 0.5
        
        let scale = Scalar.sin(halfAngle)
        let w = Scalar.cos(halfAngle)
        
        self = Quaternion(scale * axis.x, scale * axis.y, scale * axis.z, w)
    }
    
    // The euler angles represent a rotation around Y, then around X', then around Z'.
    @inlinable
    public init(eulerAngles: SIMD3<Scalar>) {
        let yaw = eulerAngles.y
        let pitch = -eulerAngles.x
        let roll = -eulerAngles.z
        
        let cy = Scalar.cos(yaw * 0.5)
        let sy = Scalar.sin(yaw * 0.5)
        let cp = Scalar.cos(pitch * 0.5)
        let sp = Scalar.sin(pitch * 0.5)
        let cr = Scalar.cos(roll * 0.5)
        let sr = Scalar.sin(roll * 0.5)
        
        let x: Scalar = cr * sp * cy + sr * cp * sy
        let y: Scalar = sr * sp * cy - cr * cp * sy
        let z: Scalar = sr * cp * cy - cr * sp * sy
        let w: Scalar = cr * cp * cy + sr * sp * sy
        self.init(x, y, z, w)
    }
    
    @inlinable
    public var x : Scalar {
        get {
            return self.storage.x
        }
        set {
            self.storage.x = newValue
        }
    }
    
    @inlinable
    public var y : Scalar {
        get {
            return self.storage.y
        }
        set {
            self.storage.y = newValue
        }
    }
    
    @inlinable
    public var z : Scalar {
        get {
            return self.storage.z
        }
        set {
            self.storage.z = newValue
        }
    }
    
    @inlinable
    public var w : Scalar {
        get {
            return self.storage.w
        }
        set {
            self.storage.w = newValue
        }
    }
    
    @inlinable
    public var s : Scalar {
        get {
            return self.storage.w
        }
        set {
            self.storage.w = newValue
        }
    }
    
    
    @inlinable
    public var v : SIMD3<Scalar> {
        get {
            return self.storage.xyz
        }
        set {
            self.storage.xyz = newValue
        }
    }
    
    /// Applied as rotation around Y (heading), then around X' (attitude), then around Z' (bank).
    /// Assumes a left-handed coordinate system with X to the right, Y up, and Z forward.
    @inlinable
    public var eulerAngles : SIMD3<Scalar> {
        get {
            return SIMD3<Scalar>(self.pitch, self.yaw, self.roll)
        }
        set(newValue) {
            self = Quaternion(eulerAngles: newValue)
        }
    }
    
    /// The roll is the rotation around the positive Z axis, and is applied third.
    @inlinable
    public var roll : Scalar {
        let sinRCosP : Scalar = 2.0 * (self.w * self.z as Scalar - self.x * self.y as Scalar)
        let cosRCosP : Scalar = 1.0 - 2.0 * (self.x * self.x as Scalar + self.z * self.z as Scalar) as Scalar
        return -Scalar.atan2(y: sinRCosP, x: cosRCosP)
    }
    
    /// The pitch is the rotation around the positive X axis, and is applied second.
    @inlinable
    public var pitch : Scalar {
        let sinP : Scalar = 2.0 * (self.w * self.x as Scalar + self.y * self.z as Scalar)
        return -Scalar.asin(clamp(sinP, min: -1 as Scalar, max: 1 as Scalar))
    }
    
    /// The yaw is the rotation around the positive Y axis, and is applied first.
    @inlinable
    public var yaw : Scalar {
        let sinYCosP: Scalar = 2.0 * (self.x * self.z as Scalar - self.w * self.y as Scalar)
        let cosYCosP: Scalar = 1.0 - 2.0 * (self.x * self.x as Scalar + self.y * self.y as Scalar)
        return Scalar.atan2(y: sinYCosP, x: cosYCosP)
    }
    
    @inlinable
    public static func *(q1: Quaternion, q2: Quaternion) -> Quaternion {
        var result = SIMD4<Scalar>(q1.x, -q1.x, q1.x, -q1.x) * SIMD4<Scalar>(q2.w, q2.z, q2.y, q2.x)
        result.addProduct(SIMD4(q1.y, q1.y, -q1.y, -q1.y), SIMD4<Scalar>(q2.z, q2.w, q2.x, q2.y))
        result.addProduct(SIMD4(-q1.z, q1.z, q1.z, -q1.z), SIMD4<Scalar>(q2.y, q2.x, q2.w, q2.z))
        result.addProduct(SIMD4(repeating: q1.w), SIMD4<Scalar>(q2.x, q2.y, q2.z, q2.w))
        return Quaternion(result.x, result.y, result.z, result.w)
    }
    
    @inlinable
    public static func *=(lhs: inout Quaternion, rhs: Quaternion) {
        lhs = lhs * rhs
    }
    
    @inlinable
    public static func *(lhs: Quaternion, rhs: Scalar) -> Quaternion {
        return Quaternion(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs, lhs.w * rhs)
    }
    
    @inlinable
    public static func *=(lhs: inout Quaternion, rhs: Scalar) {
        lhs.x *= rhs
        lhs.y *= rhs
        lhs.z *= rhs
        lhs.w *= rhs
    }
    
    @inlinable
    public static func ==(lhs: Quaternion, rhs: Quaternion) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z && lhs.w == rhs.w
    }
    
    @inlinable
    public var normalized : Quaternion {
        return Quaternion.normalize(self)
    }
    
    @inlinable
    public var lengthSquared : Scalar {
        return Quaternion.dot(self, self)
    }
    
    @inlinable
    public var length : Scalar {
        return Scalar.sqrt(self.lengthSquared)
    }
    
    @inlinable
    public var conjugate : Quaternion {
        get {
            return Quaternion(-self.x, -self.y, -self.z, self.w)
        } set {
            self = Quaternion(-newValue.x, -newValue.y, -newValue.z, newValue.w)
        }
    }
    
    @inlinable
    public var inverse : Quaternion {
        get {
            let lengthSquared = self.lengthSquared
            let scale = 1.0 / lengthSquared
            return self.conjugate * scale
        } set {
            self = newValue.inverse
        }
    }
}

extension Quaternion: @unchecked Sendable where Scalar: Sendable {}

extension Matrix4x4 where Scalar : Real {
    
    @inlinable
    public init(_ q: Quaternion<Scalar>) {
        self.init(quaternion: q)
    }
    
    @inlinable
    public init(quaternion q: Quaternion<Scalar>) {
        self = Matrix4x4<Scalar>.identity
        
        let sqw : Scalar = q.w*q.w
        let sqx : Scalar = q.x*q.x
        let sqy : Scalar = q.y*q.y
        let sqz : Scalar = q.z*q.z
        
        // invs (inverse square length) is only required if quaternion is not already normalised
        let invs : Scalar = 1.0 / (sqx + sqy + sqz + sqw)
        self[0, 0] = ( sqx - sqy - sqz + sqw)*invs // since sqw + sqx + sqy + sqz =1/invs*invs
        self[1, 1] = (-sqx + sqy - sqz + sqw)*invs
        self[2, 2] = (-sqx - sqy + sqz + sqw)*invs
        
        var tmp1 : Scalar = q.x*q.y
        var tmp2 : Scalar = q.z*q.w
        self[1, 0] = 2.0 * (tmp1 + tmp2)*invs
        self[0, 1] = 2.0 * (tmp1 - tmp2)*invs
        
        tmp1 = q.x*q.z
        tmp2 = q.y*q.w
        self[2, 0] = 2.0 * (tmp1 - tmp2)*invs
        self[0, 2] = 2.0 * (tmp1 + tmp2)*invs
        tmp1 = q.y*q.z
        tmp2 = q.x*q.w
        self[2, 1] = 2.0 * (tmp1 + tmp2)*invs
        self[1, 2] = 2.0 * (tmp1 - tmp2)*invs
    }
}

extension Quaternion {
    
    @inlinable
    public static func *(lhs: Matrix4x4<Scalar>, rhs: Quaternion) -> Matrix4x4<Scalar> {
        return lhs * Matrix4x4<Scalar>(quaternion: rhs)
    }
    
    @inlinable
    public static func *(lhs: Quaternion, rhs: Matrix4x4<Scalar>) -> Matrix4x4<Scalar> {
        return Matrix4x4<Scalar>(quaternion: lhs) * rhs
    }
    
    @inlinable
    public static func *(lhs: Matrix3x3<Scalar>, rhs: Quaternion) -> Matrix3x3<Scalar> {
        return lhs * Matrix3x3<Scalar>(quaternion: rhs)
    }
    
    @inlinable
    public static func *(lhs: Quaternion, rhs: Matrix3x3<Scalar>) -> Matrix3x3<Scalar> {
        return Matrix3x3<Scalar>(quaternion: lhs) * rhs
    }
    
    @inlinable
    public static func *(lhs: AffineMatrix<Scalar>, rhs: Quaternion) -> AffineMatrix<Scalar> {
        return lhs * AffineMatrix(quaternion: rhs)
    }
    
    @inlinable
    public static func *(lhs: Quaternion, rhs: AffineMatrix<Scalar>) -> AffineMatrix<Scalar> {
        return AffineMatrix(quaternion: lhs) * rhs
    }
}


extension Quaternion {
    @inlinable
    public static func dot(_ u: Quaternion<Scalar>, _ v: Quaternion<Scalar>) -> Scalar {
        return SubstrateMath.dot(u.storage, v.storage)
    }
    
    @inlinable
    public static func normalize(_ x: Quaternion<Scalar>) -> Quaternion<Scalar> {
        //http://stackoverflow.com/questions/11667783/quaternion-and-normalization
        let qmagsq = dot(x, x)
        
        return x * (1.0 / qmagsq.squareRoot())
    }
    
    @inlinable
    public static func slerp(from: Quaternion<Scalar>, to: Quaternion<Scalar>, factor t: Scalar) -> Quaternion<Scalar> {
        // Calculate angle between them.
        var cosHalfTheta : Scalar = dot(from, to)
        var to = to
        
        // if this == other or this == -other then theta = 0 and we can return this
        if (abs(cosHalfTheta) >= 1.0) {
            return from;
        }
        
        if cosHalfTheta < 0 {
            // Ensure we take the shortest path
            cosHalfTheta = -cosHalfTheta
            to = Quaternion(-to.storage)
        }
        
        // Calculate temporary values.
        let halfTheta : Scalar = Scalar.acos(cosHalfTheta)
        let sinHalfTheta : Scalar = Scalar.sin(halfTheta)
        
        if abs(halfTheta) < Scalar.ulpOfOne {
            // As theta goes to zero, sin(factor * theta) / sin(theta) goes to factor.
            return Quaternion(interpolate(from: from.storage, to: to.storage, factor: t))
        } else if (abs(sinHalfTheta) < 0.001){
            // if theta = 180 degrees then result is not fully defined
            // we could rotate around any axis normal to qa or qb
            return Quaternion(0.5 * (from.storage + to.storage))
        } else {
            let ratioA = Scalar.sin((1 - t) * halfTheta) / sinHalfTheta
            let ratioB = Scalar.sin(t * halfTheta) / sinHalfTheta
            
            return Quaternion(from.storage * ratioA + to.storage * ratioB)
        }
    }
}

@inlinable
public func normalize<Scalar>(_ x: Quaternion<Scalar>) -> Quaternion<Scalar> {
    return Quaternion.normalize(x)
}

@inlinable
public func dot<Scalar>(_ u: Quaternion<Scalar>, _ v: Quaternion<Scalar>) -> Scalar {
    return Quaternion.dot(u, v)
}

@inlinable
public func slerp<Scalar>(from: Quaternion<Scalar>, to: Quaternion<Scalar>, factor t: Scalar) -> Quaternion<Scalar> {
    return Quaternion.slerp(from: from, to: to, factor: t)
}


///MARK: Quaternion extensions

extension Quaternion {
    @inlinable
    public init(_ m: Matrix4x4<Scalar>) {
        var n4 : Scalar; // the norm of quaternion multiplied by 4
        var tr = m[0][0]
        tr += m[1][1]
        tr += m[2][2]; // trace of matrix
        
        let condition1 = m[0][0] > m[1][1]
        let condition2 = m[0][0] > m[2][2]
        if (tr > 0.0){
            let x = m[1][2] - m[2][1]
            let y = m[2][0] - m[0][2]
            let z = m[0][1] - m[1][0]
            let w = tr + 1.0
            self = Quaternion(x, y, z, w);
            n4 = self.w;
            
        } else if condition1 && condition2 {
            var x = 1.0 + m[0][0]
            x -= m[1][1]
            x -= m[2][2]
            let y = m[1][0] + m[0][1]
            let z = m[2][0] + m[0][2]
            let w = m[1][2] - m[2][1]
            self = Quaternion(x, y, z, w);
            n4 = self.x;
        } else if ( m[1][1] > m[2][2] ){
            let x = m[1][0] + m[0][1]
            var y = 1.0 + m[1][1]
            y -= m[0][0]
            y -= m[2][2]
            let z = m[2][1] + m[1][2]
            let w = m[2][0] - m[0][2]
            self = Quaternion( x, y, z, w );
            n4 = self.y;
        } else {
            let x = m[2][0] + m[0][2]
            let y = m[2][1] + m[1][2]
            var z = 1.0 + m[2][2]
            z -= m[0][0]
            z -= m[1][1]
            let w = m[0][1] - m[1][0]
            
            self = Quaternion(x, y, z, w);
            n4 = self.z;
        }
        
        n4 = n4.squareRoot()
        
        self *= 0.5 / n4
    }
    
    @inlinable
    public init(_ m: Matrix3x3<Scalar>) {
        var n4 : Scalar; // the norm of quaternion multiplied by 4
        var tr = m[0][0]
        tr += m[1][1]
        tr += m[2][2]; // trace of matrix
        
        let condition1 = m[0][0] > m[1][1]
        let condition2 = m[0][0] > m[2][2]
        if (tr > 0.0){
            let x = m[1][2] - m[2][1]
            let y = m[2][0] - m[0][2]
            let z = m[0][1] - m[1][0]
            let w = tr + 1.0
            self = Quaternion(x, y, z, w);
            n4 = self.w;
            
        } else if condition1 && condition2 {
            var x = 1.0 + m[0][0]
            x -= m[1][1]
            x -= m[2][2]
            let y = m[1][0] + m[0][1]
            let z = m[2][0] + m[0][2]
            let w = m[1][2] - m[2][1]
            self = Quaternion(x, y, z, w);
            n4 = self.x;
        } else if ( m[1][1] > m[2][2] ){
            let x = m[1][0] + m[0][1]
            var y = 1.0 + m[1][1]
            y -= m[0][0]
            y -= m[2][2]
            let z = m[2][1] + m[1][2]
            let w = m[2][0] - m[0][2]
            self = Quaternion( x, y, z, w );
            n4 = self.y;
        } else {
            let x = m[2][0] + m[0][2]
            let y = m[2][1] + m[1][2]
            var z = 1.0 + m[2][2]
            z -= m[0][0]
            z -= m[1][1]
            let w = m[0][1] - m[1][0]
            
            self = Quaternion(x, y, z, w);
            n4 = self.z;
        }
        
        n4 = n4.squareRoot()
        
        self *= 0.5 / n4
    }
    
    @inlinable
    public init(_ m: AffineMatrix<Scalar>) {
        var n4 : Scalar; // the norm of quaternion multiplied by 4
        var tr = m[0][0]
        tr += m[1][1]
        tr += m[2][2]; // trace of matrix
        
        let condition1 = m[0][0] > m[1][1]
        let condition2 = m[0][0] > m[2][2]
        if (tr > 0.0){
            let x = m[1][2] - m[2][1]
            let y = m[2][0] - m[0][2]
            let z = m[0][1] - m[1][0]
            let w = tr + 1.0
            self = Quaternion(x, y, z, w);
            n4 = self.w;
            
        } else if condition1 && condition2 {
            var x = 1.0 + m[0][0]
            x -= m[1][1]
            x -= m[2][2]
            let y = m[1][0] + m[0][1]
            let z = m[2][0] + m[0][2]
            let w = m[1][2] - m[2][1]
            self = Quaternion(x, y, z, w);
            n4 = self.x;
        } else if ( m[1][1] > m[2][2] ){
            let x = m[1][0] + m[0][1]
            var y = 1.0 + m[1][1]
            y -= m[0][0]
            y -= m[2][2]
            let z = m[2][1] + m[1][2]
            let w = m[2][0] - m[0][2]
            self = Quaternion( x, y, z, w );
            n4 = self.y;
        } else {
            let x = m[2][0] + m[0][2]
            let y = m[2][1] + m[1][2]
            var z = 1.0 + m[2][2]
            z -= m[0][0]
            z -= m[1][1]
            let w = m[0][1] - m[1][0]
            
            self = Quaternion(x, y, z, w);
            n4 = self.z;
        }
        
        n4 = n4.squareRoot()
        
        self *= 0.5 / n4
    }
}


extension Quaternion : Codable {
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.x)
        try container.encode(self.y)
        try container.encode(self.z)
        try container.encode(self.w)
    }
    
    @inlinable
    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        let x = try values.decode(Scalar.self)
        let y = try values.decode(Scalar.self)
        let z = try values.decode(Scalar.self)
        let w = try values.decode(Scalar.self)
        
        self.init(x, y, z, w)
    }
}
