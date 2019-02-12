//
//  Renderer.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 11/03/17.
//
//

import SwiftFrameGraph
import Foundation
import SwiftMath
import Dispatch
import DrawTools
import Utilities



public let RenderMaxInflightFrames = 3

public final class Renderer {
    
    static var backend : FrameGraphBackend! = nil
    
    public let renderStartedSemaphore = DispatchSemaphore(value: 0)
    private let renderQueue : DispatchQueue
    
    public init(backend: FrameGraphBackend) {
        Renderer.backend = backend
        
        self.renderQueue = DispatchQueue(label: "Render Queue", qos: .userInteractive, attributes: [], autoreleaseFrequency: .inherit, target: nil)
        
        let _ = FullScreenTriangle.tri // Make sure that the triangle's vertex buffer is staged.
        // Otherwise, the first time we go to use it, its staging pass may be added after the pass that uses it (in its execute method).
        
        FrameGraph.execute(backend: backend)
    }
    
    // Depth range notes:
    // We want reversed depth range: http://outerra.blogspot.co.nz/2012/11/maximizing-depth-buffer-range-and.html
    // careful: OpenGL default range is [-1, 1] rather than [0, 1]. We want our projection matrix to map the near plane to z = 1 and the far plane to z = 0.
    
    // Frustum culling: http://bitsquid.blogspot.co.nz/2016/10/the-implementation-of-frustum-culling.html
    // http://www.flipcode.com/archives/Frustum_Culling.shtml
    
    public func render(frame: UInt64, renderRequests: [RenderRequest], windows: [Window]) {
        self.renderQueue.async {
            self.renderStartedSemaphore.signal()
            
            self.renderInternal(frame: frame, renderRequests: renderRequests, windows: windows)
        }
    }
    
    private func renderInternal(frame: UInt64, renderRequests: [RenderRequest], windows: [Window]) {
        // use semaphore to encode 3 frames ahead
        
        defer { Allocator.frameCompleted(frame) }
        
        var destinationRenderTargets = [Texture : _RenderTargetDescriptor]()
        
        for renderRequest in renderRequests {
            
            let renderTexture : Texture
            var renderTargetDescriptor : _RenderTargetDescriptor
            switch renderRequest.destination {
            case .window(let window):
                renderTexture = window.texture
                renderTargetDescriptor = destinationRenderTargets[renderTexture] ?? {
                    let clearPass = ClearRenderTargetPass(outputTexture: window.texture)
                    FrameGraph.addPass(clearPass)
                    
                    var descriptor = clearPass.renderTargetDescriptor._descriptor
                    for i in 0..<descriptor.colorAttachments.count {
                        descriptor.colorAttachments[i]?.clearColor = nil
                    }
                    return descriptor
                    }()
                
            case .texture(let texture):
                renderTexture = texture
                
                renderTargetDescriptor = destinationRenderTargets[renderTexture] ?? {
                    var descriptor = RenderTargetDescriptor<DisplayRenderTargetIndex>()
                    descriptor[.display] = RenderTargetColorAttachmentDescriptor(texture: texture)
                    return descriptor._descriptor
                    }()
            }
            
            destinationRenderTargets[renderTexture] = renderTargetDescriptor
            
            var scissor = renderRequest.scissor
            if scissor.x + scissor.width > renderTexture.size.width || scissor.y + scissor.height > renderTexture.size.height {
                scissor = ScissorRect(x: 0, y: 0, width: renderTexture.size.width, height: renderTexture.size.height)
            }
            
            switch renderRequest.source {
            case let .imgui(imguiData):
                let imguiPass = ImGuiPass(renderer: self, renderData: imguiData, renderTargetDescriptor: RenderTargetDescriptor(renderTargetDescriptor))
                _ = FrameGraph.addPass(imguiPass)
            case let .texture(texture, isToneMapped):
                let hdrResolvePass = BlitColorRegionPass(inputTexture: texture, scissorRect: scissor, renderTargetDescriptor: RenderTargetDescriptor<DisplayRenderTargetIndex>(renderTargetDescriptor))
                _ = FrameGraph.addPass(hdrResolvePass)
            case let .frameGraphPass(function):
                function()
            }
        }
        
        FrameGraph.execute(backend: Renderer.backend)
        
        for window in windows {
            window.cycleFrames()
        }
        
        RenderBlackboard.clear()
    }
}
