//
//  Window+ImGui.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 6/12/16.
//
//

import CImGui
import ImGui
import SwiftMath
import Dispatch
import Substrate

extension ImGuiNavInput_ {
    var value : Int {
        return Int(self.rawValue)
    }
}

extension ImGui {
    
    fileprivate static func updateScreens() -> [Screen] {
        let platformIO = igGetPlatformIO()!
        
        let screens = Application.sharedApplication.screens
            
        if Int(platformIO.pointee.Monitors.Capacity) < screens.count {
            let newData = igMemAlloc(screens.count * MemoryLayout<ImGuiPlatformMonitor>.size)
            if platformIO.pointee.Monitors.Data != nil {
                newData?.copyMemory(from: platformIO.pointee.Monitors.Data, byteCount: Int(platformIO.pointee.Monitors.Size) * MemoryLayout<ImGuiPlatformMonitor>.size)
                igMemFree(platformIO.pointee.Monitors.Data)
            }
            platformIO.pointee.Monitors.Data = newData?.assumingMemoryBound(to: ImGuiPlatformMonitor.self)
            platformIO.pointee.Monitors.Capacity = Int32(screens.count)
            platformIO.pointee.Monitors.Size = Int32(screens.count)
        }
    
        for (i, screen) in screens.enumerated() {
            let monitor = ImGuiPlatformMonitor(MainPos: ImVec2(x: screen.position.x, y: screen.position.y),
                                               MainSize: ImVec2(x: screen.dimensions.width, y: screen.dimensions.height),
                                               WorkPos: ImVec2(x: screen.workspacePosition.x, y: screen.workspacePosition.y),
                                               WorkSize: ImVec2(x: screen.workspaceDimensions.width, y: screen.workspaceDimensions.height),
                                               DpiScale: screen.backingScaleFactor)
            platformIO.pointee.Monitors.Data[i] = monitor
        }

        return screens
    }
    
    public static func initialisePlatformInterface() {
        
        let (pixels, width, height, bytesPerPixel) = ImGui.getFontTexDataAsAlpha8()
        
        var textureDescriptor = TextureDescriptor(type: .type2D, format: .r8Unorm, width: width, height: height, mipmapped: false)
        textureDescriptor.storageMode = .private
        textureDescriptor.usageHint = [.shaderRead, .blitDestination]
        let fontTexture = Texture(descriptor: textureDescriptor, flags: .persistent)
        GPUResourceUploader.replaceTextureRegion(Region(x: 0, y: 0, width: width, height: height), mipmapLevel: 0, in: fontTexture, withBytes: pixels, bytesPerRow: width * bytesPerPixel)
        
        ImGui.setFontTexID(UnsafeMutableRawPointer(bitPattern: UInt(exactly: fontTexture.handle)!))
        
        #if os(macOS)
        ImGui.io.pointee.ConfigMacOSXBehaviors = true
        #endif
        
        #if os(iOS)
        let configFlags : ImGuiConfigFlags_ = [ImGuiConfigFlags_DockingEnable]
        let backendFlags : ImGuiBackendFlags_ = []
        #else
        let configFlags : ImGuiConfigFlags_ = [ImGuiConfigFlags_NavEnableKeyboard, ImGuiConfigFlags_NavEnableGamepad, ImGuiConfigFlags_DockingEnable, ImGuiConfigFlags_ViewportsEnable]
        let backendFlags : ImGuiBackendFlags_ = [ImGuiBackendFlags_HasMouseCursors, ImGuiBackendFlags_HasGamepad, ImGuiBackendFlags_PlatformHasViewports, ImGuiBackendFlags_RendererHasViewports, ImGuiBackendFlags_HasMouseHoveredViewport]
        #endif
        
        ImGui.io.pointee.ConfigFlags |= ImGuiConfigFlags(configFlags.rawValue)
        ImGui.io.pointee.BackendFlags |= ImGuiBackendFlags(backendFlags.rawValue)
        
        #if !(os(iOS) || os(tvOS) || os(watchOS))
        let platformIO = igGetPlatformIO()!
        platformIO.pointee.Platform_CreateWindow = { viewport in
            let viewport = viewport!
            let windowSize = WindowSize(Float(viewport.pointee.Size.x), Float(viewport.pointee.Size.y))
            let window = Application.sharedApplication.createWindow(title: "", dimensions: windowSize, flags: [.borderless, .hidden], renderGraph: Application.sharedApplication.windowRenderGraph)
            viewport.pointee.PlatformHandle = Unmanaged<AnyObject>.passRetained(window).toOpaque()
        }
        
        platformIO.pointee.Platform_DestroyWindow = { viewport in
            Application.sharedApplication.destroyWindow(viewport!.pointee.window)
            Unmanaged<AnyObject>.fromOpaque(viewport!.pointee.PlatformHandle).release()
        }
        
        platformIO.pointee.Platform_ShowWindow = { viewport in
            viewport!.pointee.window.isVisible = true
        }
        
        platformIO.pointee.Platform_GetWindowPos = { (viewport) in
            let window = viewport!.pointee.window
            return ImVec2(x: window.position.x, y: window.position.y)
        }
        
        platformIO.pointee.Platform_SetWindowPos = { (viewport, position) in
            let window = viewport!.pointee.window
            window.position = WindowPosition(position.x, position.y)
        }
        
        platformIO.pointee.Platform_SetWindowSize = { (viewport, size) in
            let window = viewport!.pointee.window
            window.dimensions = WindowSize(Float(size.x), Float(size.y))
        }
        
        platformIO.pointee.Platform_GetWindowSize = { (viewport) in
            let windowSize = viewport!.pointee.window.dimensions
            return ImVec2(x: Float(windowSize.width), y: Float(windowSize.height))
        }
        
        platformIO.pointee.Platform_SetWindowFocus = { (viewport) in
            viewport!.pointee.window.hasFocus = true
        }
        
        platformIO.pointee.Platform_GetWindowFocus = { (viewport) in
          return viewport!.pointee.window.hasFocus
        }
        
        platformIO.pointee.Platform_SetWindowTitle = { (viewport, title) in
            viewport!.pointee.window.title = String(cString: title!)
        }
        
        platformIO.pointee.Platform_GetWindowDpiScale = { (viewport) in
            if viewport!.pointee.PlatformHandle == nil {
                return Application.sharedApplication.screens[0].backingScaleFactor
            }
            
            let window = viewport!.pointee.window
            return Float(window.framebufferScale)
        }
        
        platformIO.pointee.Platform_RenderWindow = { (viewport, renderArguments) in
            
        }
        
        platformIO.pointee.Platform_SwapBuffers = { (viewport, renderArguments) in
            
        }
        
        platformIO.pointee.Platform_SetWindowAlpha = { (viewport, alpha) in
            viewport!.pointee.window.alpha = alpha
        }
        
        #endif // !(os(iOS) || os(tvOS) || os(watchOS))
    }
    
    public static func beginFrame(windows: [Window], inputLayer: ImGuiInputLayer, deltaTime: Double) {
        _ = self.updateScreens()

        let io = ImGui.io
        let oldMousePosition = ImGui.io.pointee.MousePos
        
        let mainWindow = windows[0]
        
        #if !os(iOS)
        let mainViewport = igGetMainViewport()!
        mainViewport.pointee.window = mainWindow
        #endif
        
        io.pointee.DisplaySize = ImVec2(x: Float(mainWindow.dimensions.width), y: Float(mainWindow.dimensions.height))
        io.pointee.DeltaTime = Float(deltaTime)
        
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
                    Application.sharedApplication.setCursorPosition(to: Vector2f(oldMousePosition.x, oldMousePosition.y))
                } else {
                    io.pointee.MousePos = ImVec2(x: mousePosition.x, y: mousePosition.y)
                }
                
                io.pointee.MouseWheel = inputLayer[.mouseScrollY].value
                io.pointee.MouseWheelH = inputLayer[.mouseScrollX].value
            }
            
            let wantsViewportHovered = (ImGuiViewportFlags_.RawValue(viewport.pointee.Flags) & ImGuiViewportFlags_NoInputs.rawValue) == 0
            if wantsViewportHovered {
                let windowPosition = window.position
                let windowDimensions = window.dimensions
                
                if  windowPosition.x <= mousePosition.x && windowPosition.y <= mousePosition.y &&
                    (windowPosition.x + windowDimensions.width) >= mousePosition.x && (windowPosition.y + windowDimensions.height) >= mousePosition.y {
                    let windowsInFrontCount = window.windowsInFrontCount
                    if windowsInFrontCount < frontmostHoveredViewport {
                        io.pointee.MouseHoveredViewport = viewport.pointee.ID
                        frontmostHoveredViewport = windowsInFrontCount
                    }
                }
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

extension ImGuiViewport {
    public var window : Window {
        get {
            return Unmanaged<AnyObject>.fromOpaque(self.PlatformHandle).takeUnretainedValue() as! Window
        }
        set {
            self.PlatformHandle = Unmanaged<AnyObject>.passUnretained(newValue).toOpaque()
        }
    }
}
