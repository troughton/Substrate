//
//  SwiftDebugDraw.swift
//  CGRAGame
//
//  Created by Joseph Bennett on 11/05/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

import Foundation
import SwiftMath
import Utilities

@_fixed_layout
public final class DebugDraw {
    
    @_fixed_layout
    public struct DrawStyle {
        public static let defaultStyle : DrawStyle =  DrawStyle(colour: RGBAColour(1), depthEnabled: false, wireframe: false)
        
        public var colour : RGBAColour
        public var depthEnabled : Bool
        public var wireframe : Bool
        
        @inlinable
        public init(colour: RGBAColour, depthEnabled: Bool, wireframe: Bool) {
            self.colour = colour
            self.depthEnabled = depthEnabled
            self.wireframe = wireframe
        }
    }
    
    @_fixed_layout
    public struct DebugVertex {
        public var x : Float
        public var y : Float
        public var z : Float
        public var colour : UInt32
        
        @inlinable
        public init(x: Float, y: Float, z: Float, colour: UInt32) {
            self.x = x
            self.y = y
            self.z = z
            self.colour = colour
        }
        
        @inlinable
        public init(position: Vector4f, colour: UInt32) {
            self.x = position.x
            self.y = position.y
            self.z = position.z
            self.colour = colour
        }
        
        @inlinable
        public init(position: Vector3f, colour: UInt32) {
            self.x = position.x
            self.y = position.y
            self.z = position.z
            self.colour = colour
        }
    }
    
    // Depth enabled vs depth disabled
    @_fixed_layout
    public struct DebugDrawData {
        public let allocator : AllocatorType
        public let points : ExpandingBuffer<DebugVertex>
        public let pointSizes : ExpandingBuffer<Float>
        public let lines : ExpandingBuffer<DebugVertex>
        public let wireframeTriangles : ExpandingBuffer<DebugVertex>
        public let filledTriangles : ExpandingBuffer<DebugVertex>
        // line strips, triangle strips?
        
        @inlinable
        init(allocator: AllocatorType) {
            self.allocator = allocator
            self.points = ExpandingBuffer(allocator: allocator)
            self.pointSizes = ExpandingBuffer(allocator: allocator)
            self.lines = ExpandingBuffer(allocator: allocator)
            self.wireframeTriangles = ExpandingBuffer(allocator: allocator)
            self.filledTriangles = ExpandingBuffer(allocator: allocator)
        }
        
        func clear() {
            self.points.removeAll()
            self.pointSizes.removeAll()
            self.lines.removeAll()
            self.wireframeTriangles.removeAll()
            self.filledTriangles.removeAll()
        }
    }
    
    @_fixed_layout
    public struct DrawData {
        public let depthEnabledData : DebugDrawData
        public let depthDisabledData : DebugDrawData

        @inlinable
        init(allocator: AllocatorType) {
            self.depthEnabledData = DebugDrawData(allocator: allocator)
            self.depthDisabledData = DebugDrawData(allocator: allocator)
        }
        
        @inlinable
        func addCube(transform: AffineMatrix, style: DrawStyle) {
            
            let colour = style.colour.packed
            
            let transformedVertices = [
                Vector4f(-0.5, -0.5, -0.5, 1),
                Vector4f(-0.5, -0.5, 0.5, 1),
                Vector4f(-0.5, 0.5, -0.5, 1),
                Vector4f(-0.5, 0.5, 0.5, 1),
                Vector4f(0.5, -0.5, -0.5, 1),
                Vector4f(0.5, -0.5, 0.5, 1),
                Vector4f(0.5, 0.5, -0.5, 1),
                Vector4f(0.5, 0.5, 0.5, 1),
                ].map {
                    transform * $0
            }
            
            if style.wireframe {
                let list = style.depthEnabled ? self.depthEnabledData.lines : self.depthDisabledData.lines
                
                // yz plane at negative x
                list.line(from: transformedVertices[0], to: transformedVertices[1], colour: colour)
                list.line(from: transformedVertices[0], to: transformedVertices[2], colour: colour)
                list.line(from: transformedVertices[1], to: transformedVertices[3], colour: colour)
                list.line(from: transformedVertices[2], to: transformedVertices[3], colour: colour)
                
                // yz plane at positive x
                list.line(from: transformedVertices[4], to: transformedVertices[5], colour: colour)
                list.line(from: transformedVertices[4], to: transformedVertices[6], colour: colour)
                list.line(from: transformedVertices[5], to: transformedVertices[7], colour: colour)
                list.line(from: transformedVertices[6], to: transformedVertices[7], colour: colour)
                
                // negative x to positive x for each.
                for i in 0..<4 {
                    list.line(from: transformedVertices[i], to: transformedVertices[4 + i], colour: colour)
                }
            } else {
                let list = style.depthEnabled ? self.depthEnabledData.filledTriangles : self.depthDisabledData.filledTriangles
                
                // at negative x
                list.append(DebugDraw.DebugVertex(position: transformedVertices[0], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[1], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[3], colour: colour))
                
                list.append(DebugDraw.DebugVertex(position: transformedVertices[0], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[2], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[3], colour: colour))
                
                // at positive x
                list.append(DebugDraw.DebugVertex(position: transformedVertices[4], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[5], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[7], colour: colour))
                
                list.append(DebugDraw.DebugVertex(position: transformedVertices[4], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[6], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[7], colour: colour))
                
                // at negative y
                list.append(DebugDraw.DebugVertex(position: transformedVertices[0], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[1], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[4], colour: colour))
                
                list.append(DebugDraw.DebugVertex(position: transformedVertices[1], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[4], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[5], colour: colour))
                
                // at positive y
                list.append(DebugDraw.DebugVertex(position: transformedVertices[2], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[3], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[6], colour: colour))
                
                list.append(DebugDraw.DebugVertex(position: transformedVertices[3], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[6], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[7], colour: colour))
                
                // at negative z
                list.append(DebugDraw.DebugVertex(position: transformedVertices[0], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[2], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[4], colour: colour))
                
                list.append(DebugDraw.DebugVertex(position: transformedVertices[2], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[4], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[6], colour: colour))
                
                // at positive z
                list.append(DebugDraw.DebugVertex(position: transformedVertices[1], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[3], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[5], colour: colour))
                
                list.append(DebugDraw.DebugVertex(position: transformedVertices[3], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[6], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[7], colour: colour))
                
            }
        }
        
        @inlinable
        func addPlane(transform: AffineMatrix, style: DrawStyle) {
            let colour = style.colour.packed
            
            let transformedVertices = [
                Vector4f(-1, 0, -1, 1),
                Vector4f(-1, 0, 1, 1),
                Vector4f(1, 0, -1, 1),
                Vector4f(1, 0, 1, 1),
                ].map {
                    transform * $0
            }
            
            if style.wireframe {
                let list = style.depthEnabled ? self.depthEnabledData.lines : self.depthDisabledData.lines
                
                list.line(from: transformedVertices[0], to: transformedVertices[1], colour: colour)
                list.line(from: transformedVertices[0], to: transformedVertices[2], colour: colour)
                list.line(from: transformedVertices[1], to: transformedVertices[3], colour: colour)
                list.line(from: transformedVertices[2], to: transformedVertices[3], colour: colour)
            } else {
                let list = style.depthEnabled ? self.depthEnabledData.filledTriangles : self.depthDisabledData.filledTriangles
                
                list.append(DebugDraw.DebugVertex(position: transformedVertices[0], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[1], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[3], colour: colour))
                
                list.append(DebugDraw.DebugVertex(position: transformedVertices[0], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[2], colour: colour))
                list.append(DebugDraw.DebugVertex(position: transformedVertices[3], colour: colour))
            }
        }
        
        @inlinable
        func addLine(from: Vector3f, to: Vector3f, style: DrawStyle) {
            let colour = style.colour.packed
            let list = style.depthEnabled ? self.depthEnabledData.lines : self.depthDisabledData.lines
            
            list.line(from: from, to: to, colour: colour)
        }
        
        @inlinable
        func addPoint(at position: Vector3f, size: Float, style: DrawStyle) {
            let colour = style.colour.packed
            if style.depthEnabled {
                self.depthEnabledData.points.append(DebugDraw.DebugVertex(position: position, colour: colour))
                self.depthEnabledData.pointSizes.append(size)
            } else {
                self.depthDisabledData.points.append(DebugDraw.DebugVertex(position: position, colour: colour))
                self.depthDisabledData.pointSizes.append(size)
            }
        }
    }
    
    @usableFromInline let drawData : DrawData
    
    @usableFromInline var styleStack : [DrawStyle] = [DrawStyle.defaultStyle]
    @usableFromInline var transformStack : [AffineMatrix] = [AffineMatrix.identity]
    
    @inlinable
    public internal(set) var currentStyle : DrawStyle {
        get {
            return self.styleStack.last!
        }
        set {
            self.styleStack.removeLast()
            self.styleStack.append(newValue)
        }
    }
    
    @inlinable
    public internal(set) var currentTransform : AffineMatrix {
        get {
            return self.transformStack.last!
        }
        set {
            self.transformStack.removeLast()
            self.transformStack.append(newValue)
        }
    }
    
    @inlinable
    public init(allocator: AllocatorType) {
        self.drawData = DrawData(allocator: allocator)
    }
    
    @inlinable
    public func withStyle(style: (DrawStyle) -> DrawStyle, drawCommands: () -> ()) {
        pushStyle(style(self.currentStyle))
        drawCommands()
        popStyle()
    }
    
    @inlinable
    public func withStyle(_ style: DrawStyle, drawCommands: () -> ()) {
        pushStyle(style)
        drawCommands()
        popStyle()
    }
    
    @inlinable
    public func pushStyle() {
        self.pushStyle(self.currentStyle)
    }
    
    @inlinable
    public func pushStyle(_ style: DrawStyle) {
        self.styleStack.append(style)
    }
    
    @inlinable
    public func popStyle() {
        assert(self.styleStack.count > 1, "Unbalanced call to popStyle(). i.e no matching pushStyle() call.")
        
        self.styleStack.removeLast()
    }
    
    @inlinable
    public func pushTransform(_ transform: AffineMatrix) {
        self.transformStack.append(self.currentTransform * transform)
    }
    
    @inlinable
    public func popTransform() {
        assert(self.transformStack.count > 1, "Unbalanced call to popTransform(). i.e no matching pushTransform() call.")
        
        self.transformStack.removeLast()
    }
    
    @inlinable
    public var colour : RGBAColour {
        get {
            return self.currentStyle.colour
        }
        
        set {
            self.styleStack[self.styleStack.endIndex - 1].colour = newValue
        }
    }
    
    @inlinable
    public var depthEnabled : Bool {
        get {
            return self.currentStyle.depthEnabled
        }
        set {
            self.styleStack[self.styleStack.endIndex - 1].depthEnabled = newValue
        }
    }
    
    @inlinable
    public var wireframe : Bool {
        get {
            return self.currentStyle.wireframe
        }
        set {
            self.styleStack[self.styleStack.endIndex - 1].wireframe = newValue
        }
    }
    
    @inlinable
    public func point(position: Vector3f, size: Float = 1.0) {
        let transformedPosition = self.currentTransform * vec4(position, 1)
        
        self.drawData.addPoint(at: transformedPosition.xyz, size: size, style: self.currentStyle)
    }
    
    @inlinable
    public func point(position: Vector3f, size: Float = 1.0, style: DrawStyle) {
        withStyle(style) {
            self.point(position: position, size: size)
        }
    }
    
    @inlinable
    public func line(from: Vector3f, to: Vector3f) {
        let transformedFrom = (self.currentTransform * vec4(from, 1)).xyz
        let transformedTo = (self.currentTransform * vec4(to, 1)).xyz
        
        self.drawData.addLine(from: transformedFrom, to: transformedTo, style: self.currentStyle)
    }
    
    @inlinable
    public func line(from: Vector3f, to: Vector3f, style: DrawStyle) {
        withStyle(style) {
            self.line(from: from, to: to)
        }
    }
    
    @inlinable
    func cone(centre: Vector3f, forward: Vector3f, radius: Float, angle: Angle, sphereCapped: Bool) {
        
        self.pushTransform(AffineMatrix.lookAtInv(eye: centre, at: centre + forward))
        defer { self.popTransform() }
        
        let angleStep = 15 // degrees
        
        let endCapRadius = radius * sin(angle)
        let endCapDistance = radius * cos(angle)
        
        let flatCapCentre = Vector3f(0, 0, endCapDistance)
        let sphereCapCentre = Vector3f(0, 0, radius)
        
        var startCapPoint : Vector3f? = nil
        var previousCapPoint : Vector3f? = nil
        
        var i = angleStep
        while i <= 360 {
            defer { i += angleStep }
            
            let currentAngle = deg(Float(i))
            
            let c = cos(currentAngle)
            let s = sin(currentAngle)
            
            let edgePoint = flatCapCentre + endCapRadius * Vector3f(c, s, 0.0)
            
            if startCapPoint == nil {
                startCapPoint = edgePoint
            }
            
            self.line(from: Vector3f.zero, to: edgePoint)
            
            if let previousCapPoint = previousCapPoint {
                self.line(from: edgePoint, to: previousCapPoint)
            }
            previousCapPoint = edgePoint
            
            if sphereCapped {
                var previousPoint = edgePoint
                
                for j in (1...3).reversed() {
                    let sliceAngle = angle * Float(j)/4.0
                    let sliceRadius = radius * sin(sliceAngle)
                    let nextPoint = Vector3f(sliceRadius * c, sliceRadius * s, radius * cos(sliceAngle))
                    
                    self.line(from: previousPoint, to: nextPoint)
                    previousPoint = nextPoint
                }
                
                self.line(from: previousPoint, to: sphereCapCentre)
                
            } else {
                self.line(from: edgePoint, to: flatCapCentre)
            }
            
        }
        
        self.line(from: startCapPoint!, to: previousCapPoint!)
        
    }
    
    @inlinable
    public func sphereCappedCone(sphere: Sphere, forward: Vector3f, angle: Angle) {
        self.cone(centre: sphere.centre, forward: forward, radius: sphere.radius, angle: angle, sphereCapped: true)
    }
    
    @inlinable
    public func sphereCappedCone(sphere: Sphere, forward: Vector3f, angle: Angle, style: DrawStyle) {
        withStyle(style) {
            self.sphereCappedCone(sphere: sphere, forward: forward, angle: angle)
        }
    }
    
    @inlinable
    public func cone(centre: Vector3f, forward: Vector3f, length: Float, angle: Angle) {
        let radius = length / cos(angle)
        self.cone(centre: centre, forward: forward, radius: radius, angle: angle, sphereCapped: false)
    }
    
    @inlinable
    public func cone(centre: Vector3f, forward: Vector3f, length: Float, angle: Angle, style: DrawStyle) {
        withStyle(style) {
            self.cone(centre: centre, forward: forward, length: length, angle: angle)
        }
    }
    
    @inlinable
    public func sphere(_ sphere: Sphere) {
        assert(self.currentStyle.wireframe == true, "Filled spheres are currently unsupported.")
        
        let stepSize = 15
        
        var radiusVec = Vector3f(0, 0, sphere.radius)
        var cache = [Vector3f](repeating: sphere.centre + radiusVec, count: 360/stepSize)
        
        var lastPoint = Vector3f(0)
        var temp = Vector3f(0)
        
        var i = stepSize
        while i <= 360 {
            defer { i += stepSize }
            
            let angle = Float(i) * Float.pi / 180.0
            let s = sin(angle)
            let c = cos(angle)
            
            lastPoint.x = sphere.centre.x
            lastPoint.y = sphere.centre.y + sphere.radius * s
            lastPoint.z = sphere.centre.z + sphere.radius * c
            
            var n = 0
            var j = stepSize
            while j <= 360 {
                defer { j += stepSize; n += 1 }
                
                let jAngle = Float(j) * Float.pi / 180.0
                
                temp.x = sphere.centre.x + sin(jAngle) * sphere.radius * s
                temp.y = sphere.centre.y + cos(jAngle) * sphere.radius * s
                temp.z = lastPoint.z
                
                self.line(from: lastPoint, to: temp)
                self.line(from: lastPoint, to: cache[n])
                
                cache[n] = lastPoint
                lastPoint = temp
            }
        }
    }
    
    @inlinable
    public func sphere(_ sphere: Sphere, style: DrawStyle) {
        withStyle(style) {
            self.sphere(sphere)
        }
    }
    
    @inlinable
    public func box(position: Vector3f, scale: Vector3f, style: DrawStyle? = nil) {
        let transform = self.currentTransform * AffineMatrix.scaleRotateTranslate(scale: scale, rotation: Quaternion.identity, translation: position)
        self.box(transform: transform, style: style)
    }
    
    @inlinable
    public func box(transform: AffineMatrix, style: DrawStyle? = nil) {
        self.drawData.addCube(transform: transform, style: style ?? self.currentStyle)
    }
    
    @inlinable
    public func orientedBox(_ oobb: OrientedBoundingBox, style: DrawStyle? = nil) {
        self.box(transform: oobb.transform, style: style)
    }
    
    @inlinable
    public func projectedBox(_ oobb: ProjectedBoundingBox, style: DrawStyle? = nil) {
        let projectedVertices = [
             Vector3f(-1, -1, -1),
             Vector3f(-1, -1, 1),
             Vector3f(-1, 1, -1),
             Vector3f(-1, 1, 1),
             Vector3f(1, -1, -1),
             Vector3f(1, -1, 1),
             Vector3f(1, 1, -1),
             Vector3f(1, 1, 1),
        ].map { oobb.transform.multiplyAndProject($0) }
        
        // yz plane at negative x
        self.line(from: projectedVertices[0], to: projectedVertices[1], style: style ?? self.currentStyle)
        self.line(from: projectedVertices[0], to: projectedVertices[2], style: style ?? self.currentStyle)
        self.line(from: projectedVertices[1], to: projectedVertices[3], style: style ?? self.currentStyle)
        self.line(from: projectedVertices[2], to: projectedVertices[3], style: style ?? self.currentStyle)
        
        // yz plane at positive x
        self.line(from: projectedVertices[4], to: projectedVertices[5], style: style ?? self.currentStyle)
        self.line(from: projectedVertices[4], to: projectedVertices[6], style: style ?? self.currentStyle)
        self.line(from: projectedVertices[5], to: projectedVertices[7], style: style ?? self.currentStyle)
        self.line(from: projectedVertices[6], to: projectedVertices[7], style: style ?? self.currentStyle)
        
        // negative x to positive x for each.
        for i in 0..<4 {
            self.line(from: projectedVertices[i], to: projectedVertices[4 + i], style: style ?? self.currentStyle)
        }
    }
    
    @inlinable
    public func axisAlignedBox(_ aabb: AxisAlignedBoundingBox, style: DrawStyle? = nil) {
        let transform = self.currentTransform * AffineMatrix.scaleRotateTranslate(scale: aabb.size, rotation: Quaternion.identity, translation: aabb.centre)
        self.box(transform: transform, style: style)
    }
   
    @inlinable
    public func plane(position: Vector3f, normal: Vector3f, scale: Vector3f, style: DrawStyle? = nil) {
        let unitNormal = vec3(0, 1, 0)
        let normal = normal.normalized
        
        let rotationAxis = cross(unitNormal, normal)
        let rotationAmount = acos(dot(unitNormal, normal))
        
        let rotation = Quaternion.init(angle: Angle(radians: rotationAmount), axis: rotationAxis)
        
        let transform = self.currentTransform * AffineMatrix.scaleRotateTranslate(scale: scale, rotation: rotation, translation: position)
        
        self.drawData.addPlane(transform: transform, style: style ?? self.currentStyle)
    }
    
    @inlinable
    public func grid(position: Vector3f, xDir: Vector3f, yDir: Vector3f, size: Vector2f, step: Vector2f = Vector2f(1.0), style: DrawStyle) {
        withStyle(style) {
            self.grid(position: position, xDir: xDir, yDir: yDir, size: size, step: step)
        }
    }
    
    @inlinable
    public func grid(position: Vector3f, xDir: Vector3f, yDir: Vector3f, size: Vector2f, step: Vector2f = Vector2f(1.0)) {
        
        let xSteps = Int(round(size.x / step.x))
        let ySteps = Int(round(size.y / step.y))
        
        var start = position //FIXME: Should be a single expression, but 'expression too complex'
        start -= (size.x * 0.5 * xDir)
        start -= (size.y * 0.5 * yDir)
        
        let yEndOffset = size.x * xDir
        let xEndOffset = size.y * yDir
        
        for x in 0...xSteps {
            let startOffset = step.x * Float(x) * xDir
            let startPoint = start + startOffset
            let endPoint = startPoint + xEndOffset
            self.line(from: startPoint, to: endPoint)
        }
        
        for y in 0...ySteps {
            let startOffset = step.y * Float(y) * yDir
            let startPoint = start + startOffset
            let endPoint = startPoint + yEndOffset
            self.line(from: startPoint, to: endPoint)
        }
        
    }
    
    @inlinable
    public func flush() -> DrawData {
        assert(self.styleStack.count == 1, "pushStyle() without corresponding popStyle()")
        
        return self.drawData
    }
}

extension ExpandingBuffer where Element == DebugDraw.DebugVertex {
    @inlinable
    public func line(from: Vector4f, to: Vector4f, colour: UInt32) {
        self.append(DebugDraw.DebugVertex(x: from.x, y: from.y, z: from.z, colour: colour))
        self.append(DebugDraw.DebugVertex(x: to.x, y: to.y, z: to.z, colour: colour))
    }
    
    @inlinable
    public func line(from: Vector3f, to: Vector3f, colour: UInt32) {
        self.append(DebugDraw.DebugVertex(x: from.x, y: from.y, z: from.z, colour: colour))
        self.append(DebugDraw.DebugVertex(x: to.x, y: to.y, z: to.z, colour: colour))
    }
}
