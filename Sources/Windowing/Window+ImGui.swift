//
//  Window+ImGui.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 6/12/16.
//
//

import CDebugDrawTools
import DrawTools
import SwiftMath
import Dispatch

extension ImGuiNavInput_ {
    var value : Int {
        return Int(self.rawValue)
    }
}

extension ImGui {
    
    fileprivate static func updateScreens() -> [Screen] {
        let platformIO = igGetPlatformIO()!
        
        let screens = Application.sharedApplication.screens
        let mainScreenHeight = screens[0].dimensions.height
        
        if Int(platformIO.pointee.Monitors.Capacity) < screens.count {
            let newData = igMemAlloc(screens.count * MemoryLayout<ImGuiPlatformMonitor>.size)
            if platformIO.pointee.Monitors.Data != nil {
                memcpy(newData, platformIO.pointee.Monitors.Data, Int(platformIO.pointee.Monitors.Size) * MemoryLayout<ImGuiPlatformMonitor>.size)
                igMemFree(platformIO.pointee.Monitors.Data)
            }
            platformIO.pointee.Monitors.Data = newData?.assumingMemoryBound(to: ImGuiPlatformMonitor.self)
            platformIO.pointee.Monitors.Capacity = Int32(screens.count)
            platformIO.pointee.Monitors.Size = Int32(screens.count)
        }
        
        for (i, screen) in screens.enumerated() {
            let monitor = ImGuiPlatformMonitor(MainPos: ImVec2(x: screen.position.x, y: mainScreenHeight - (screen.position.y + screen.dimensions.height)),
                                               MainSize: ImVec2(x: screen.dimensions.width, y: screen.dimensions.height),
                                               WorkPos: ImVec2(x: screen.workspacePosition.x, y: mainScreenHeight - (screen.workspacePosition.y + screen.workspaceDimensions.height)),
                                               WorkSize: ImVec2(x: screen.workspaceDimensions.width, y: screen.workspaceDimensions.height),
                                               DpiScale: screen.backingScaleFactor)
            platformIO.pointee.Monitors.Data[i] = monitor
        }
        
        return screens
    }
    
    public static func beginFrame(windows: [Window], inputLayer: ImGuiInputLayer) {
        let screens = self.updateScreens()
        let mainScreenHeight = screens[0].dimensions.height
        
        let io = ImGui.io
        let oldMousePosition = ImGui.io.pointee.MousePos
        
        let mainWindow = windows[0]
        
        io.pointee.DisplaySize = ImVec2(x: Float(mainWindow.dimensions.width), y: Float(mainWindow.dimensions.height))
        io.pointee.DeltaTime = Float(Timing.deltaTime)
        
        io.pointee.MousePos = ImVec2(x: -Float.greatestFiniteMagnitude, y: -Float.greatestFiniteMagnitude)
        io.pointee.MouseWheel = 0.0
        io.pointee.MouseWheelH = 0.0
        io.pointee.MouseHoveredViewport = 0
        
        let mousePosition = Vector2f(inputLayer[.mouseX].value, inputLayer[.mouseY].value)
        
        #if !os(iOS)
        var frontmostHoveredViewport = Int.max
        
        let platformIO = igGetPlatformIO()!
        for n in 0..<Int(platformIO.pointee.Viewports.Size) {
            let viewport = platformIO.pointee.Viewports.Data[n]!
            let window = viewport.pointee.window
            
            let focused = window.hasFocus
            if focused {
                if io.pointee.WantSetMousePos {
                    Application.sharedApplication.setCursorPosition(to: Vector2f(oldMousePosition.x, mainScreenHeight - oldMousePosition.y))
                } else {
                    io.pointee.MousePos = ImVec2(x: mousePosition.x, y: mainScreenHeight - mousePosition.y)
                }
                
                io.pointee.MouseWheel = inputLayer[.mouseScrollY].value
                io.pointee.MouseWheelH = inputLayer[.mouseScrollX].value
            }
            
            let wantsViewportHovered = (ImGuiViewportFlags_.RawValue(viewport.pointee.Flags) & ImGuiViewportFlags_NoInputs.rawValue) == 0
            if wantsViewportHovered {
                let windowPosition = window.position
                let windowDimensions = window.dimensions
                
                if window.windowsInFrontCount < frontmostHoveredViewport &&
                    windowPosition.x <= mousePosition.x && windowPosition.y <= mousePosition.y &&
                    (windowPosition.x + windowDimensions.width) >= mousePosition.x && (windowPosition.y + windowDimensions.height) >= mousePosition.y {
                    io.pointee.MouseHoveredViewport = viewport.pointee.ID
                    frontmostHoveredViewport = window.windowsInFrontCount
                }
            }
        }
        #else
        io.pointee.MousePos = ImVec2(x: mousePosition.x, y: mainScreenHeight - mousePosition.y)
        #endif
        
        io.pointee.MouseDown.0 = inputLayer[.mouseButtonLeft].isActive
        io.pointee.MouseDown.1 = inputLayer[.mouseButtonRight].isActive
        io.pointee.MouseDown.2 = inputLayer[.mouseButtonMiddle].isActive
        
        withUnsafeMutablePointer(to: &ImGui.io.pointee.NavInputs.0, { navInputs in
            
            navInputs[ImGuiNavInput_Menu.value] = inputLayer[.gamepadStart].value
            navInputs[ImGuiNavInput_Activate.value] = inputLayer[.gamepadA].value
            navInputs[ImGuiNavInput_Cancel.value] = inputLayer[.gamepadB].value
            navInputs[ImGuiNavInput_Input.value] = inputLayer[.gamepadY].value
            navInputs[ImGuiNavInput_Menu.value] = inputLayer[.gamepadX].value
            navInputs[ImGuiNavInput_DpadLeft.value] = inputLayer[.gamepadLeft].value
            navInputs[ImGuiNavInput_DpadRight.value] = inputLayer[.gamepadRight].value
            navInputs[ImGuiNavInput_DpadUp.value] = inputLayer[.gamepadUp].value
            navInputs[ImGuiNavInput_DpadDown.value] = inputLayer[.gamepadDown].value
            navInputs[ImGuiNavInput_LStickLeft.value] = max(-inputLayer[.gamepadLeftAxisX].value, 0)
            navInputs[ImGuiNavInput_LStickRight.value] = max(inputLayer[.gamepadLeftAxisX].value, 0)
            navInputs[ImGuiNavInput_LStickUp.value] = max(-inputLayer[.gamepadLeftAxisY].value, 0)
            navInputs[ImGuiNavInput_LStickDown.value] = max(inputLayer[.gamepadLeftAxisY].value, 0)
            navInputs[ImGuiNavInput_FocusPrev.value] = inputLayer[.gamepadLeftShoulder].value
            navInputs[ImGuiNavInput_FocusNext.value] = inputLayer[.gamepadRightShoulder].value
            navInputs[ImGuiNavInput_TweakSlow.value] = inputLayer[.gamepadLeftTrigger].value
            navInputs[ImGuiNavInput_TweakFast.value] = inputLayer[.gamepadRightTrigger].value
        })
        
        ImGui.newFrame()
        
        let mainWindowPosition = mainWindow.position
        ImGuizmo.setRect(Rect(origin: Point(x: mainWindowPosition.x, y: mainScreenHeight - (mainWindowPosition.y + mainWindow.dimensions.height)), size: Size2f(width: mainWindow.dimensions.width, height: mainWindow.dimensions.height)))
    }
}
