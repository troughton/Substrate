//
//  Geometry.swift
//  OriginalAdventure
//
//  Created by Thomas Roughton on 13/12/15.
//  Copyright © 2015 Thomas Roughton. All rights reserved.
//

import Swift

public enum Extent : Int {
    case minX_MinY_MinZ = 0b000
    case minX_MinY_MaxZ = 0b001
    case minX_MaxY_MinZ = 0b010
    case minX_MaxY_MaxZ = 0b011
    case maxX_MinY_MinZ = 0b100
    case maxX_MinY_MaxZ = 0b101
    case maxX_MaxY_MinZ = 0b110
    case maxX_MaxY_MaxZ = 0b111
    case lastElement
    
    static let MaxXFlag = 0b100
    static let MaxYFlag = 0b010
    static let MaxZFlag = 0b001
    
    static let values = (0..<Extent.lastElement.rawValue).map { rawValue -> Extent in return Extent(rawValue: rawValue)! }
}

@_fixed_layout
public struct SIMDPlane {
    public let normalX : Vector4f
    public let normalY : Vector4f
    public let normalZ : Vector4f
    public let d : Vector4f
}

@_fixed_layout
public struct FrustumPlane {
    public let storage : vec4
    
    @inlinable
    public var normalVector : vec3 {
        return storage.xyz
    }
    
    @inlinable
    public var constant : Float {
        return storage.w
    }
    
    
    @inlinable
    public var normalised : FrustumPlane {
        let magnitude = normalVector.length
        return FrustumPlane(normalVector: self.normalVector / magnitude, constant: self.constant / magnitude)
    }
    
    @inlinable
    public func distance(to point: vec3) -> Float {
        return dot(self.normalVector, point) + self.constant
    }
    
    @inlinable
    public init(normalVector: vec3, constant: Float) {
        let magnitude = normalVector.length
        self.init(normalAndConstant: vec4(normalVector, constant) / magnitude)
    }
    
    public init(normalAndConstant: vec4) {
        self.storage = normalAndConstant
    }
    
    public init(withPoints points: [vec3]) {
        assert(points.count > 2)
        
        let normal = cross(points[1] - points[0], points[2] - points[0]).normalized
        let constant = -(points[0] * normal).componentSum
        
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
    
    public var simdPlane : SIMDPlane {
        return SIMDPlane(normalX: Vector4f(self.normalVector.x), normalY: Vector4f(self.normalVector.y), normalZ: Vector4f(self.normalVector.z), d: Vector4f(self.constant))
    }
}

private let isGL = false

public struct Frustum {
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
        
        static let frustumPlanes : [PlaneDirection] = [.near, .far, .left, .right, .top, .bottom]
    }
    
    public let leftPlane : FrustumPlane
    public let rightPlane : FrustumPlane
    public let topPlane : FrustumPlane
    public let bottomPlane : FrustumPlane
    public let nearPlane : FrustumPlane
    public let farPlane : FrustumPlane
    
    public init(worldToProjectionMatrix: Matrix4x4f) {
        // FIXME: These planes are complete guesses (as to which is near, far, left, right etc.
        // Thankfully, nothing relies on that currently.
        
        let vp = worldToProjectionMatrix
        
        let n1x = (vp[0][3] + vp[0][0])
        let n1y = (vp[1][3] + vp[1][0])
        let n1z = (vp[2][3] + vp[2][0])
        let n1 = vec3(n1x, n1y, n1z)
        self.leftPlane = FrustumPlane(normalVector: n1, constant: (vp[3][3] + vp[3][0]))
        
        let n2x = (vp[0][3] - vp[0][0])
        let n2y = (vp[1][3] - vp[1][0])
        let n2z = (vp[2][3] - vp[2][0])
        self.rightPlane = FrustumPlane(normalVector: vec3(n2x, n2y, n2z), constant: (vp[3][3] - vp[3][0]))
        
        let n3x = (vp[0][3] - vp[0][0])
        let n3y = (vp[1][3] - vp[1][0])
        let n3z = (vp[2][3] - vp[2][0])
        
        self.topPlane = FrustumPlane(normalVector: vec3(n3x, n3y, n3z), constant: (vp[3][3] - vp[3][0]))
        
        let n4x = (vp[0][3] + vp[0][1])
        let n4y = (vp[1][3] + vp[1][1])
        let n4z = (vp[2][3] + vp[2][1])
        self.bottomPlane = FrustumPlane(normalVector: vec3(n4x, n4y, n4z), constant: (vp[3][3] + vp[3][1]))
        
        let n5xGL = (vp[0][3] + vp[0][2])
        let n5yGL = (vp[1][3] + vp[1][2])
        let n5zGL = (vp[2][3] + vp[2][2])
        
        if isGL {
            self.nearPlane = FrustumPlane(normalVector: vec3(n5xGL, n5yGL, n5zGL), constant: (vp[3][3] + vp[3][2]))
        } else {
            self.nearPlane = FrustumPlane(normalVector: vec3(vp[0][2], vp[1][2], vp[2][2]), constant: vp[3][2])
        }
        
        let n6x = (vp[0][3] - vp[0][2])
        let n6y = (vp[1][3] - vp[1][2])
        let n6z = (vp[2][3] - vp[2][2])
        self.farPlane = FrustumPlane(normalVector: vec3(n6x, n6y, n6z), constant: (vp[3][3] - vp[3][2]))
        
    }
    
    @inlinable
    public func enclosesPoint(_ point: vec3) -> Bool {
        if topPlane.distance(to: point) < 0 { return false }
        if bottomPlane.distance(to: point) < 0 { return false }
        if nearPlane.distance(to: point) < 0 { return false }
        if farPlane.distance(to: point) < 0 { return false }
        if leftPlane.distance(to: point) < 0 { return false }
        if rightPlane.distance(to: point) < 0 { return false }
        
        return true
    }
    
    @inlinable
    public var planes : UnsafePointer<FrustumPlane> {
        mutating get {
            assert(MemoryLayout<Frustum>.size == 6 * MemoryLayout<FrustumPlane>.size)
            return withUnsafePointer(to: &self) { frustum in
                return UnsafeRawPointer(frustum).assumingMemoryBound(to: FrustumPlane.self)
            }
        }
    }
    
    // Adapted from http://iquilezles.org/www/articles/frustumcorrect/frustumcorrect.htm
    // May have false positives.
    @inlinable
    public func contains(box: AxisAlignedBoundingBox) -> Bool {
        // check box outside/inside of frustum
        var frustum = self
        let planes = frustum.planes
        for i in 0..<6 {
            var out = 0
            out += (planes[i].distance(to: Vector3f(box.minX, box.minY, box.minZ)) < 0) ? 1 : 0
            out += (planes[i].distance(to: Vector3f(box.maxX, box.minY, box.minZ)) < 0) ? 1 : 0
            out += (planes[i].distance(to: Vector3f(box.minX, box.maxY, box.minZ)) < 0) ? 1 : 0
            out += (planes[i].distance(to: Vector3f(box.maxX, box.maxY, box.minZ)) < 0) ? 1 : 0
            out += (planes[i].distance(to: Vector3f(box.minX, box.minY, box.maxZ)) < 0) ? 1 : 0
            out += (planes[i].distance(to: Vector3f(box.maxX, box.minY, box.maxZ)) < 0) ? 1 : 0
            out += (planes[i].distance(to: Vector3f(box.minX, box.maxY, box.maxZ)) < 0) ? 1 : 0
            out += (planes[i].distance(to: Vector3f(box.maxX, box.maxY, box.maxZ)) < 0) ? 1 : 0
            
            if out == 8 { return false }
        }
        
        return true
    }
    
    @inlinable
    public func contains(sphere: Sphere) -> Bool {
        if topPlane.distance(to: sphere.centre) < -sphere.radius { return false }
        if bottomPlane.distance(to: sphere.centre) < -sphere.radius { return false }
        if nearPlane.distance(to: sphere.centre) < -sphere.radius { return false }
        if farPlane.distance(to: sphere.centre) < -sphere.radius { return false }
        if leftPlane.distance(to: sphere.centre) < -sphere.radius { return false }
        if rightPlane.distance(to: sphere.centre) < -sphere.radius { return false }
        
        return true
    }
    
    @inlinable
    public var simdPlanes : (SIMDPlane, SIMDPlane, SIMDPlane, SIMDPlane, SIMDPlane, SIMDPlane) {
        return (farPlane.simdPlane, nearPlane.simdPlane, topPlane.simdPlane, bottomPlane.simdPlane, leftPlane.simdPlane, rightPlane.simdPlane)
    }
    
}
