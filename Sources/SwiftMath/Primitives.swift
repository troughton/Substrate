//
//  Primitives.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 18/11/16.
//
//

import Swift

@_fixed_layout
public struct AxisAlignedBoundingBox : Equatable {
    public var minPoint : Vector3f
    public var maxPoint : Vector3f
    
    @inlinable
    public init() {
        self.minPoint = Vector3f()
        self.maxPoint = Vector3f()
    }
    
    @inlinable
    public init(min: Vector3f, max: Vector3f) {
        self.minPoint = min
        self.maxPoint = max
    }
    
    @inlinable
    public mutating func expand(by factor: Float) {
        self.minPoint -= Vector3f(factor)
        self.maxPoint += Vector3f(factor)
    }
    
    public static let baseBox = AxisAlignedBoundingBox(min: vec3(Float.infinity), max: vec3(-Float.infinity))
    
    public static let unitBox = AxisAlignedBoundingBox(min: vec3(-0.5), max: vec3(0.5))
    
    @inlinable
    public var width : Float {
        return self.maxX - self.minX;
    }
    
    @inlinable
    public var depth : Float {
        return self.maxZ - self.minZ;
    }
    
    @inlinable
    public var height : Float {
        return self.maxY - self.minY;
    }
    
    @inlinable
    public var volume : Float {
        return self.depth * self.width * self.height;
    }
    
    @inlinable
    public var diagonal : Float {
        return (self.maxPoint - self.minPoint).length
    }
    
    @inlinable
    public var surfaceArea : Float {
        let width = self.width
        let height = self.height
        let depth = self.depth
        return 2.0 * (width * height + width * depth + height * depth);
    }
    
    @inlinable
    public var minX : Float { return self.minPoint.x }
    @inlinable
    public var minY : Float { return self.minPoint.y }
    @inlinable
    public var minZ : Float { return self.minPoint.z }
    @inlinable
    public var maxX : Float { return self.maxPoint.x }
    @inlinable
    public var maxY : Float { return self.maxPoint.y }
    @inlinable
    public var maxZ : Float { return self.maxPoint.z }
    
    @inlinable
    public var centreX : Float {
        return (self.minX + self.maxX)/2
    }
    
    @inlinable
    public var centreY : Float {
        return (self.minY + self.maxY)/2
    }
    
    @inlinable
    public var centreZ : Float {
        return (self.minZ + self.maxZ)/2
    }
    
    @inlinable
    public var centre : Vector3f {
        return (self.minPoint + self.maxPoint) * 0.5
    }
    
    @inlinable
    public var size : vec3 {
        return self.maxPoint - self.minPoint
    }
    
    @inlinable
    public func contains(point: vec3) -> Bool {
        return point.x >= self.minX &&
            point.x <= self.maxX &&
            point.y >= self.minY &&
            point.y <= self.maxY &&
            point.z >= self.minZ &&
            point.z <= self.maxZ;
    }
    
    /**
     * Returns the vertex of self box in the direction described by direction.
     * @param direction The direction to look in.
     * @return The vertex in that direction.
     */
    public func pointAtExtent(_ extent: Extent) -> vec3 {
        let useMaxX = extent.rawValue & Extent.MaxXFlag != 0
        let useMaxY = extent.rawValue & Extent.MaxYFlag != 0
        let useMaxZ = extent.rawValue & Extent.MaxZFlag != 0
        
        return vec3(useMaxX ? self.maxX : self.minX, useMaxY ? self.maxY : self.minY, useMaxZ ? self.maxZ : self.minZ)
    }
    
    /**
     * @param otherBox The box to check intersection with.
     * @return Whether self box is intersecting with the other box.
     */
    @inlinable
    public func intersects(with otherBox: AxisAlignedBoundingBox) -> Bool {
        return !(self.maxX < otherBox.minX ||
            self.minX > otherBox.maxX ||
            self.maxY < otherBox.minY ||
            self.minY > otherBox.maxY ||
            self.maxZ < otherBox.minZ ||
            self.minZ > otherBox.maxZ);
    }
    
    @inlinable
    public func intersects(with sphere: Sphere) -> Bool {
        if (sphere.centre.x + sphere.radius < self.minX) ||
                (sphere.centre.y + sphere.radius < self.minY) ||
                (sphere.centre.z + sphere.radius < self.minZ) ||
                (sphere.centre.x - sphere.radius > self.maxX) ||
                (sphere.centre.y - sphere.radius > self.maxY) ||
                (sphere.centre.z - sphere.radius > self.maxZ) {
            return false;
        } else {
            return true;
        }
    }
    
    @inlinable
    public func contains(_ otherBox: AxisAlignedBoundingBox) -> Bool {
        return
            self.minX < otherBox.minX &&
                self.maxX > otherBox.maxX &&
                self.minY < otherBox.minY &&
                self.maxY > otherBox.maxY &&
                self.minZ < otherBox.minZ &&
                self.maxZ > otherBox.maxZ
    }

    public mutating func combine(with box: AxisAlignedBoundingBox) {
        self.minPoint = min(self.minPoint, box.minPoint)
        self.maxPoint = max(self.maxPoint, box.maxPoint)
    }
    
    public static func combine(_ a : AxisAlignedBoundingBox, _ b : AxisAlignedBoundingBox) -> AxisAlignedBoundingBox {
        var result = a
        result.combine(with: b)
        return result
    }
    
    
    /**
     * Transforms this bounding box from its local space to the space described by nodeToSpaceTransform.
     * The result is guaranteed to be axis aligned – that is, with no rotation in the destination space.
     * It may or may not have the same width, height, or depth as its source.
     * @param nodeToSpaceTransform The transformation from local to the destination space.
     * @return this box in the destination coordinate system.
     */
    public func transformed(by nodeToSpaceTransform: Matrix4x4f) -> AxisAlignedBoundingBox {
        
        var minX = Float.infinity, minY = Float.infinity, minZ = Float.infinity
        var maxX = -Float.infinity, maxY = -Float.infinity, maxZ = -Float.infinity
        
        //Compute all the vertices for the box.
        for xToggle in 0..<2 {
            for yToggle in 0..<2 {
                for zToggle in 0..<2 {
                    let x = xToggle == 0 ? minPoint.x : maxPoint.x;
                    let y = yToggle == 0 ? minPoint.y : maxPoint.y;
                    let z = zToggle == 0 ? minPoint.z : maxPoint.z;
                    let vertex = vec3(x, y, z);
                    let transformedVertex = nodeToSpaceTransform.multiplyAndProject(vertex)
                    
                    if (transformedVertex.x < minX) { minX = transformedVertex.x; }
                    if (transformedVertex.y < minY) { minY = transformedVertex.y; }
                    if (transformedVertex.z < minZ) { minZ = transformedVertex.z; }
                    if (transformedVertex.x > maxX) { maxX = transformedVertex.x; }
                    if (transformedVertex.y > maxY) { maxY = transformedVertex.y; }
                    if (transformedVertex.z > maxZ) { maxZ = transformedVertex.z; }
                }
            }
        }
        
        return AxisAlignedBoundingBox(min: vec3(minX, minY, minZ), max: vec3(maxX, maxY, maxZ));
    }
    
    /**
     * Transforms this bounding box from its local space to the space described by nodeToSpaceTransform.
     * The result is guaranteed to be axis aligned – that is, with no rotation in the destination space.
     * It may or may not have the same width, height, or depth as its source.
     * @param nodeToSpaceTransform - The transformation from local to the destination space.
     * @return - this box in the destination coordinate system.
     */
    public func transformed(by nodeToSpaceTransform: AffineMatrix) -> AxisAlignedBoundingBox {
        
        var minX = Float.infinity, minY = Float.infinity, minZ = Float.infinity
        var maxX = -Float.infinity, maxY = -Float.infinity, maxZ = -Float.infinity
        
        //Compute all the vertices for the box.
        for xToggle in 0..<2 {
            for yToggle in 0..<2 {
                for zToggle in 0..<2 {
                    let x = xToggle == 0 ? minPoint.x : maxPoint.x;
                    let y = yToggle == 0 ? minPoint.y : maxPoint.y;
                    let z = zToggle == 0 ? minPoint.z : maxPoint.z;
                    let vertex = Vector4f(x, y, z, 1)
                    let transformedVertex = nodeToSpaceTransform * vertex
                    
                    if (transformedVertex.x < minX) { minX = transformedVertex.x; }
                    if (transformedVertex.y < minY) { minY = transformedVertex.y; }
                    if (transformedVertex.z < minZ) { minZ = transformedVertex.z; }
                    if (transformedVertex.x > maxX) { maxX = transformedVertex.x; }
                    if (transformedVertex.y > maxY) { maxY = transformedVertex.y; }
                    if (transformedVertex.z > maxZ) { maxZ = transformedVertex.z; }
                }
            }
        }
        
        return AxisAlignedBoundingBox(min: vec3(minX, minY, minZ), max: vec3(maxX, maxY, maxZ));
    }
    
    @inlinable
    public func boundingSphere(in nodeToSpaceTransform: AffineMatrix, radiusScale: Float) -> Sphere {
        
        let centre = self.centre
        let radius = self.diagonal * 0.5
        var transformedCentre = nodeToSpaceTransform * Vector4f(centre, 1)
        
        transformedCentre.w = radius * radiusScale
        
        return Sphere(centreAndRadius: transformedCentre)
    }
    
    public func maxZForBoundingBoxInSpace(nodeToSpaceTransform : Matrix4x4f) -> Float {
        
        var maxZ = -Float.infinity
        
        //Compute all the vertices for the box.
        for xToggle in 0..<2 {
            for yToggle in 0..<2 {
                for zToggle in 0..<2 {
                    let x = xToggle == 0 ? minPoint.x : maxPoint.x;
                    let y = yToggle == 0 ? minPoint.y : maxPoint.y;
                    let z = zToggle == 0 ? minPoint.z : maxPoint.z;
                    let vertex = vec3(x, y, z);
                    let transformedVertex = nodeToSpaceTransform * Vector4f(vertex, 1);
                    
                    if (transformedVertex.z > maxZ) { maxZ = transformedVertex.z; }
                }
            }
        }
        
        return maxZ;
    }
    
    
    public static func ==(lhs: AxisAlignedBoundingBox, rhs: AxisAlignedBoundingBox) -> Bool {
        return lhs.minPoint == rhs.minPoint && lhs.maxPoint == rhs.maxPoint
    }

}

public struct Cylinder {
    public var position : Vector3f
    public var end : Vector3f
    public var radius : Float
    
}

public struct Disk {
    public var centre : Vector3f
    public var normal : Vector3f
    public var radius : Float
    
}

public struct OrientedBoundingBox {
    public var transform : AffineMatrix
    
    public init(transform: AffineMatrix) {
        self.transform = transform
    }
    
    public init(aabb: AxisAlignedBoundingBox, inSpace transform: AffineMatrix) {
        let aabbTransform = AffineMatrix.scaleRotateTranslate(scale: aabb.size, rotation: Quaternion.identity, translation: aabb.centre)
        self.init(transform: transform * aabbTransform)
    }
}

public struct ProjectedBoundingBox {
    public var transform : Matrix4x4f
    
    public init(transform: Matrix4x4f = Matrix4x4f.identity) {
        self.transform = transform
    }
    
    public init(aabb: AxisAlignedBoundingBox, inSpace transform: Matrix4x4f) {
        let aabbTransform = Matrix4x4f.scaleRotateTranslate(scale: aabb.size, rotation: Quaternion.identity, translation: aabb.centre)
        self.init(transform: transform * aabbTransform)
    }
    
    public init(transform: AffineMatrix) {
        self.transform = Matrix4x4f(transform)
    }
    
    public init(aabb: AxisAlignedBoundingBox, inSpace transform: AffineMatrix) {
        let aabbTransform = AffineMatrix.scaleRotateTranslate(scale: aabb.size, rotation: Quaternion.identity, translation: aabb.centre)
        self.init(transform: transform * aabbTransform)
    }
}

@_fixed_layout
public struct Plane {
    @usableFromInline
    var storage : Vector4f

    @inlinable
    public var normal : Vector3f {
        get {
            return self.storage.xyz
        }
        set {
            self.storage.xyz = newValue
        }
    }
    
    @inlinable
    public var constant : Float {
        get {
            return self.storage.w
        }
        set {
            self.storage.w = newValue
        }
    }
    
    public init(normal: Vector3f, constant: Float) {
        self.storage = Vector4f(normal, constant)
    }
}

public struct Ray {
    
    public var origin : Vector3f
    public var direction : Vector3f
    
    public init(origin: Vector3f = Vector3f(0), direction: Vector3f = Vector3f(0)) {
        self.origin = origin
        self.direction = direction
    }
    
    public init(fromScreenSpaceX x: Float, y: Float, mvp: Matrix4x4f) {
        self = Ray(fromScreenSpaceX: x, y: y, inverseMVP: mvp.inverse)
    }
    
    public init(fromScreenSpaceX x: Float, y: Float, inverseMVP: Matrix4x4f) {
        let ray = Ray(origin: Vector3f(x, y, 0), direction: Vector3f(0, 0, 1))
        let viewRay = inverseMVP * ray
        self = viewRay
    }
    
    public func at(t: Float) -> Vector3f {
        return self.origin + Vector3f(t) * self.direction
    }
    
    public static func *(lhs: Matrix4x4f, rhs: Ray) -> Ray {
        var ray = Ray()
        
        let origin = lhs * Vector4f(rhs.origin, 1)
        
        ray.origin = origin.xyz * Vector3f(1.0 / origin.w)
        
        let direction = Vector3f(
            lhs[2][0] - (lhs[2][3] * ray.origin.x),
            lhs[2][1] - (lhs[2][3] * ray.origin.y),
            lhs[2][2] - (lhs[2][3] * ray.origin.z)
            ).normalized
        ray.direction = direction
        return ray
    }
    
    public func intersectionAt(y: Float) -> Vector3f {
        let t = (y - self.origin.y) / self.direction.y
        return self.at(t: t)
    }
    
    public func intersects(with box: AxisAlignedBoundingBox) -> Bool {
        // r.dir is unit direction vector of ray
        var dirFrac = Vector3f(1.0) / self.direction
        
        // lb is the corner of AABB with minimal coordinates - left bottom, rt is maximal corner
        // r.org is origin of ray
        let t1 = (box.minX - self.origin.x) * dirFrac.x
        let t2 = (box.maxX - self.origin.x) * dirFrac.x
        let t3 = (box.minY - self.origin.y) * dirFrac.y
        let t4 = (box.maxY - self.origin.y) * dirFrac.y
        let t5 = (box.minZ - self.origin.z) * dirFrac.z
        let t6 = (box.maxZ - self.origin.z) * dirFrac.z
        
        let tMin = max(max(min(t1, t2), min(t3, t4)), min(t5, t6));
        let tMax = min(min(max(t1, t2), max(t3, t4)), max(t5, t6));
        
        // if tmax < 0, ray (line) is intersecting AABB, but whole AABB is behind us
        if (tMax < 0) {
            return false
        }
        
        // if tmin > tmax, ray doesn't intersect AABB
        if (tMin > tMax) {
            return false
        }
        
        return true
    }
    
    public func intersections(with box: AxisAlignedBoundingBox) -> (near: Float, far: Float)? {
        var t1 = Vector3f()
        var t2 = Vector3f() // vectors to hold the T-values for every direction
        var tNear = -Float.infinity;
        var tFar = Float.infinity;
        
        for i in 0..<3 { //we test slabs in every direction
            if (self.direction[i] == 0) { // ray parallel to planes in this direction
                if ((self.origin[i] < box.minPoint[i]) || (self.origin[i] > box.maxPoint[i])) {
                    return nil // parallel AND outside box : no intersection possible
                }
            } else { // ray not parallel to planes in this direction
                t1[i] = (box.minPoint[i] - self.origin[i]) / self.direction[i];
                t2[i] = (box.maxPoint[i] - self.origin[i]) / self.direction[i];
                
                if(t1[i] > t2[i]) { // we want T_1 to hold values for intersection with near plane
                    swap(&t1, &t2)
                }
                if (t1[i] > tNear){
                    tNear = t1[i];
                }
                if (t2[i] < tFar){
                    tFar = t2[i];
                }
                if ( (tNear > tFar) || (tFar < 0) ) {
                    return nil
                }
            }
        }
        return (tNear, tFar)
    }
}

@_fixed_layout
public struct Sphere {
    public var centreAndRadius : Vector4f
    
    @inlinable
    public var centre : Vector3f {
        get {
            return self.centreAndRadius.xyz
        }
        set {
            self.centreAndRadius.xyz = newValue
        }
    }
    
    @inlinable
    public var radius : Float {
        get {
            return self.centreAndRadius.w
        }
        set {
            self.centreAndRadius.w = newValue
        }
    }
    
    @inlinable
    public init(centre: Vector3f, radius: Float) {
        self.centreAndRadius = Vector4f(centre, radius)
    }
    
    @inlinable
    public init(centreAndRadius: Vector4f) {
        self.centreAndRadius = centreAndRadius
    }
}

public struct Triangle {
    public var v0 : Vector3f
    public var v1 : Vector3f
    public var v2 : Vector3f
}

public struct Intersection {
    public var position : Vector3f
    public var normal : Vector3f
    public var distance : Float
}

public enum Axis {
    case x
    case y
    case z
    
    public var next : Axis {
        switch self {
        case .x:
            return .y
        case .y:
            return .z
        case .z:
            return .x
        }
    }
}
