//
//  Window+ImGui.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 6/12/16.
//
//

import CImGui
import ImGui
import SubstrateMath
import Dispatch
import Substrate

extension ImGuiNavInput_ {
    var value : Int {
        return Int(self.rawValue)
    }
}

extension ImGui {
    
    public static func initialisePlatformInterface() {
        
        let (pixels, width, height, bytesPerPixel) = ImGui.io.pointee.Fonts.pointee.texDataAsAlpha8
        
        var textureDescriptor = TextureDescriptor(type: .type2D, format: .r8Unorm, width: width, height: height, mipmapped: false)
        textureDescriptor.storageMode = .private
        textureDescriptor.usageHint = [.shaderRead, .blitDestination]
        let fontTexture = Texture(descriptor: textureDescriptor, flags: .persistent)
        GPUResourceUploader.replaceTextureRegion(Region(x: 0, y: 0, width: width, height: height), mipmapLevel: 0, in: fontTexture, withBytes: pixels!, bytesPerRow: width * bytesPerPixel)
        
        ImGui.io.pointee.Fonts.pointee.setTexID(UnsafeMutableRawPointer(bitPattern: UInt(exactly: fontTexture.handle)!)!)
        
        #if os(macOS)
        ImGui.io.pointee.ConfigMacOSXBehaviors = true
        #endif
        
        #if os(iOS)
        let configFlags : ImGui.ConfigFlags = [.navEnableGamepad, .isTouchScreen,]
        let backendFlags : ImGui.BackendFlags = []
        #else
        let configFlags : ImGui.ConfigFlags = [.navEnableKeyboard, .navEnableGamepad]
        let backendFlags : ImGui.BackendFlags = [.hasMouseCursors, .hasGamepad]
        #endif
        
        ImGui.io.pointee.ConfigFlags |= configFlags.rawValue
        ImGui.io.pointee.BackendFlags |= backendFlags.rawValue
    }
    
    public static func beginFrame(windows: [Window], inputLayer: ImGuiInputLayer, deltaTime: Double) {
        let io = ImGui.io!
        let oldMousePosition = ImGui.io.pointee.MousePos
        
        let mainWindow = windows[0]
        
        io.pointee.DisplaySize = ImVec2(x: Float(mainWindow.dimensions.width), y: Float(mainWindow.dimensions.height))
        let framebufferScale = mainWindow.framebufferScale
        io.pointee.DisplayFramebufferScale = ImVec2(x: Float(framebufferScale), y: Float(framebufferScale))
        io.pointee.DeltaTime = Float(deltaTime)
        
        io.pointee.MousePos = ImVec2(x: -Float.greatestFiniteMagnitude, y: -Float.greatestFiniteMagnitude)
        io.pointee.MouseWheel = 0.0
        io.pointee.MouseWheelH = 0.0
        
        let mousePosition = Vector2f(inputLayer[.mouseX].value, inputLayer[.mouseY].value)
        
        #if !os(iOS)
        let platformIO = ImGui.currentContext!
        for n in 0..<Int(platformIO.pointee.Viewports.Size) {
            let viewport = platformIO.pointee.Viewports.Data[n]!
            let window = windows[n]
            
            let focused = window.hasFocus
            if focused {
                if io.pointee.WantSetMousePos {
                    Application.sharedApplication.setCursorPosition(to: Vector2f(oldMousePosition.x, oldMousePosition.y))
                } else {
                    io.pointee.MousePos = ImVec2(x: mousePosition.x, y: mousePosition.y)
                }
                
                io.pointee.MouseWheel = inputLayer[.mouseScrollY].value
                io.pointee.MouseWheelH = inputLayer[.mouseScrollX].value
            }
        }
        #else
        io.pointee.MousePos = ImVec2(x: mousePosition.x, y: mousePosition.y)
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
    }
}

extension ImGuiBackendFlags_ : OptionSet {}
extension ImGuiConfigFlags_ : OptionSet {}
