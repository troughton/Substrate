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
#if canImport(Vulkan)
        if RenderBackend.api == .vulkan {
            let window = SDLVulkanWindow(id: self.nextAvailableWindowId(), title: title, dimensions: dimensions, windowFrameGraph: frameGraph)
            self.windows.append(window)
            return window
        }
#endif
        fatalError("createWindow(title:dimensions:flags:frameGraph) is not implemented for non-Vulkan windows.")
    }
    
    deinit {
        SDL_Quit()
    }
}

#endif // canImport(CSDL2)
