//
//  Primitives.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 18/11/16.
//
//

import Swift
import RealModule
import SubstrateUtilities

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
    public static var unitRect: Rect<Scalar> {
        return Rect(origin: SIMD2<Scalar>.zero, size: SIMD2<Scalar>.one)
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
            self.size = newValue - self.origin
        }
    }
    
    @inlinable
    public var centre: SIMD2<Scalar> {
        get {
            return self.origin + self.size * 0.5
        }
    }
    
    @inlinable
    public var area: Scalar {
        get {
            return self.width * self.height
        }
    }
    
    @inlinable
    public func contains(point: SIMD2<Scalar>) -> Bool {
        let maxPoint = self.origin + self.size
        return all(point .>= self.origin) && all(point .<= maxPoint)
    }
    
    @inlinable
    public func contains(rect: Rect<Scalar>) -> Bool {
        return self.union(with: rect) == self
    }
    
    @inlinable
    public func intersects(with otherRect: Rect) -> Bool {
        return all((self.origin + self.size .>= otherRect.origin) .& (otherRect.origin + otherRect.size .>= self.origin))
    }
    
    @inlinable
    public func intersects(with otherRect: Rect, transformedBy transform: RectTransform<Scalar>) -> Bool {
        return self.intersects(with: otherRect.transformed(by: transform))
    }
    
    @inlinable
    public func intersects(with otherRect: Rect, transformedBy transform: AffineMatrix2D<Scalar>) -> Bool {
        func project(point p: SIMD2<Scalar>, onto axis: SIMD2<Scalar>, minVal: inout Scalar, maxVal: inout Scalar) {
            let projected = dot(axis, p)
            minVal = min(minVal, projected)
            maxVal = max(maxVal, projected)
        }

        func overlapsOnAxis(_ axis: SIMD2<Scalar>, pointsA: Array4<SIMD2<Scalar>>, pointsB: Array4<SIMD2<Scalar>>) -> Bool {
            var minA = Scalar.infinity
            var maxA = -Scalar.infinity

            for point in pointsA {
                project(point: point, onto: axis, minVal: &minA, maxVal: &maxA)
            }

            var minB = Scalar.infinity
            var maxB = -Scalar.infinity

            for point in pointsB {
                project(point: point, onto: axis, minVal: &minB, maxVal: &maxB)
            }

            return (minA <= maxB) && (maxA >= minB)
        }
        
        let selfMaxPoint = self.maxPoint
        var pointsSelf = Array4(repeating: SIMD2<Scalar>.zero)
        pointsSelf[0] = self.minPoint
        pointsSelf[1] = SIMD2(self.minPoint.x, selfMaxPoint.y)
        pointsSelf[2] = selfMaxPoint
        pointsSelf[3] = SIMD2(selfMaxPoint.x, self.minPoint.y)
        
        let otherMaxPoint = otherRect.maxPoint
        var pointsOther = Array4(repeating: SIMD2<Scalar>.zero)
        pointsOther[0] = transform.transform(point: otherRect.minPoint)
        pointsOther[1] = transform.transform(point: SIMD2(otherRect.minPoint.x, otherMaxPoint.y))
        pointsOther[2] = transform.transform(point: otherMaxPoint)
        pointsOther[3] = transform.transform(point: SIMD2(otherMaxPoint.x, otherRect.minPoint.y))
        
        
        // Separating axis theorem: there must be overlap on every axis. First, check the X and Y axes.
        
        if (!overlapsOnAxis(SIMD2(1, 0), pointsA: pointsSelf, pointsB: pointsOther)) {
            return false
        }
        
        if (!overlapsOnAxis(SIMD2(0, 1), pointsA: pointsSelf, pointsB: pointsOther)) {
            return false
        }
        
        let tangentA = pointsOther[1] - pointsOther[0] // Local Y axis
        let normalA = SIMD2(-tangentA.y, tangentA.x)
        
        if (!overlapsOnAxis(normalA, pointsA: pointsSelf, pointsB: pointsOther)) {
            return false
        }
        
        let tangentB = pointsOther[2] - pointsOther[1] // Local X axis
        let normalB = SIMD2(-tangentB.y, tangentB.x)
        
        if (!overlapsOnAxis(normalB, pointsA: pointsSelf, pointsB: pointsOther)) {
            return false
        }
        
        return true
    }
    
    
    @inlinable
    public func union(with otherRect: Rect) -> Rect {
        return Rect(minPoint: pointwiseMin(self.minPoint, otherRect.minPoint), maxPoint: pointwiseMax(self.maxPoint, otherRect.maxPoint))
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

extension Rect: @unchecked Sendable where Scalar: Sendable {}

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
        self.size = maxPoint &- minPoint &+ .one // We include maxPoint.
    }
    
    @inlinable
    public static var unitRect: Rect<Scalar> {
        return Rect(origin: SIMD2<Scalar>.zero, size: SIMD2<Scalar>.one)
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
            return self.origin &+ self.size &- .one
        }
        set {
            self.size = newValue &- self.origin &+ .one
        }
    }
    
    @inlinable
    public var area: Scalar {
        get {
            return self.width * self.height
        }
    }
    
    @inlinable
    public func contains(point: SIMD2<Scalar>) -> Bool {
        let maxPoint = self.origin &+ self.size
        return all(point .>= self.origin) && all(point .<= maxPoint)
    }
    
    @inlinable
    public func contains(rect: Rect<Scalar>) -> Bool {
        return self.union(with: rect) == self
    }

    @inlinable
    public func intersects(with otherRect: Rect) -> Bool {
        return all((self.origin &+ self.size .>= otherRect.origin) .& (otherRect.origin &+ otherRect.size .>= self.origin))
    }
    
    @inlinable
    public func union(with otherRect: Rect) -> Rect {
        return Rect(minPoint: pointwiseMin(self.minPoint, otherRect.minPoint), maxPoint: pointwiseMax(self.maxPoint, otherRect.maxPoint))
    }
}

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
    public init<S: Sequence>(bounding sequence: S) where S.Element == SIMD3<Scalar> {
        self = .baseBox
        for element in sequence {
            self.expandToInclude(point: element)
        }
    }
    
    @inlinable
    public mutating func expand(by factor: Scalar) {
        self.minPoint -= SIMD3<Scalar>(repeating: factor)
        self.maxPoint += SIMD3<Scalar>(repeating: factor)
    }
    
    @inlinable
    public mutating func expandToInclude(point: SIMD3<Scalar>) {
        self.minPoint = pointwiseMin(point, self.minPoint)
        self.maxPoint = pointwiseMax(point, self.maxPoint)
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
    public var minX : Scalar { get { return self.minPoint.x } set { self.minPoint.x = newValue } }
    @inlinable
    public var minY : Scalar { get { return self.minPoint.y } set { self.minPoint.y = newValue } }
    @inlinable
    public var minZ : Scalar { get { return self.minPoint.z } set { self.minPoint.z = newValue } }
    @inlinable
    public var maxX : Scalar { get { return self.maxPoint.x } set { self.maxPoint.x = newValue } }
    @inlinable
    public var maxY : Scalar { get { return self.maxPoint.y } set { self.maxPoint.y = newValue } }
    @inlinable
    public var maxZ : Scalar { get { return self.maxPoint.z } set { self.maxPoint.z = newValue } }
    
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
        
        // Compute all the vertices for the box.
        let process: (_ vertex: SIMD3<Scalar>) -> () = { vertex in
            let transformedVertex = nodeToSpaceTransform.multiplyAndProject(vertex)
            
            newMin = pointwiseMin(newMin, transformedVertex)
            newMax = pointwiseMax(newMax, transformedVertex)
        }
        
        process(SIMD3(minPoint.x, minPoint.y, minPoint.z))
        process(SIMD3(minPoint.x, minPoint.y, maxPoint.z))
        process(SIMD3(minPoint.x, maxPoint.y, minPoint.z))
        process(SIMD3(minPoint.x, maxPoint.y, maxPoint.z))
        process(SIMD3(maxPoint.x, minPoint.y, minPoint.z))
        process(SIMD3(maxPoint.x, minPoint.y, maxPoint.z))
        process(SIMD3(maxPoint.x, maxPoint.y, minPoint.z))
        process(SIMD3(maxPoint.x, maxPoint.y, maxPoint.z))
        
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
        
        let process: (_ vertex: SIMD3<Scalar>) -> () = { vertex in
            let transformedVertex = nodeToSpaceTransform.transform(point: vertex)
            
            newMin = pointwiseMin(newMin, transformedVertex)
            newMax = pointwiseMax(newMax, transformedVertex)
        }
        
        process(SIMD3(minPoint.x, minPoint.y, minPoint.z))
        process(SIMD3(minPoint.x, minPoint.y, maxPoint.z))
        process(SIMD3(minPoint.x, maxPoint.y, minPoint.z))
        process(SIMD3(minPoint.x, maxPoint.y, maxPoint.z))
        process(SIMD3(maxPoint.x, minPoint.y, minPoint.z))
        process(SIMD3(maxPoint.x, minPoint.y, maxPoint.z))
        process(SIMD3(maxPoint.x, maxPoint.y, minPoint.z))
        process(SIMD3(maxPoint.x, maxPoint.y, maxPoint.z))
        
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

extension AxisAlignedBoundingBox: @unchecked Sendable where Scalar: Sendable {}

public struct Cylinder<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable, Codable {
    public var position : SIMD3<Scalar>
    public var end : SIMD3<Scalar>
    public var radius : Scalar
    
    @inlinable
    public init(position: SIMD3<Scalar>, end: SIMD3<Scalar>, radius: Scalar) {
        self.position = position
        self.end = end
        self.radius = radius
    }
}

extension Cylinder: @unchecked Sendable where Scalar: Sendable {}

public struct Disk<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable, Codable {
    public var centre : SIMD3<Scalar>
    public var normal : SIMD3<Scalar>
    public var radius : Scalar
    
    @inlinable
    public init(centre: SIMD3<Scalar>, normal: SIMD3<Scalar>, radius: Scalar) {
        self.centre = centre
        self.normal = normal
        self.radius = radius
    }
}

extension Disk : @unchecked Sendable where Scalar: Sendable {}

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

extension OrientedBoundingBox: @unchecked Sendable where Scalar: Sendable {}

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

extension ProjectedBoundingBox: @unchecked Sendable where Scalar: Sendable {}

public struct Plane<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable {
    public var equation : SIMD4<Scalar>

    @inlinable
    public var normal : SIMD3<Scalar> {
        get {
            return self.equation[SIMD3(0, 1, 2)]
        }
        set {
            self.equation = SIMD4(newValue, self.equation.w)
        }
    }
    
    @inlinable
    public var constant : Scalar {
        get {
            return self.equation.w
        }
        set {
            self.equation.w = newValue
        }
    }
    
    @inlinable
    public init(equation: SIMD4<Scalar>) {
        self.equation = equation
    }
    
    @inlinable
    public init(normal: SIMD3<Scalar>, constant: Scalar) {
        self.equation = SIMD4<Scalar>(normal, constant)
    }
    
    @inlinable
    public init(point: SIMD3<Scalar>, normal: SIMD3<Scalar>) {
        self.equation = SIMD4<Scalar>(normal, -dot(normal, point))
    }
    
    @inlinable
    public func project(point: SIMD3<Scalar>) -> SIMD3<Scalar> {
        return point - self.vector(to: point)
    }
    
    @inlinable
    public func vector(to point: SIMD3<Scalar>) -> SIMD3<Scalar> {
        return dot(self.equation, SIMD4(point, 1)) * self.normal
    }
    
    @inlinable
    public func distance(to point: SIMD3<Scalar>) -> Scalar {
        return abs(dot(self.equation, SIMD4(point, 1))) / self.normal.length
    }
    
    // Plane transformed by matrix: https://stackoverflow.com/a/48408289
    @inlinable
    public static func *(matrix: AffineMatrix<Scalar>, plane: Plane<Scalar>) -> Plane<Scalar> {
        return Plane(equation: Matrix4x4(matrix.inverse).transpose * plane.equation)
    }
    
    // Plane transformed by matrix: https://stackoverflow.com/a/48408289
    @inlinable
    public static func *(matrix: Matrix4x4<Scalar>, plane: Plane<Scalar>) -> Plane<Scalar> {
        return Plane(equation: matrix.inverse.transpose * plane.equation)
    }
}

extension Plane: @unchecked Sendable where Scalar: Sendable {}

extension Plane: Codable {
    @inlinable
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.equation = try container.decode(SIMD4<Scalar>.self)
    }
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.equation)
    }
}

public struct Ray<Scalar: SIMDScalar & BinaryFloatingPoint>: Hashable {
    public var origin : SIMD3<Scalar>
    public var direction : SIMD3<Scalar> {
        didSet {
            self._inverseDirection = 1.0 / self.direction
        }
    }
    @usableFromInline var _inverseDirection: SIMD3<Scalar>
    
    @inlinable
    public var inverseDirection : SIMD3<Scalar> {
        return self._inverseDirection
    }
    
    @inlinable
    public init(origin: SIMD3<Scalar> = SIMD3<Scalar>(repeating: 0), direction: SIMD3<Scalar> = SIMD3<Scalar>(0, 0, 1)) {
        self.origin = origin
        self.direction = direction
        self._inverseDirection = 1.0 / direction
    }
    
    @inlinable
    public func at(t: Scalar) -> SIMD3<Scalar> {
        return self.origin + t * self.direction
    }
    
    @inlinable
    public func intersectionAt(y: Scalar) -> SIMD3<Scalar>? {
        guard self.direction.y != 0.0 else { return nil }
        let t = (y - self.origin.y) * self.inverseDirection.y
        return self.at(t: t)
    }
    
    @inlinable
    public func intersections(with box: AxisAlignedBoundingBox<Scalar>) -> (near: Scalar, far: Scalar)? {
        var t1 = SIMD3<Scalar>()
        var t2 = SIMD3<Scalar>() // vectors to hold the T-values for every direction
        var tNear = -Scalar.infinity
        var tFar = Scalar.infinity
        
        for i in 0..<3 { //we test slabs in every direction
            if (self.direction[i] == 0) { // ray parallel to planes in this direction
                if ((self.origin[i] < box.minPoint[i]) || (self.origin[i] > box.maxPoint[i])) {
                    return nil // parallel AND outside box : no intersection possible
                }
            } else { // ray not parallel to planes in this direction
                t1[i] = (box.minPoint[i] - self.origin[i]) * self.inverseDirection[i];
                t2[i] = (box.maxPoint[i] - self.origin[i]) * self.inverseDirection[i];
                
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
    
    @inlinable
    public func minIntersectionT(with box: AxisAlignedBoundingBox<Scalar>, intersectionTUpperLimit: Scalar = .infinity) -> Scalar? {
        let minOffset = (box.minPoint - self.origin) * self.inverseDirection
        let maxOffset = (box.maxPoint - self.origin) * self.inverseDirection
        
        let tMinVector = pointwiseMin(minOffset, maxOffset)
        let tMin = max(max(tMinVector.x, tMinVector.y), tMinVector.z)
        
        if tMin >= intersectionTUpperLimit {
            return nil
        }
        
        let tMaxVector = pointwiseMax(minOffset, maxOffset)
        let tMax = min(min(tMaxVector.x, tMaxVector.y), tMaxVector.z)
        
        // if tmax < 0, ray (line) is intersecting AABB, but the whole AABB is behind us
        if tMax < 0 || tMin > tMax {
            return nil
        }
        
        return tMin
    }
    
    @inlinable
    public func intersects(with box: AxisAlignedBoundingBox<Scalar>, intersectionTUpperLimit: Scalar = .infinity) -> Bool {
        return self.minIntersectionT(with: box, intersectionTUpperLimit: intersectionTUpperLimit) != nil
    }
    
    @inlinable
    public func intersections(with sphere: Sphere<Scalar>) -> (near: Scalar, far: Scalar)? {
        // Wikipedia: https://en.wikipedia.org/wiki/Line–sphere_intersection
        
        let rayOffset = self.origin
        let directionTerm = dot(self.direction, rayOffset)
        
        let discriminantSq = directionTerm * directionTerm - dot(rayOffset, rayOffset) + sphere.radius * sphere.radius
        
        if discriminantSq < 0 {
            return nil
        }
        
        let discriminant = discriminantSq.squareRoot()
        
        let t2 = -directionTerm - discriminant
        let t1 = -directionTerm + discriminant
        return (t2, t1)
    }
    
    @inlinable
    public func minIntersectionT(with sphere: Sphere<Scalar>, intersectionTUpperLimit: Scalar = .infinity) -> Scalar? {
        // Wikipedia: https://en.wikipedia.org/wiki/Line–sphere_intersection
        
        let rayOffset = self.origin
        let directionTerm = dot(self.direction, rayOffset)
        
        let discriminantSq = directionTerm * directionTerm - dot(rayOffset, rayOffset) + sphere.radius * sphere.radius
        
        if discriminantSq < 0 {
            return nil
        }
        
        let discriminant = discriminantSq.squareRoot()
        
        let t2 = -directionTerm - discriminant
        if t2 < intersectionTUpperLimit {
            if t2 >= 0 {
                return t2
            } else {
                let t1 = -directionTerm + discriminant
                if t1 >= 0 && t1 < intersectionTUpperLimit {
                    return t1
                }
            }
        }
        return nil
    }
    
    @inlinable
    public func intersects(with sphere: Sphere<Scalar>, intersectionTUpperLimit: Scalar = .infinity) -> Bool {
        return self.minIntersectionT(with: sphere, intersectionTUpperLimit: intersectionTUpperLimit) != nil
    }
    
    @inlinable
    public func intersectionT(with plane: Plane<Scalar>) -> Scalar {
        return -dot(plane.equation, SIMD4(self.origin, 1)) / dot(plane.equation.xyz, self.direction)
    }
    
    @inlinable
    public static func *(lhs: AffineMatrix<Scalar>, rhs: Ray<Scalar>) -> Ray<Scalar> {
        return Ray(origin: lhs.transform(point: rhs.origin), direction: lhs.transform(direction: rhs.direction))
    }
    
    @inlinable
    public static func *(lhs: Matrix4x4<Scalar>, rhs: Ray<Scalar>) -> Ray<Scalar> {
        return Ray(origin: lhs.transform(point: rhs.origin).xyz, direction: lhs.transform(direction: rhs.direction).xyz)
    }
}

extension Ray: @unchecked Sendable where Scalar: Sendable {}

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

extension Sphere: @unchecked Sendable where Scalar: Sendable {}

public struct Line<Vertex> {
    public var v0 : Vertex
    public var v1 : Vertex
    
    @inlinable
    public init(_ v0: Vertex, _ v1: Vertex) {
        self.v0 = v0
        self.v1 = v1
    }
    
    @inlinable
    public init(v0: Vertex, v1: Vertex) {
        self.v0 = v0
        self.v1 = v1
    }
    
    @inlinable
    public subscript(i: Int) -> Vertex {
        get {
            switch i {
            case 0:
                return self.v0
            case 1:
                return self.v1
            default:
                preconditionFailure("Index \(i) is out of bounds.")
            }
        }
        set {
            switch i {
            case 0:
                self.v0 = newValue
            case 1:
                self.v1 = newValue
            default:
                preconditionFailure("Index \(i) is out of bounds.")
            }
        }
    }
}

extension Line: Equatable where Vertex: Equatable {}
extension Line: Hashable where Vertex: Hashable {}
extension Line: Encodable where Vertex: Encodable {}
extension Line: Decodable where Vertex: Decodable {}
extension Line: @unchecked Sendable where Vertex: Sendable {}

public struct Triangle<Vertex> {
    public var v0 : Vertex
    public var v1 : Vertex
    public var v2 : Vertex
    
    @inlinable
    public init(_ v0: Vertex, _ v1: Vertex, _ v2: Vertex) {
        self.v0 = v0
        self.v1 = v1
        self.v2 = v2
    }
    
    @inlinable
    public init(v0: Vertex, v1: Vertex, v2: Vertex) {
        self.v0 = v0
        self.v1 = v1
        self.v2 = v2
    }
    
    @inlinable
    public subscript(i: Int) -> Vertex {
        get {
            switch i {
            case 0:
                return self.v0
            case 1:
                return self.v1
            case 2:
                return self.v2
            default:
                preconditionFailure("Index \(i) is out of bounds.")
            }
        }
        set {
            switch i {
            case 0:
                self.v0 = newValue
            case 1:
                self.v1 = newValue
            case 2:
                self.v2 = newValue
            default:
                preconditionFailure("Index \(i) is out of bounds.")
            }
        }
    }
}

extension Triangle: Equatable where Vertex: Equatable {}
extension Triangle: Hashable where Vertex: Hashable {}
extension Triangle: Encodable where Vertex: Encodable {}
extension Triangle: Decodable where Vertex: Decodable {}
extension Triangle: @unchecked Sendable where Vertex: Sendable {}

extension AffineMatrix {
    @inlinable
    public func transform(positions: Triangle<SIMD3<Scalar>>) -> Triangle<SIMD3<Scalar>> {
        var result = positions
        result.v0 = self.transform(point: positions.v0)
        result.v1 = self.transform(point: positions.v1)
        result.v2 = self.transform(point: positions.v2)
        return result
    }
    
    @inlinable
    public func transform(tangentDirections directions: Triangle<SIMD3<Scalar>>) -> Triangle<SIMD3<Scalar>> {
        var result = directions
        result.v0 = self.transform(direction: directions.v0)
        result.v1 = self.transform(direction: directions.v1)
        result.v2 = self.transform(direction: directions.v2)
        return result
    }
    
    @inlinable
    public func transform(normalDirections directions: Triangle<SIMD3<Scalar>>) -> Triangle<SIMD3<Scalar>> {
        var result = directions
        let matrix = Matrix3x3(self).inverse.transpose
        result.v0 = matrix * directions.v0
        result.v1 = matrix * directions.v1
        result.v2 = matrix * directions.v2
        return result
    }
}

public enum Axis: Hashable, Sendable {
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
