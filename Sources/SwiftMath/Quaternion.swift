//
//  File.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 10/01/17.
//
//

import Foundation

public typealias quat = Quaternion

@_fixed_layout
public struct Quaternion : Equatable {
    public static let identity = Quaternion(0, 0, 0, 1)
    
    public var x: Float
    public var y: Float
    public var z: Float
    public var w: Float
    
    @inlinable
    public init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
    
    @inlinable
    public init(angle: Angle, axis: Vector3f) {
        let halfAngle = -angle.radians * 0.5
        
        let scale = sin(halfAngle)
        let w = cos(halfAngle)
        
        self = Quaternion(scale * axis.x, scale * axis.y, scale * axis.z, w)
    }
    
    @inlinable
    public init(eulerAngles: Vector3f) {
        let (heading, altitude, bank) = (eulerAngles.y, eulerAngles.z, eulerAngles.x)
        
        let c1 = cos(heading * 0.5);
        let c2 = cos(altitude * 0.5);
        let c3 = cos(bank * 0.5);
        let s1 = sin(heading * 0.5);
        let s2 = sin(altitude * 0.5);
        let s3 = sin(bank * 0.5);
        
        let w = c1 * c2 * c3 - s1 * s2 * s3
        let x = s1 * s2 * c3 + c1 * c2 * s3
        let y = s1 * c2 * c3 + c1 * s2 * s3
        let z = c1 * s2 * c3 - s1 * c2 * s3
        
        self = Quaternion(x, y, z, w)
    }
    
    
    @inlinable
    public var eulerAngles : Vector3f {
        get {
            let qx2 = self.x * self.x
            let qy2 = self.y * self.y
            let qz2 = self.z * self.z
            let test = self.x * self.y + self.z * self.w
            if (test > 0.499) {
                return Vector3f(0, 2.0 * atan2(self.x, self.w), Float.pi * 0.5)
            }
            if (test < -0.499) {
                return Vector3f(0, -2.0 * atan2(self.x, self.w), Float.pi * -0.5)
            }
            let h = atan2(2 * self.y * self.w - 2 * self.x * self.z, 1 - 2 * qy2 - 2 * qz2)
            let a = asin(2 * self.x * self.y + 2 * self.z * self.w)
            let b = atan2(2 * self.x * self.w - 2 * self.y * self.z, 1 - 2 * qx2 - 2 * qz2)
            
            return Vector3f(b, h, a)
        }
        set(newValue) {
            self = Quaternion(eulerAngles: newValue)
        }
    }
    
    @inlinable
    public var roll : Float {
        let factor1 = (self.x * self.y + self.w * self.z)
        let factor2 = self.w * self.w + self.x * self.x - self.y * self.y - self.z * self.z
        let result = atan2(2 * factor1, factor2);
        return result
    }
    
    @inlinable
    public var pitch : Float {
        let factor1 = (self.y * self.z + self.w * self.x)
        var factor2 = self.w * self.w
        factor2 -= self.x * self.x - self.y * self.y
        factor2 += self.z * self.z
        return atan2(2 * factor1, factor2);
    }
    
    @inlinable
    public var yaw : Float {
        let factor = (self.x * self.z - self.w * self.y)
        let clamped = clamp(-2 * factor, min: -1, max: 1)
        return asin(clamped);
    }
    
    @inlinable
    public static func *(q1: Quaternion, q2: Quaternion) -> Quaternion {
        let x =  q1.x * q2.w + q1.y * q2.z - q1.z * q2.y + q1.w * q2.x
        let y = -q1.x * q2.z + q1.y * q2.w + q1.z * q2.x + q1.w * q2.y
        let z =  q1.x * q2.y - q1.y * q2.x + q1.z * q2.w + q1.w * q2.z
        let w = -q1.x * q2.x - q1.y * q2.y - q1.z * q2.z + q1.w * q2.w
        return Quaternion(x, y, z, w)
    }
    
    @inlinable
    public static func *=(lhs: inout Quaternion, rhs: Quaternion) {
        lhs = lhs * rhs
    }
    
    @inlinable
    public static func *(lhs: Quaternion, rhs: Float) -> Quaternion {
        return Quaternion(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs, lhs.w * rhs)
    }
    
    @inlinable
    public static func *=(lhs: inout Quaternion, rhs: Float) {
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
        return normalize(self)
    }
    
    @inlinable
    public var lengthSquared : Float {
        return dot(self, self)
    }
    
    @inlinable
    public var conjugate : Quaternion {
        return Quaternion(-self.x, -self.y, -self.z, self.w)
    }
    
    @inlinable
    public var inverse : Quaternion {
        let lengthSquared = self.lengthSquared
        let scale = 1.0 / lengthSquared
        return self.conjugate * scale
    }
    
}

extension Quaternion {
    
    @inlinable
    public static func *(lhs: Matrix4x4f, rhs: Quaternion) -> Matrix4x4f {
        return lhs * Matrix4x4f(quaternion: rhs)
    }
    
    @inlinable
    public static func *(lhs: Quaternion, rhs: Matrix4x4f) -> Matrix4x4f {
        return Matrix4x4f(quaternion: lhs) * rhs
    }
    
    @inlinable
    public static func *(lhs: Matrix3x3f, rhs: Quaternion) -> Matrix3x3f {
        return lhs * Matrix3x3f(quaternion: rhs)
    }
    
    @inlinable
    public static func *(lhs: Quaternion, rhs: Matrix3x3f) -> Matrix3x3f {
        return Matrix3x3f(quaternion: lhs) * rhs
    }
    
    @inlinable
    public static func *(lhs: AffineMatrix, rhs: Quaternion) -> AffineMatrix {
        return lhs * AffineMatrix(quaternion: rhs)
    }
    
    @inlinable
    public static func *(lhs: Quaternion, rhs: AffineMatrix) -> AffineMatrix {
        return AffineMatrix(quaternion: lhs) * rhs
    }
    
}

@inlinable
public func normalize(_ x: Quaternion) -> Quaternion {
    //http://stackoverflow.com/questions/11667783/quaternion-and-normalization
    let qmagsq = Float(x.x * x.x + x.y * x.y + x.z * x.z + x.w * x.w)
    
    if (abs(1.0 - qmagsq) < 2.107342e-08) {
        return x * Float(2.0 / (1.0 + qmagsq));
    }
    else {
        return x * (1.0 / sqrtf(qmagsq));
    }
}

@inlinable
public func dot(_ u: Quaternion, _ v: Quaternion) -> Float {
    return u.x * v.x + u.y * v.y + u.z * v.z + u.w * v.w
}

@inlinable
public func slerp(from: Quaternion, to: Quaternion, factor t: Float) -> Quaternion {
    // Calculate angle between them.
    let cosHalfTheta = dot(from, to)
    
    // if this == other or this == -other then theta = 0 and we can return this
    if (abs(cosHalfTheta) >= 1.0) {
        return from;
    }
    
    // Calculate temporary values.
    let halfTheta : Float = acos(cosHalfTheta)
    let sinHalfTheta : Float = sqrtf(1.0 - cosHalfTheta * cosHalfTheta)
    
    var x : Float, y : Float, z : Float, w : Float;
    
    // if theta = 180 degrees then result is not fully defined
    // we could rotate around any axis normal to qa or qb
    if (fabs(sinHalfTheta) < 0.001){
        w = (from.w * 0.5 + to.w * 0.5);
        x = (from.x * 0.5 + to.x * 0.5);
        y = (from.y * 0.5 + to.y * 0.5);
        z = (from.z * 0.5 + to.z * 0.5);
    } else {
        
        let ratioA = sin((1 - t) * halfTheta) / sinHalfTheta
        let ratioB = sin(t * halfTheta) / sinHalfTheta
        
        //calculate quaternion.
        w = (from.w * ratioA + to.w * ratioB);
        x = (from.x * ratioA + to.x * ratioB);
        y = (from.y * ratioA + to.y * ratioB);
        z = (from.z * ratioA + to.z * ratioB);
    }
    return Quaternion(x, y, z, w);
}


///MARK: Quaternion extensions

extension Quaternion {
    public init(_ m: Matrix4x4f) {
        var n4 : Float; // the norm of quaternion multiplied by 4
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
        
        n4 = sqrtf(n4)
        
        self *= 0.5 / n4
    }
    
    public init(_ m: AffineMatrix) {
        var n4 : Float; // the norm of quaternion multiplied by 4
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
        
        n4 = sqrtf(n4)
        
        self *= 0.5 / n4
    }
}

