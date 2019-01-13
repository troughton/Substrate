// Copyright 2016 Stuart Carnie.
// License: https://github.com/SwiftGFX/SwiftMath#license-bsd-2-clause
//

import Swift

extension Matrix3x3f {
    public init(_ m: Matrix4x4f) {
        self.init(m[0].xyz, m[1].xyz, m[2].xyz)
    }
    
    public init(quaternion q: Quaternion) {
        self.init(diagonal: vec3(1.0))
        
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

extension Matrix3x3f: CustomStringConvertible {
    
    /// Displays the matrix in column-major order
    public var description: String {
        return "Matrix3x3f(\n\(self[0]), \(self[1]), \(self[2]))\n)"
    }
}


extension Matrix3x3f : CustomDebugStringConvertible {
    public var debugDescription : String {
        return self.description
    }
}

@inlinable
public func interpolate(from m1: Matrix3x3f, to m: Matrix3x3f, factor t: Float) -> Matrix3x3f {
    return Matrix3x3f(
        m1[1, 1] + (m[1, 1] - m1[1, 1]) * t,
        m1[1, 2] + (m[1, 2] - m1[1, 2]) * t,
        m1[1, 3] + (m[1, 3] - m1[1, 3]) * t,
        m1[2, 1] + (m[2, 1] - m1[2, 1]) * t,
        m1[2, 2] + (m[2, 2] - m1[2, 2]) * t,
        m1[2, 3] + (m[2, 3] - m1[2, 3]) * t,
        m1[3, 1] + (m[3, 1] - m1[3, 1]) * t,
        m1[3, 2] + (m[3, 2] - m1[3, 2]) * t,
        m1[3, 3] + (m[3, 3] - m1[3, 3]) * t
    )
}
