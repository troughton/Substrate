//
//  Quaternion+Interpolation.swift
//  
//  SubstrateMath
//  Created by Thomas Roughton on 28/06/22.
//

// Reference: https://www.gamedeveloper.com/programming/spherical-spline-quaternions-for-dummies
// and https://gist.github.com/usefulslug/e5534b4f009a71ec521d

import Foundation
import RealModule

extension Quaternion {
    // https://docs.microsoft.com/en-us/previous-versions/windows/desktop/bb281635(v=vs.85)
    // Assumes the input is a unit quaternion.
    public static func log(_ q: Quaternion) -> Quaternion {
        let sinTheta = q.storage.xyz.length
        if sinTheta < .ulpOfOne || sinTheta > 1.0 {
            return Quaternion(SIMD4.zero)
        }
        
        let theta = Scalar.asin(sinTheta)
        return Quaternion(SIMD4(q.storage.xyz * (theta / sinTheta), 0.0))
    }

    // https://docs.microsoft.com/en-us/previous-versions/windows/desktop/bb281622(v=vs.85)
    // Expects a pure quaternion, so w == 0
    public static func exp(_ q: Quaternion) -> Quaternion {
        let theta = q.storage.xyz.length
        if theta < .ulpOfOne {
            return Quaternion(SIMD4(0, 0, 0, 1))
        }
        
        let sinTheta = Scalar.sin(theta)
        let cosTheta = Scalar.cos(theta)
        return Quaternion(SIMD4(q.storage.xyz * (sinTheta / theta), cosTheta))
    }
    
    static func slerpNoInvert(from: Quaternion, to: Quaternion, factor: Scalar) -> Quaternion {
        let dotProduct = dot(from, to)
        
        if abs(dotProduct) > 0.9999 {
            return from
        }
        
        let theta = Scalar.acos(dotProduct)
        let sinT = 1.0 as Scalar / Scalar.sin(theta)
        let newFactor = Scalar.sin(factor * theta) * sinT
        let invFactor = Scalar.sin((1.0 - factor) * theta) * sinT

        let newStorage = invFactor * from.storage + newFactor * to.storage
        
        return Quaternion(newStorage)
    }
    
    // SQUAD (Spherical Spline Quaternions, [Shomake 1987]) implementation for Unity by Vegard Myklebust.
    // https://gist.github.com/usefulslug/c59d5f7d35240733b80b
    // Made available under Creative Commons license CC0. License details can be found here:
    // https://creativecommons.org/publicdomain/zero/1.0/legalcode.txt
    
    /// Returns a quaternion between q1 and q2 as part of a smooth SQUAD segment
    public static func interpolateSplineSegment(leading q0: Quaternion, start q1: Quaternion, end q2: Quaternion, trailing q3: Quaternion, factor t: Scalar) -> Quaternion {
        var q0 = q0
        var q2 = q2
        var q3 = q3
        
        // https://docs.microsoft.com/en-us/previous-versions/windows/desktop/bb281657(v=vs.85)?redirectedfrom=MSDN
        if (q0.storage + q1.storage).lengthSquared < (q0.storage - q1.storage).lengthSquared {
            q0 = Quaternion(-q0.storage)
        }
        if (q1.storage + q2.storage).lengthSquared < (q1.storage - q2.storage).lengthSquared {
            q2 = Quaternion(-q2.storage)
        }
        if (q2.storage + q3.storage).lengthSquared < (q2.storage - q3.storage).lengthSquared {
            q3 = Quaternion(-q3.storage)
        }
        
        let outA = Quaternion.intermediate(q0,q1,q2)
        let outB = Quaternion.intermediate(q1,q2,q3)
        return Quaternion.squad(startRotation: q1, startTangent: outA, endTangent: outB, endRotation: q2, factor: t)
    }

    /// Tries to compute sensible tangent values for the quaternion
    static func intermediate(_ q0: Quaternion, _ q1: Quaternion, _ q2: Quaternion) -> Quaternion {
        let expQ1 = q1.inverse // Quaternion.exp(q1)
        
        let q0Part = Quaternion.log(expQ1 * q0)
        let q2Part = Quaternion.log(expQ1 * q2)
        let added = Quaternion(-0.25 * (q2Part.storage + q0Part.storage))
        
        return q1 * Quaternion.exp(added)
    }

    /// Returns a smooth approximation between q1 and q2 using t1 and t2 as 'tangents'
    public static func squad(startRotation q1: Quaternion, startTangent t1: Quaternion, endTangent t2: Quaternion, endRotation q2: Quaternion, factor t: Scalar) -> Quaternion {
        let slerpT: Scalar = 2.0 * t * (1.0 - t)
        let slerp1: Quaternion = Quaternion.slerpNoInvert(from: q1, to: q2, factor: t)
        let slerp2: Quaternion = Quaternion.slerpNoInvert(from: t1, to: t2, factor: t)
        return Quaternion.slerpNoInvert(from: slerp1, to: slerp2, factor: slerpT)
    }
}
