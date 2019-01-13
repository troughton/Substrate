//
//  DebugDraw+PhysX.swift
//  DrawTools
//
//  Created by Thomas Roughton on 31/12/18.
//

#if canImport(PhysX)
import PhysX
import SwiftMath

extension PxScene {
    
    public func renderDebugVisualisation(debugDraw: DebugDraw, projectionMatrix: Matrix4x4f) {
        let renderBuffer = self.renderBuffer
        
        for line in renderBuffer.lines {
            debugDraw.drawData.depthDisabledData.lines.append(DebugDraw.DebugVertex(x: line.handle.pos0.x, y: line.handle.pos0.y, z: line.handle.pos0.z, colour: line.handle.color0))
            debugDraw.drawData.depthDisabledData.lines.append(DebugDraw.DebugVertex(x: line.handle.pos1.x, y: line.handle.pos1.y, z: line.handle.pos1.z, colour: line.handle.color1))
        }
        
        for triangle in renderBuffer.triangles {
            debugDraw.drawData.depthDisabledData.wireframeTriangles.append(DebugDraw.DebugVertex(x: triangle.handle.pos0.x, y: triangle.handle.pos0.y, z: triangle.handle.pos0.z, colour: triangle.handle.color0))
            debugDraw.drawData.depthDisabledData.wireframeTriangles.append(DebugDraw.DebugVertex(x: triangle.handle.pos1.x, y: triangle.handle.pos1.y, z: triangle.handle.pos1.z, colour: triangle.handle.color1))
            debugDraw.drawData.depthDisabledData.wireframeTriangles.append(DebugDraw.DebugVertex(x: triangle.handle.pos2.x, y: triangle.handle.pos2.y, z: triangle.handle.pos2.z, colour: triangle.handle.color2))
        }
        
        for point in renderBuffer.points {
            debugDraw.drawData.depthDisabledData.points.append(DebugDraw.DebugVertex(x: point.handle.pos.x, y: point.handle.pos.y, z: point.handle.pos.z, colour: point.handle.color))
        }
        
        let drawList = ImGui.windowDrawList()
        let windowSize = ImGui.windowSize
        for text in renderBuffer.texts {
            let locationNDC = projectionMatrix.multiplyAndProject(Vector3f(text.handle.position.x, text.handle.position.y, text.handle.position.z))
            let location2D = (locationNDC.xy * 0.5 + 0.5) * windowSize
            
            drawList.addText(text.handle.string!, position: location2D, colour: text.handle.color)
            
        }
    }
}

#endif
