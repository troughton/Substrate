//
//  SDLApplication.swift
//  Renderer
//
//  Created by Thomas Roughton on 20/01/18.
//

#if canImport(CSDL2)

import SwiftMath
import SwiftFrameGraph
import ImGui
import CSDL2
import Foundation

#if canImport(Vulkan)

import Vulkan

public class SDLVulkanWindow : SDLWindow {
    var vkSurface : VkSurfaceKHR? = nil
    
    public convenience init(id: Int, title: String, dimensions: WindowSize, windowFrameGraph: FrameGraph) {
        let vulkanInstance = (RenderBackend.backend as! VulkanBackend).vulkanInstance
        let options : SDLWindowOptions = [.allowHighDpi, .shown, .resizeable, .vulkan]
        let sdlWindowPointer = SDL_CreateWindow(title, Int32(SDL_WINDOWPOS_UNDEFINED_MASK), Int32(SDL_WINDOWPOS_UNDEFINED_MASK), Int32(dimensions.width), Int32(dimensions.height), options.rawValue)
        self.init(id: id, title: title, dimensions: dimensions, sdlWindowPointer: sdlWindowPointer, frameGraph: windowFrameGraph)
        
        if SDL_Vulkan_CreateSurface(self.sdlWindowPointer, vulkanInstance.instance, &self.vkSurface) == SDL_FALSE {
            fatalError("Unable to create Vulkan surface: " + String(cString: SDL_GetError()))
        }
    }
}

#endif // canImport(Vulkan)

#if canImport(Metal)

import AppKit

public class SDLMetalWindow : SDLWindow {
    var metalView : SDL_MetalView? = nil
    
    public convenience init(id: Int, title: String, dimensions: WindowSize, frameGraph: FrameGraph) {
        let options : SDLWindowOptions = [.allowHighDpi, .shown, .resizeable]
        let sdlWindowPointer = SDL_CreateWindow(title, Int32(SDL_WINDOWPOS_UNDEFINED_MASK), Int32(SDL_WINDOWPOS_UNDEFINED_MASK), Int32(dimensions.width), Int32(dimensions.height), options.rawValue)
            
        self.init(id: id, title: title, dimensions: dimensions, sdlWindowPointer: sdlWindowPointer, frameGraph: frameGraph)
        
        self.metalView = SDL_Metal_CreateView(sdlWindowPointer)
        
        #if os(macOS)
        let view = Unmanaged<NSView>.fromOpaque(self.metalView!).takeUnretainedValue()
        
        let metalLayer = view.layer as! CAMetalLayer
        metalLayer.device = (RenderBackend.renderDevice as! MTLDevice)
        self.swapChain = metalLayer
        #endif
    }
    
    deinit {
        SDL_Metal_DestroyView(self.metalView)
    }
}

extension CAMetalLayer : SwapChain {
    public var format : PixelFormat {
        return PixelFormat(rawValue: self.pixelFormat.rawValue)!
    }
}

#endif // canImport(Metal)

public class SDLApplication : Application {
    
    public init(delegate: ApplicationDelegate?, updateables: @autoclosure () -> [FrameUpdateable], updateScheduler: UpdateScheduler, windowFrameGraph: FrameGraph) {
        delegate?.applicationWillInitialise()
        
        guard SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER) == 0 else {
            let error = String(cString: SDL_GetError())
            fatalError("Unable to initialise SDL: \(error)")
        }
        print("Initialised SDL")
        
        let updateables = updateables()
        precondition(!updateables.isEmpty)
        
        super.init(delegate: delegate, updateables: updateables, inputManager: SDLInputManager(), updateScheduler: updateScheduler, windowFrameGraph: windowFrameGraph)
    }
    
    public override func createWindow(title: String, dimensions: WindowSize, flags: WindowCreationFlags, frameGraph: FrameGraph) -> Window {
        var window : SDLWindow! = nil

        #if canImport(Metal)
        if RenderBackend.api == .metal {
            window = SDLMetalWindow(id: self.nextAvailableWindowId(), title: title, dimensions: dimensions, frameGraph: frameGraph)
        }
        #endif
        
        #if canImport(Vulkan)
        if RenderBackend.api == .vulkan {
            window = SDLVulkanWindow(id: self.nextAvailableWindowId(), title: title, dimensions: dimensions, windowFrameGraph: frameGraph)
        }
        #endif
        
        precondition(window != nil)
        
        self.windows.append(window)
        
        return window
    }
    
    public override var screens: [Screen] {
        let numVideoDisplays = SDL_GetNumVideoDisplays()
        
        return (0..<numVideoDisplays).map { (i) -> Screen in
            var displayMode = SDL_DisplayMode()
            SDL_GetDisplayMode(i, 0, &displayMode)
        
            var bounds = SDL_Rect()
            SDL_GetDisplayBounds(i, &bounds)
                        
            var usableBounds = SDL_Rect()
            SDL_GetDisplayUsableBounds(i, &usableBounds)
            
            var ddpi = 0.0 as Float
            SDL_GetDisplayDPI(i, &ddpi, nil, nil)
            let baselineDPI = 108.8 as Float
            
            let backingScaleFactor = ddpi/baselineDPI
            
            return Screen(position: WindowPosition(Float(bounds.x), Float(bounds.y)), dimensions: WindowSize(Float(bounds.w), Float(bounds.h)), workspacePosition: WindowPosition(Float(usableBounds.x), Float(usableBounds.y)), workspaceDimensions: WindowSize(Float(usableBounds.w), Float(usableBounds.h)), backingScaleFactor: backingScaleFactor)
        }
        
    }
    
    deinit {
        SDL_Quit()
    }
}

#endif // canImport(CSDL2)
