//
//  ImGui+ImGuizmo.swift
//  CGRAGame
//
//  Created by Thomas Roughton on 18/05/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

import CDebugDrawTools
import SwiftMath
import Utilities

internal extension ImGui {
    
    static func beginImGuizmoFrame() {
        ImGuizmo_BeginFrame()
    }
    
}

public enum TransformOperation : ImGuizmoOperation.RawValue {
    case translate = 0
    case rotate = 1
    case scale = 2
    case select
}

public enum CoordinateMode : ImGuizmoMode.RawValue {
    case local
    case world
}

public final class ImGuizmo {

    public static func setDrawList() {
        ImGuizmo_SetDrawList()
    }
    
    /// return true if mouse cursor is over any gizmo control (axis, plan or screen component)
    public static var cursorIsOverGizmo : Bool {
        return ImGuizmo_IsOver()
    }
    
    /// return true if cursorIsOverGizmo or if the gizmo is in moving state
    public static var isActive : Bool {
        return ImGuizmo_IsUsing()
    }
    
    public static func setEnabled(_ enabled: Bool) {
        ImGuizmo_Enable(enabled)
    }
    
    public static func setRect(_ rect: Rect) {
        ImGuizmo_SetRect(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
    }
    
    public static func setOrthographic(_ isOrthographic: Bool) {
        ImGuizmo_SetOrthographic(isOrthographic)
    }
    
    /// Render a cube with face color corresponding to face normal. Useful for debug/tests
    public static func drawCube(view: Matrix4x4f, projection: Matrix4x4f, object: Matrix4x4f) {
        var values = (view, projection, object)
        
        withExtendedLifetime(values) {
            ImGuizmo_DrawCube(escapingCastMutablePointer(to: &values.0), escapingCastMutablePointer(to: &values.1), escapingCastMutablePointer(to: &values.2))
        }
    }
    
    /// Render a cube with face color corresponding to face normal. Useful for debug/tests
    public static func drawGrid(view: Matrix4x4f, projection: Matrix4x4f, object: Matrix4x4f, gridSize: Float) {
        var values = (view, projection, object)
        
        withExtendedLifetime(values) {
            ImGuizmo_DrawGrid(escapingCastMutablePointer(to: &values.0), escapingCastMutablePointer(to: &values.1), escapingCastMutablePointer(to: &values.2), gridSize)
        }
    }
    
    public static func manipulate(view: Matrix4x4f, projection: Matrix4x4f, operation: TransformOperation, mode: CoordinateMode, object: inout Matrix4x4f, snap: Vector3f? = nil, localBounds: AxisAlignedBoundingBox? = nil, boundsSnap: Vector3f? = nil) {
        
        let mode = operation == .scale ? .local : mode
        
        var values = (view, projection, object, snap, localBounds, boundsSnap)
        defer {
            object = values.2
        }
        withExtendedLifetime(values) {
            ImGuizmo_Manipulate(escapingCastMutablePointer(to: &values.0), escapingCastMutablePointer(to: &values.1), ImGuizmoOperation(operation.rawValue), ImGuizmoMode(mode.rawValue), escapingCastMutablePointer(to: &values.2), nil, escapingCastMutablePointer(to: &values.3), escapingCastMutablePointer(to: &values.4), escapingCastMutablePointer(to: &values.5))
        }
    }
}
