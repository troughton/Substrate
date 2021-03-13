//
//  Primitives.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 18/11/16.
//
//

import Swift
import RealModule

@frozen
public struct Rect<Scalar: SIMDScalar>: Hashable, Codable {
    public var origin : SIMD2<Scalar>
    public var size : SIMD2<Scalar>
  
    @inlinable
    public init() {
        self.origin = SIMD2<Scalar>()
        self.size = SIMD2<Scalar>()
    }
    
    @inlinable
    public init(origin: SIMD2<Scalar>, size: SIMD2<Scalar>) {
        self.origin = origin
        self.size = size
    }
    
    @inlinable
    public init(x: Scalar, y: Scalar, width: Scalar, height: Scalar) {
        self.origin = SIMD2(x, y)
        self.size = SIMD2(width, height)
    }
    
    @inlinable
    public var x: Scalar {
        get {
            return self.origin.x
        }
        set {
            self.origin.x = newValue
        }
    }
    
    @inlinable
    public var y: Scalar {
        get {
            return self.origin.y
        }
        set {
            self.origin.y = newValue
        }
    }
    
    @inlinable
    public var width: Scalar {
        get {
            return self.size.x
        }
        set {
            self.size.x = newValue
        }
    }
    
    @inlinable
    public var height: Scalar {
        get {
            return self.size.y
        }
        set {
            self.size.y = newValue
        }
    }
}

extension Rect where Scalar: BinaryFloatingPoint {
    @inlinable
    public init<Other: BinaryFloatingPoint & SIMDScalar>(_ other: Rect<Other>) {
        self.origin = SIMD2(other.origin)
        self.size = SIMD2(other.size)
    }
    
    @inlinable
    public init<Other: FixedWidthInteger & SIMDScalar>(_ other: Rect<Other>) {
        self.origin = SIMD2(other.origin)
        self.size = SIMD2(other.size)
    }
    
    @inlinable
    public init(minPoint: SIMD2<Scalar>, maxPoint: SIMD2<Scalar>) {
        self.origin = minPoint
        self.size = maxPoint - minPoint
    }
    
    @inlinable
    public var minPoint: SIMD2<Scalar> {
        get {
            return self.origin
        }
        set {
            self.origin = newValue
        }
    }
    
    @inlinable
    public var maxPoint: SIMD2<Scalar> {
        get {
            return self.origin + self.size
        }
        set {
            self.origin = newValue - self.size
        }
    }
    
    @inlinable
    public func contains(point: SIMD2<Scalar>) -> Bool {
        let maxPoint = self.origin + self.size
        return all(point .>= self.origin) && all(point .<= maxPoint)
    }
    
    @inlinable
    public func intersects(with otherRect: Rect) -> Bool {
        return all((self.origin + self.size .>= otherRect.origin) .& (otherRect.origin + otherRect.size .>= self.origin))
    }
    
    @inlinable
    public func clipped(to otherRect: Rect<Scalar>) -> Rect {
        let currentMax = self.origin + self.size
        let minPoint = pointwiseMin(pointwiseMax(otherRect.origin, self.origin), currentMax)
        let maxPoint = pointwiseMax(minPoint, pointwiseMin(otherRect.origin + otherRect.size, currentMax))
        return Rect(origin: minPoint, size: maxPoint - minPoint)
    }
    
    /**
     * Transforms this bounding box from its local space to the space described by nodeToSpaceTransform.
     * The result is guaranteed to be axis aligned – that is, with no rotation in the destination space.
     * It may or may not have the same width or height as its source.
     * @param nodeToSpaceTransform - The transformation from local to the destination space.
     * @return - this box in the destination coordinate system.
     */
    @inlinable
    public func boundingRect(transformedBy nodeToSpaceTransform: AffineMatrix2D<Scalar>) -> Rect {
        var newMin = SIMD2(repeating: Scalar.infinity)
        var newMax = SIMD2(repeating: -Scalar.infinity)
        
        let minPoint = self.origin
        let maxPoint = self.origin + self.size
        
        //Compute all the vertices for the box.
        for xToggle in 0..<2 {
            for yToggle in 0..<2 {
                let x = xToggle == 0 ? minPoint.x : maxPoint.x;
                let y = yToggle == 0 ? minPoint.y : maxPoint.y;
                let vertex = SIMD2<Scalar>(x, y)
                let transformedVertex = nodeToSpaceTransform.transform(point: vertex)
                
                newMin = pointwiseMin(newMin, transformedVertex)
                newMax = pointwiseMax(newMax, transformedVertex)
            }
        }
        
        return Rect(origin: newMin, size: newMax - newMin)
    }
    
    @inlinable
    public func boundingRect(transformedBy rectTransform: RectTransform<Scalar>) -> Rect<Scalar> {
        let a = rectTransform * self.origin
        let b = rectTransform * (self.origin + self.size)
        return Rect(minPoint: pointwiseMin(a, b), maxPoint: pointwiseMax(a, b))
    }
    
    @inlinable
    public func transformed(by rectTransform: RectTransform<Scalar>) -> Rect<Scalar> {
        let a = rectTransform * self.origin
        let b = rectTransform * (self.origin + self.size)
        return Rect(origin: a, size: b - a)
    }
}

extension Rect where Scalar: FixedWidthInteger {
    @inlinable
    public init<Other: FixedWidthInteger & SIMDScalar>(clamping other: Rect<Other>) {
        self.origin = SIMD2(clamping: other.origin)
        self.size = SIMD2(clamping: other.size)
    }
    
    @inlinable
    public init<Other: BinaryFloatingPoint & SIMDScalar>(_ other: Rect<Other>, rounding: FloatingPointRoundingRule = .towardZero) {
        self.origin = SIMD2(other.origin, rounding: rounding)
        self.size = SIMD2(other.size, rounding: rounding)
    }
    
    @inlinable
    public init(minPoint: SIMD2<Scalar>, maxPoint: SIMD2<Scalar>) {
        self.origin = minPoint
        self.size = maxPoint &- minPoint
    }
    
    @inlinable
    public var minPoint: SIMD2<Scalar> {
        get {
            return self.origin
        }
        set {
            self.origin = newValue
        }
    }
    
    @inlinable
    public var maxPoint: SIMD2<Scalar> {
        get {
            return self.origin &+ self.size
        }
        set {
            self.origin = newValue &- self.size
        }
    }
    
    @inlinable
    public func contains(point: SIMD2<Scalar>) -> Bool {
        let maxPoint = self.origin &+ self.size
        return all(point .>= self.origin) && all(point .<= maxPoint)
    }

    @inlinable
    public func intersects(with otherRect: Rect) -> Bool {
        return all((self.origin &+ self.size .>= otherRect.origin) .& (otherRect.origin &+ otherRect.size .>= self.origin))
    }
}

@frozen
public struct AxisAlignedBoundingBox<Scalar: SIMDScalar & BinaryFloatingPoint & Comparable>: Hashable, Codable {
    public var minPoint : SIMD3<Scalar>
    public var maxPoint : SIMD3<Scalar>
    
    @inlinable
    public init() {
        self.minPoint = SIMD3<Scalar>()
        self.maxPoint = SIMD3<Scalar>()
    }
    
    @inlinable
    public init(min: SIMD3<Scalar>, max: SIMD3<Scalar>) {
        self.minPoint = min
        self.maxPoint = max
    }
    
    @inlinable
    public mutating func expand(by factor: Scalar) {
        self.minPoint -= SIMD3<Scalar>(repeating: factor)
        self.maxPoint += SIMD3<Scalar>(repeating: factor)
    }
    
    public static var baseBox : AxisAlignedBoundingBox { return AxisAlignedBoundingBox(min: SIMD3<Scalar>(repeating: Scalar.infinity), max: SIMD3<Scalar>(repeating: -Scalar.infinity)) }
    
    public static var unitBox : AxisAlignedBoundingBox { return AxisAlignedBoundingBox(min: SIMD3<Scalar>(repeating: -0.5), max: SIMD3<Scalar>(repeating: 0.5)) }
    
    @inlinable
    public var width : Scalar {
        return self.maxX - self.minX;
    }
    
    @inlinable
    public var depth : Scalar {
        return self.maxZ - self.minZ;
    }
    
    @inlinable
    public var height : Scalar {
        return self.maxY - self.minY;
    }
    
    @inlinable
    public var volume : Scalar {
        return self.depth * self.width * self.height;
    }
    
    @inlinable
    public var diagonal : Scalar {
        return (self.maxPoint - self.minPoint).length
    }
    
    @inlinable
    public var surfaceArea : Scalar {
        let size = self.maxPoint - self.minPoint
        var result = size.x * size.y
        result += size.x * size.z
        result += size.y * size.z
        
        return 2 * result
    }
    
    @inlinable
    public var minX : Scalar { return self.minPoint.x }
    @inlinable
    public var minY : Scalar { return self.minPoint.y }
    @inlinable
    public var minZ : Scalar { return self.minPoint.z }
    @inlinable
    public var maxX : Scalar { return self.maxPoint.x }
    @inlinable
    public var maxY : Scalar { return self.maxPoint.y }
    @inlinable
    public var maxZ : Scalar { return self.maxPoint.z }
    
    @inlinable
    public var centreX : Scalar {
        return (self.minX + self.maxX)/2
    }
    
    @inlinable
    public var centreY : Scalar {
        return (self.minY + self.maxY)/2
    }
    
    @inlinable
    public var centreZ : Scalar {
        return (self.minZ + self.maxZ)/2
    }
    
    @inlinable
    public var centre : SIMD3<Scalar> {
        return (self.minPoint + self.maxPoint) * 0.5
    }
    
    @inlinable
    public var size : SIMD3<Scalar> {
        return self.maxPoint - self.minPoint
    }
    
    @inlinable
    public func contains(point: SIMD3<Scalar>) -> Bool {
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
    public func pointAtExtent(_ extent: Extent) -> SIMD3<Scalar> {
        let useMaxX = extent.rawValue & Extent.MaxXFlag != 0
        let useMaxY = extent.rawValue & Extent.MaxYFlag != 0
        let useMaxZ = extent.rawValue & Extent.MaxZFlag != 0
        
        return SIMD3<Scalar>(useMaxX ? self.maxX : self.minX, useMaxY ? self.maxY : self.minY, useMaxZ ? self.maxZ : self.minZ)
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
    public func intersects(with sphere: Sphere<Scalar>) -> Bool {
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

    @inlinable
    public mutating func combine(with box: AxisAlignedBoundingBox) {
        self.minPoint = pointwiseMin(self.minPoint, box.minPoint)
        self.maxPoint = pointwiseMax(self.maxPoint, box.maxPoint)
    }
    
    @inlinable
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
    @inlinable
    public func transformed(by nodeToSpaceTransform: Matrix4x4<Scalar>) -> AxisAlignedBoundingBox {
        var newMin = SIMD3(repeating: Scalar.infinity)
        var newMax = SIMD3(repeating: -Scalar.infinity)
        
        //Compute all the vertices for the box.
        for xToggle in 0..<2 {
            for yToggle in 0..<2 {
                for zToggle in 0..<2 {
                    let x = xToggle == 0 ? minPoint.x : maxPoint.x;
                    let y = yToggle == 0 ? minPoint.y : maxPoint.y;
                    let z = zToggle == 0 ? minPoint.z : maxPoint.z;
                    let vertex = SIMD3<Scalar>(x, y, z);
                    let transformedVertex = nodeToSpaceTransform.multiplyAndProject(vertex)
                    
                    newMin = pointwiseMin(newMin, transformedVertex)
                    newMax = pointwiseMax(newMax, transformedVertex)
                }
            }
        }
        
        return AxisAlignedBoundingBox(min: newMin, max: newMax)
    }
    
    /**
     * Transforms this bounding box from its local space to the space described by nodeToSpaceTransform.
     * The result is guaranteed to be axis aligned – that is, with no rotation in the destination space.
     * It may or may not have the same width, height, or depth as its source.
     * @param nodeToSpaceTransform - The transformation from local to the destination space.
     * @return - this box in the destination coordinate system.
     */
    @inlinable
    public func transformed(by nodeToSpaceTransform: AffineMatrix<Scalar>) -> AxisAlignedBoundingBox {
        var newMin = SIMD3(repeating: Scalar.infinity)
        var newMax = SIMD3(repeating: -Scalar.infinity)
        
        //Compute all the vertices for the box.
        for xToggle in 0..<2 {
            for yToggle in 0..<2 {
                for zToggle in 0..<2 {
                    let x = xToggle == 0 ? minPoint.x : maxPoint.x;
                    let y = yToggle == 0 ? minPoint.y : maxPoint.y;
                    let z = zToggle == 0 ? minPoint.z : maxPoint.z;
                    let vertex = SIMD4<Scalar>(x, y, z, 1)
                    let transformedVertex = nodeToSpaceTransform * vertex
                    
                    newMin = pointwiseMin(newMin, transformedVertex.xyz)
                    newMax = pointwiseMax(newMax, transformedVertex.xyz)
                }
            }
        }
        
        return AxisAlignedBoundingBox(min: newMin, max: newMax)
    }
    
    @inlinable
    public func boundingSphere(in nodeToSpaceTransform: AffineMatrix<Scalar>, radiusScale: Scalar) -> Sphere<Scalar> {
        
        let centre = self.centre
        let radius = self.diagonal * 0.5
        var transformedCentre = nodeToSpaceTransform * SIMD4<Scalar>(centre, 1)
        
        transformedCentre.w = radius * radiusScale
        
        return Sphere(centreAndRadius: transformedCentre)
    }
    
    @inlinable
    public func maxZForBoundingBoxInSpace(nodeToSpaceTransform : Matrix4x4<Scalar>) -> Scalar {
        
        var maxZ = -Scalar.infinity
        
        //Compute all the vertices for the box.
        for xToggle in 0..<2 {
            for yToggle in 0..<2 {
                for zToggle in 0..<2 {
                    let x = xToggle == 0 ? minPoint.x : maxPoint.x;
                    let y = yToggle == 0 ? minPoint.y : maxPoint.y;
                    let z = zToggle == 0 ? minPoint.z : maxPoint.z;
                    let vertex = SIMD3<Scalar>(x, y, z);
                    let transformedVertex = nodeToSpaceTransform * SIMD4<Scalar>(vertex, 1)
                    
                    if (transformedVertex.z > maxZ) { maxZ = transformedVertex.z; }
                }
            }
        }
        
        return maxZ;
    }
    
    @inlinable
    public static func ==(lhs: AxisAlignedBoundingBox, rhs: AxisAlignedBoundingBox) -> Bool {
        return lhs.minPoint == rhs.minPoint && lhs.maxPoint == rhs.maxPoint
    }

}

@frozen
public struct Cylinder<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable, Codable {
    public var position : SIMD3<Scalar>
    public var end : SIMD3<Scalar>
    public var radius : Scalar
}

@frozen
public struct Disk<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable, Codable {
    public var centre : SIMD3<Scalar>
    public var normal : SIMD3<Scalar>
    public var radius : Scalar
}

@frozen
public struct OrientedBoundingBox<Scalar: SIMDScalar & BinaryFloatingPoint & Real>: Hashable, Codable {
    public var transform : AffineMatrix<Scalar>
    
    @inlinable
    public init(transform: AffineMatrix<Scalar>) {
        self.transform = transform
    }
    
    @inlinable
    public init(aabb: AxisAlignedBoundingBox<Scalar>, inSpace transform: AffineMatrix<Scalar>) {
        let aabbTransform = AffineMatrix<Scalar>.scaleRotateTranslate(scale: aabb.size, rotation: Quaternion.identity, translation: aabb.centre)
        self.init(transform: transform * aabbTransform)
    }
}

@frozen
public struct ProjectedBoundingBox<Scalar: SIMDScalar & BinaryFloatingPoint & Real>: Hashable, Codable {
    public var transform : Matrix4x4<Scalar>
    
    @inlinable
    public init(transform: Matrix4x4<Scalar> = Matrix4x4<Scalar>.identity) {
        self.transform = transform
    }
    
    @inlinable
    public init(aabb: AxisAlignedBoundingBox<Scalar>, inSpace transform: Matrix4x4<Scalar>) {
        let aabbTransform = AffineMatrix<Scalar>.scaleRotateTranslate(scale: aabb.size, rotation: Quaternion.identity, translation: aabb.centre)
        self.init(transform: transform * aabbTransform)
    }
    
    @inlinable
    public init(transform: AffineMatrix<Scalar>) {
        self.transform = Matrix4x4<Scalar>(transform)
    }
    
    @inlinable
    public init(aabb: AxisAlignedBoundingBox<Scalar>, inSpace transform: AffineMatrix<Scalar>) {
        let aabbTransform = AffineMatrix<Scalar>.scaleRotateTranslate(scale: aabb.size, rotation: Quaternion.identity, translation: aabb.centre)
        self.init(transform: transform * aabbTransform)
    }
}

@frozen
public struct Plane<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable, Codable {
    @usableFromInline
    var storage : SIMD4<Scalar>

    @inlinable
    public var normal : SIMD3<Scalar> {
        get {
            return self.storage[SIMD3(0, 1, 2)]
        }
        set {
            self.storage = SIMD4(newValue, self.storage.w)
        }
    }
    
    @inlinable
    public var constant : Scalar {
        get {
            return self.storage.w
        }
        set {
            self.storage.w = newValue
        }
    }
    
    public init(normal: SIMD3<Scalar>, constant: Scalar) {
        self.storage = SIMD4<Scalar>(normal, constant)
    }
}

@frozen
public struct Ray<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable, Codable {
    
    public var origin : SIMD3<Scalar>
    public var direction : SIMD3<Scalar>
    
    @inlinable
    public init(origin: SIMD3<Scalar> = SIMD3<Scalar>(repeating: 0), direction: SIMD3<Scalar> = SIMD3<Scalar>(repeating: 0)) {
        self.origin = origin
        self.direction = direction
    }
    
    @inlinable
    public init(fromScreenSpaceX x: Scalar, y: Scalar, mvp: Matrix4x4<Scalar>) {
        self = Ray(fromScreenSpaceX: x, y: y, inverseMVP: mvp.inverse)
    }
    
    @inlinable
    public init(fromScreenSpaceX x: Scalar, y: Scalar, inverseMVP: Matrix4x4<Scalar>) {
        let ray = Ray(origin: SIMD3<Scalar>(x, y, 0), direction: SIMD3<Scalar>(0, 0, 1))
        let viewRay = inverseMVP * ray
        self = viewRay
    }
    
    @inlinable
    public func at(t: Scalar) -> SIMD3<Scalar> {
        return self.origin + t * self.direction
    }
    
    @inlinable
    public static func *(lhs: Matrix4x4<Scalar>, rhs: Ray) -> Ray {
        var ray = Ray()
        
        let origin = lhs * SIMD4<Scalar>(rhs.origin, 1)
        
        ray.origin = origin.xyz * SIMD3<Scalar>(repeating: 1.0 / origin.w)
        
        let direction = SIMD3<Scalar>(
            lhs[2][0] - (lhs[2][3] * ray.origin.x),
            lhs[2][1] - (lhs[2][3] * ray.origin.y),
            lhs[2][2] - (lhs[2][3] * ray.origin.z)
            )
        ray.direction = normalize(direction)
        return ray
    }
    
    @inlinable
    public func intersectionAt(y: Scalar) -> SIMD3<Scalar>? {
        guard self.direction.y != 0.0 else { return nil }
        let t = (y - self.origin.y) / self.direction.y
        return self.at(t: t)
    }
    
    @inlinable
    public func intersects(with box: AxisAlignedBoundingBox<Scalar>) -> Bool {
        // r.dir is unit direction vector of ray
        let dirFrac = SIMD3<Scalar>(repeating: 1.0) / self.direction
        
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
    
    @inlinable
    public func intersections(with box: AxisAlignedBoundingBox<Scalar>) -> (near: Scalar, far: Scalar)? {
        var t1 = SIMD3<Scalar>()
        var t2 = SIMD3<Scalar>() // vectors to hold the T-values for every direction
        var tNear = -Scalar.infinity;
        var tFar = Scalar.infinity;
        
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

@frozen
public struct Sphere<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable, Codable {
    public var centreAndRadius : SIMD4<Scalar>
    
    @inlinable
    public var centre : SIMD3<Scalar> {
        get {
            return self.centreAndRadius[SIMD3(0, 1, 2)]
        }
        set {
            self.centreAndRadius = SIMD4(newValue, self.centreAndRadius.w)
        }
    }
    
    @inlinable
    public var radius : Scalar {
        get {
            return self.centreAndRadius.w
        }
        set {
            self.centreAndRadius.w = newValue
        }
    }
    
    @inlinable
    public init(centre: SIMD3<Scalar>, radius: Scalar) {
        self.centreAndRadius = SIMD4<Scalar>(centre, radius)
    }
    
    @inlinable
    public init(centreAndRadius: SIMD4<Scalar>) {
        self.centreAndRadius = centreAndRadius
    }
}

@frozen
public struct Triangle<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable, Codable {
    public var v0 : SIMD3<Scalar>
    public var v1 : SIMD3<Scalar>
    public var v2 : SIMD3<Scalar>
}

@frozen
public struct Intersection<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable, Codable {
    public var position : SIMD3<Scalar>
    public var normal : SIMD3<Scalar>
    public var distance : Scalar
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
