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

public class SDLVulkanWindow : SDLWindow {
    var vkSurface : VkSurfaceKHR? = nil
    
    public convenience init(id: Int, title: String, dimensions: WindowSize, vulkanInstance: VulkanInstance) {
        let options : SDLWindowOptions = [.allowHighDpi, .shown, .resizeable, .vulkan]
        let sdlWindowPointer = SDL_CreateWindow(title, Int32(SDL_WINDOWPOS_UNDEFINED_MASK), Int32(SDL_WINDOWPOS_UNDEFINED_MASK), Int32(dimensions.width), Int32(dimensions.height), options.rawValue)
        self.init(id: id, title: title, dimensions: dimensions, sdlWindowPointer: sdlWindowPointer)
        
        if SDL_Vulkan_CreateSurface(self.sdlWindowPointer, vulkanInstance.instance, &self.vkSurface) == SDL_FALSE {
            fatalError("Unable to create Vulkan surface: " + String(cString: SDL_GetError()))
        }
    }
}

#endif // canImport(Vulkan)

public class SDLApplication : Application {
    
    public init(delegate: ApplicationDelegate?, updateables: @autoclosure () -> [FrameUpdateable], updateScheduler: UpdateScheduler, windowFrameGraph: FrameGraph) {
        delegate?.applicationWillInitialise()
        
        let updateables = updateables()
        precondition(!updateables.isEmpty)
        
        super.init(delegate: delegate, updateables: updateables, inputManager: SDLInputManager(), updateScheduler: updateScheduler, windowFrameGraph: windowFrameGraph)
    }
    
    deinit {
        SDL_Quit()
    }
}

#endif // canImport(CSDL2)
