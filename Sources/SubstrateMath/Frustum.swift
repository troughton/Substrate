//
//  Geometry.swift
//  OriginalAdventure
//
//  Created by Thomas Roughton on 13/12/15.
//  Copyright © 2015 Thomas Roughton. All rights reserved.
//

import Swift

public enum Extent : Int, CaseIterable {
    case minX_MinY_MinZ = 0b000
    case minX_MinY_MaxZ = 0b001
    case minX_MaxY_MinZ = 0b010
    case minX_MaxY_MaxZ = 0b011
    case maxX_MinY_MinZ = 0b100
    case maxX_MinY_MaxZ = 0b101
    case maxX_MaxY_MinZ = 0b110
    case maxX_MaxY_MaxZ = 0b111
    
    static let MaxXFlag = 0b100
    static let MaxYFlag = 0b010
    static let MaxZFlag = 0b001
}

@frozen
public struct SIMDPlane<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable, Codable {
    public let normalX : SIMD4<Scalar>
    public let normalY : SIMD4<Scalar>
    public let normalZ : SIMD4<Scalar>
    public let d : SIMD4<Scalar>
    
    @inlinable
    public init(normalX: Scalar, normalY: Scalar, normalZ: Scalar, constant: Scalar) {
        self.normalX = SIMD4(repeating: normalX)
        self.normalY = SIMD4(repeating: normalY)
        self.normalZ = SIMD4(repeating: normalZ)
        self.d = SIMD4(repeating: constant)
    }
}

@frozen
public struct FrustumPlane<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable, Codable {
    public let storage : SIMD4<Scalar>
    
    @inlinable
    public var normalVector : SIMD3<Scalar> {
        return storage[SIMD3(0, 1, 2)]
    }
    
    @inlinable
    public var constant : Scalar {
        return storage.w
    }
    
    
    @inlinable
    public var normalised : FrustumPlane {
        let magnitude = normalVector.length
        return FrustumPlane(normalVector: self.normalVector / magnitude, constant: self.constant / magnitude)
    }
    
    @inlinable
    public func distance(to point: SIMD3<Scalar>) -> Scalar {
        return dot(self.normalVector, point) + self.constant
    }
    
    @inlinable
    public init(normalVector: SIMD3<Scalar>, constant: Scalar) {
        let magnitude = normalVector.length
        self.init(normalAndConstant: SIMD4<Scalar>(normalVector, constant) / magnitude)
    }
    
    @inlinable
    public init(normalAndConstant: SIMD4<Scalar>) {
        self.storage = normalAndConstant
    }
    
    @inlinable
    public init(withPoints points: [SIMD3<Scalar>]) {
        assert(points.count > 2)
        
        let normal = normalize(cross(points[1] - points[0], points[2] - points[0]))
        let constant = componentSum(-(points[0] * normal))
        
        self.init(normalVector: normal, constant: constant)
        
        assert({
            for point in points {
                if self.distance(to: point) != 0 {
                    return false
                }
            }
            return true
        }(), "All the points must lie on the resultant plane")
    }
    
    @inlinable
    public var simdPlane : SIMDPlane<Scalar> {
        return SIMDPlane(normalX: self.normalVector.x, normalY: self.normalVector.y, normalZ: self.normalVector.z, constant: self.constant)
    }
}

private let isGL = false

public struct Frustum<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable, Codable {
    enum PlaneDirection {
        case far
        case near
        case left
        case right
        case top
        case bottom
        
        var extentsOfPlane : [Extent] { //ordered anti-clockwise as viewed from the inside of the frustum
            switch self {
            case .far:
                return [.maxX_MaxY_MaxZ, .minX_MaxY_MaxZ, .minX_MinY_MaxZ, .maxX_MinY_MaxZ]
            case .near:
                return [.maxX_MaxY_MinZ, .maxX_MinY_MinZ, .minX_MinY_MinZ, .minX_MaxY_MinZ]
            case .left:
                return [.minX_MaxY_MaxZ, .minX_MaxY_MinZ, .minX_MinY_MinZ, .minX_MinY_MaxZ]
            case .right:
                return [.maxX_MaxY_MaxZ, .maxX_MinY_MaxZ, .maxX_MinY_MinZ, .maxX_MaxY_MinZ]
            case .top:
                return [.maxX_MaxY_MaxZ, .maxX_MaxY_MinZ, .minX_MaxY_MinZ, .minX_MaxY_MaxZ]
            case .bottom:
                return [.maxX_MinY_MaxZ, .minX_MinY_MaxZ, .minX_MinY_MinZ, .maxX_MinY_MinZ]
            }
        }
        
        static var frustumPlanes : [PlaneDirection] { return [.near, .far, .left, .right, .top, .bottom] }
    }
    
    public let leftPlane : FrustumPlane<Scalar>
    public let rightPlane : FrustumPlane<Scalar>
    public let topPlane : FrustumPlane<Scalar>
    public let bottomPlane : FrustumPlane<Scalar>
    public let nearPlane : FrustumPlane<Scalar>
    public let farPlane : FrustumPlane<Scalar>
    
    public init(worldToProjectionMatrix: Matrix4x4<Scalar>) {
        // FIXME: These planes are complete guesses (as to which is near, far, left, right etc.
        // Thankfully, nothing relies on that currently.
        
        let vp = worldToProjectionMatrix
        
        let n1x = (vp[0][3] + vp[0][0])
        let n1y = (vp[1][3] + vp[1][0])
        let n1z = (vp[2][3] + vp[2][0])
        let n1 = SIMD3<Scalar>(n1x, n1y, n1z)
        self.leftPlane = FrustumPlane(normalVector: n1, constant: (vp[3][3] + vp[3][0]))
        
        let n2x = (vp[0][3] - vp[0][0])
        let n2y = (vp[1][3] - vp[1][0])
        let n2z = (vp[2][3] - vp[2][0])
        self.rightPlane = FrustumPlane(normalVector: SIMD3<Scalar>(n2x, n2y, n2z), constant: (vp[3][3] - vp[3][0]))
        
        let n3x = (vp[0][3] - vp[0][0])
        let n3y = (vp[1][3] - vp[1][0])
        let n3z = (vp[2][3] - vp[2][0])
        
        self.topPlane = FrustumPlane(normalVector: SIMD3<Scalar>(n3x, n3y, n3z), constant: (vp[3][3] - vp[3][0]))
        
        let n4x = (vp[0][3] + vp[0][1])
        let n4y = (vp[1][3] + vp[1][1])
        let n4z = (vp[2][3] + vp[2][1])
        self.bottomPlane = FrustumPlane(normalVector: SIMD3<Scalar>(n4x, n4y, n4z), constant: (vp[3][3] + vp[3][1]))
        
        let n5xGL = (vp[0][3] + vp[0][2])
        let n5yGL = (vp[1][3] + vp[1][2])
        let n5zGL = (vp[2][3] + vp[2][2])
        
        if isGL {
            self.nearPlane = FrustumPlane(normalVector: SIMD3<Scalar>(n5xGL, n5yGL, n5zGL), constant: (vp[3][3] + vp[3][2]))
        } else {
            self.nearPlane = FrustumPlane(normalVector: SIMD3<Scalar>(vp[0][2], vp[1][2], vp[2][2]), constant: vp[3][2])
        }
        
        let n6x = (vp[0][3] - vp[0][2])
        let n6y = (vp[1][3] - vp[1][2])
        let n6z = (vp[2][3] - vp[2][2])
        self.farPlane = FrustumPlane(normalVector: SIMD3<Scalar>(n6x, n6y, n6z), constant: (vp[3][3] - vp[3][2]))
        
    }
    
    @inlinable
    public func enclosesPoint(_ point: SIMD3<Scalar>) -> Bool {
        if topPlane.distance(to: point) < 0 { return false }
        if bottomPlane.distance(to: point) < 0 { return false }
        if nearPlane.distance(to: point) < 0 { return false }
        if farPlane.distance(to: point) < 0 { return false }
        if leftPlane.distance(to: point) < 0 { return false }
        if rightPlane.distance(to: point) < 0 { return false }
        
        return true
    }
    
    @inlinable
    public func withPlanes<T>(_ perform: (UnsafePointer<FrustumPlane<Scalar>>) -> T) -> T {
        assert(MemoryLayout<Frustum>.size == 6 * MemoryLayout<FrustumPlane<Scalar>>.size)
        return withUnsafeBytes(of: self) { frustumBytes in
            let frustum = frustumBytes.bindMemory(to: FrustumPlane<Scalar>.self)
            defer { _ = frustumBytes.bindMemory(to: Frustum.self) }
            return perform(frustum.baseAddress!)
        }
    }
    
    // Adapted from http://iquilezles.org/www/articles/frustumcorrect/frustumcorrect.htm
    // May have false positives.
    @inlinable
    public func contains(box: AxisAlignedBoundingBox<Scalar>) -> Bool {
        // check box outside/inside of frustum
        return self.withPlanes { planes in
            for i in 0..<6 {
                var out = 0
                out += (planes[i].distance(to: SIMD3<Scalar>(box.minX, box.minY, box.minZ)) < 0) ? 1 : 0
                out += (planes[i].distance(to: SIMD3<Scalar>(box.maxX, box.minY, box.minZ)) < 0) ? 1 : 0
                out += (planes[i].distance(to: SIMD3<Scalar>(box.minX, box.maxY, box.minZ)) < 0) ? 1 : 0
                out += (planes[i].distance(to: SIMD3<Scalar>(box.maxX, box.maxY, box.minZ)) < 0) ? 1 : 0
                out += (planes[i].distance(to: SIMD3<Scalar>(box.minX, box.minY, box.maxZ)) < 0) ? 1 : 0
                out += (planes[i].distance(to: SIMD3<Scalar>(box.maxX, box.minY, box.maxZ)) < 0) ? 1 : 0
                out += (planes[i].distance(to: SIMD3<Scalar>(box.minX, box.maxY, box.maxZ)) < 0) ? 1 : 0
                out += (planes[i].distance(to: SIMD3<Scalar>(box.maxX, box.maxY, box.maxZ)) < 0) ? 1 : 0
                
                if out == 8 { return false }
            }
            
            return true
        }
    }
    
    @inlinable
    public func contains(sphere: Sphere<Scalar>) -> Bool {
        if topPlane.distance(to: sphere.centre) < -sphere.radius { return false }
        if bottomPlane.distance(to: sphere.centre) < -sphere.radius { return false }
        if nearPlane.distance(to: sphere.centre) < -sphere.radius { return false }
        if farPlane.distance(to: sphere.centre) < -sphere.radius { return false }
        if leftPlane.distance(to: sphere.centre) < -sphere.radius { return false }
        if rightPlane.distance(to: sphere.centre) < -sphere.radius { return false }
        
        return true
    }
    
    @inlinable
    public var simdPlanes : (SIMDPlane<Scalar>, SIMDPlane<Scalar>, SIMDPlane<Scalar>, SIMDPlane<Scalar>, SIMDPlane<Scalar>, SIMDPlane<Scalar>) {
        return (farPlane.simdPlane, nearPlane.simdPlane, topPlane.simdPlane, bottomPlane.simdPlane, leftPlane.simdPlane, rightPlane.simdPlane)
    }
    
}
