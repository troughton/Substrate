//
//  RenderPassImgui.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 6/04/17.
//
//

import SwiftFrameGraph
import SwiftMath
import CDebugDrawTools
import DrawTools

final class ImGuiPass : DrawRenderPass {
    
    static let vertexDescriptor : VertexDescriptor = {
        var vertexDescriptor = VertexDescriptor()
        //pos
        vertexDescriptor.attributes[0].offset = 0 //OFFSETOF(ImDrawVert, pos);
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 2//OFFSETOF(ImDrawVert, uv);
        vertexDescriptor.attributes[1].format = .float2;
        vertexDescriptor.attributes[1].bufferIndex = 0;
        vertexDescriptor.attributes[2].offset = MemoryLayout<Float>.size * 4 //OFFSETOF(ImDrawVert, col)
        vertexDescriptor.attributes[2].format = .uchar4Normalized
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<ImDrawVert>.size
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        return vertexDescriptor
    }()
    
    static let pipelineDescriptor : RenderPipelineDescriptor<DisplayRenderTargetIndex> = {
        var descriptor = RenderPipelineDescriptor<DisplayRenderTargetIndex>()
        
        descriptor.vertexFunction = "imgui_vertex"
        descriptor.fragmentFunction = "imgui_fragment"
        descriptor.vertexDescriptor = ImGuiPass.vertexDescriptor
        
        var blendDescriptor = BlendDescriptor()
        blendDescriptor.sourceRGBBlendFactor = .sourceAlpha
        blendDescriptor.sourceAlphaBlendFactor = .sourceAlpha
        blendDescriptor.destinationRGBBlendFactor = .oneMinusSourceAlpha
        blendDescriptor.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        descriptor[blendStateFor: .display] = blendDescriptor
        descriptor.label = "ImGui Pass Pipeline"
        
        descriptor.setFunctionConstants(ImGuiFragmentFunctionConstants())
        
        return descriptor
    }()
    
    static let samplerDescriptor : SamplerDescriptor = {
        var samplerDescriptor = SamplerDescriptor()
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        return samplerDescriptor
    }()
    
    
    static let fontTexture : Texture = {
        let (pixels, width, height, bytesPerPixel) = ImGui.getFontTexDataAsAlpha8()
        
        var textureDescriptor = TextureDescriptor(texture2DWithFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        textureDescriptor.storageMode = .private
        textureDescriptor.usageHint = [.shaderRead, .blitDestination]
        let fontTexture = Texture(descriptor: textureDescriptor, flags: .persistent)
        
        let stagingBuffer = Buffer(descriptor: BufferDescriptor(length: width * height * bytesPerPixel, storageMode: .managed, cacheMode: .writeCombined, usage: .blitSource))
        FrameGraph.addBlitCallbackPass(name: "Stage ImGui Font Texture", execute: { blitEncoder in
            stagingBuffer[stagingBuffer.range].withContents { $0.copyMemory(from: pixels, byteCount: stagingBuffer.length) }
            blitEncoder.copy(from: stagingBuffer, sourceOffset: 0, sourceBytesPerRow: width * bytesPerPixel, sourceBytesPerImage: stagingBuffer.descriptor.length, sourceSize: Size(width: width, height: height, depth: 1), to: fontTexture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: Origin(x: 0, y: 0, z: 0))
        })
        
        ImGui.setFontTexID(UnsafeMutableRawPointer(bitPattern: UInt(fontTexture.handle))!)
        
        return fontTexture
    }()
    
    struct ImGuiFragmentFunctionConstants : FunctionConstants {
        var textureTypeFloat : Bool = false
        var textureTypeUInt : Bool = false
        var textureTypeDepth : Bool = false
        var textureTypeDepthArray : Bool = false
        var channelCount : UInt16 = 0
        var convertTextureLinearToSRGB : Bool = false
        
        init() {
            
        }
        
        public init?(descriptor: TextureDescriptor, convertLinearToSRGB: Bool) {
            let pixelFormat = descriptor.pixelFormat
            
            if pixelFormat.isDepth {
                if descriptor.textureType == .type2DArray {
                    self.textureTypeDepthArray = true
                } else {
                    self.textureTypeDepth = true
                }
                self.channelCount = 1
            }
            
            switch pixelFormat {
            case .rgba32Float, .rgba16Float:
                self.textureTypeFloat = true
                self.channelCount = 4
            case .rg32Float, .rg16Float:
                self.textureTypeFloat = true
                self.channelCount = 2
            case .r32Float, .r16Float, .r8Unorm:
                self.textureTypeFloat = true
                self.channelCount = 1
            default:
                return nil
            }
            
            self.convertTextureLinearToSRGB = convertLinearToSRGB
        }
    }
    
    let name = "ImGui"
    let renderer : Renderer
    let renderData : ImGui.RenderData
    let renderTargetDescriptor: RenderTargetDescriptor<DisplayRenderTargetIndex>
    
    init(renderer: Renderer, renderData: ImGui.RenderData, renderTargetDescriptor: RenderTargetDescriptor<DisplayRenderTargetIndex>) {
        
        let _ = ImGuiPass.fontTexture // make sure the font texture is initialised
        
        self.renderer = renderer
        self.renderData = renderData
        self.renderTargetDescriptor = renderTargetDescriptor
    }
    
    func execute(renderCommandEncoder renderEncoder: RenderCommandEncoder) {
        
        if renderData.vertexBuffer.isEmpty {
            return
        }
        
        renderEncoder.setTriangleFillMode(.fill)
        
        let vertexBuffer = Buffer(descriptor: BufferDescriptor(length: renderData.vertexBuffer.count * MemoryLayout<ImDrawVert>.size, usage: .vertexBuffer), bytes: renderData.vertexBuffer.baseAddress!)
        let indexBuffer = Buffer(descriptor: BufferDescriptor(length: renderData.indexBuffer.count * MemoryLayout<ImDrawIdx>.size, usage: .indexBuffer), bytes: renderData.indexBuffer.baseAddress!)
        
        
        let displayPosition = self.renderData.displayPosition
        let displayWidth = Float(self.renderData.displaySize.width)
        let displayHeight = Float(self.renderData.displaySize.height)
        
        let fbWidth = self.renderTargetDescriptor.size.width
        let fbHeight = self.renderTargetDescriptor.size.height
        let fbWidthF = Float(fbWidth)
        let fbHeightF = Float(fbHeight)
        
        var pipelineDescriptor = ImGuiPass.pipelineDescriptor
        renderEncoder.setRenderPipelineDescriptor(pipelineDescriptor)
        
        let left = displayPosition.x, right = displayPosition.x + displayWidth, top = displayPosition.y, bottom = displayPosition.y + displayHeight
        let near : Float = 0
        let far : Float = 1
        let orthoMatrix = Matrix4x4f.ortho(left: left, right: right, bottom: bottom, top: top, near: near, far: far)
        
        renderEncoder.setValue(orthoMatrix, key: "proj_matrix")
        
        renderEncoder.setSampler(ImGuiPass.samplerDescriptor, key: "tex_sampler")
        
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        renderEncoder.setViewport(Viewport(originX: 0.0, originY: 0.0, width: Double(fbWidth), height: Double(fbHeight), zNear: 0.0, zFar: 1.0))
        
        let clipSpaceDisplayPosition = displayPosition * renderData.clipScaleFactor
        
        for drawCommand in renderData.drawCommands {
            
            renderEncoder.setVertexBufferOffset(drawCommand.vertexBufferByteOffset, index: 0)
            
            var idxBufferOffset = 0
            
            var previousFunctionConstants = ImGuiFragmentFunctionConstants()
            
            for pcmd in drawCommand.subCommands {
                if pcmd.UserCallback != nil {
                    fatalError("User callbacks are unsupported.")
                } else {
                    let clipRect = ImVec4(x: pcmd.ClipRect.x - clipSpaceDisplayPosition.x, y: pcmd.ClipRect.y - clipSpaceDisplayPosition.y, z: pcmd.ClipRect.z - clipSpaceDisplayPosition.x, w: pcmd.ClipRect.w - clipSpaceDisplayPosition.y)
                    if clipRect.x < fbWidthF && clipRect.y < fbHeightF && clipRect.z >= 0.0 && clipRect.w >= 0.0 {
                        let scissorRect = ScissorRect(x: max(Int(clipRect.x), 0), y: max(Int(clipRect.y), 0), width: Int(min(clipRect.z, fbWidthF) - clipRect.x), height: Int(min(clipRect.w, fbHeightF) - clipRect.y))
                        renderEncoder.setScissorRect(scissorRect)
                        
                        let textureIdentifier = UInt(bitPattern: pcmd.TextureId!)
                        
                        let texture : Texture
                        if UInt64(textureIdentifier) & (UInt64(ResourceType.texture.rawValue) << 48) != 0 {
                            // Texture handle
                            texture = Texture(existingHandle: Texture.Handle(textureIdentifier))
                        } else {
                            let lookupHandle = UInt32(truncatingIfNeeded: textureIdentifier) // Only the lower 32 bits, since that's how many bits are reserved for the index in Texture.Handle.
                            texture = TextureLookup.textureWithId(lookupHandle) ?? Texture.invalid
                        }
                        
                        guard let functionConstants = ImGuiFragmentFunctionConstants(descriptor: texture.descriptor, convertLinearToSRGB: texture == ImGuiPass.fontTexture) else { continue }
                        if previousFunctionConstants != functionConstants {
                            pipelineDescriptor.setFunctionConstants(functionConstants)
                            renderEncoder.setRenderPipelineDescriptor(pipelineDescriptor)
                            
                            previousFunctionConstants = functionConstants
                        }
                        
                        if texture.descriptor.pixelFormat.isDepth {
                            renderEncoder.setTexture(texture, key: texture.descriptor.textureType != .type2DArray ? "depthTexture" : "depthTexture2DArray")
                        } else {
                            renderEncoder.setTexture(texture, key: "floatTexture")
                        }
                        
                        renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: Int(pcmd.ElemCount), indexType: MemoryLayout<ImDrawIdx>.size == 2 ? .uint16 : .uint32, indexBuffer: indexBuffer, indexBufferOffset: drawCommand.indexBufferByteOffset + MemoryLayout<ImDrawIdx>.size * idxBufferOffset)
                    }
                }
                
                idxBufferOffset += Int(pcmd.ElemCount)
            }
        }
    }
}

fileprivate var imguiConfigFilePath : ContiguousArray<CChar>! = nil 

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

public extension ImGui {
    public static func initialiseRendering(mainWindow: Window) {
        ImGui.styleColorsDark()
        
        let _ = ImGuiPass.fontTexture
        
        // FIXME: this should probably go somewhere else.
        
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
        
        #if !os(iOS)
        let mainViewport = igGetMainViewport()!
        mainViewport.pointee.window = mainWindow
        
        self.initialisePlatformInterface()
        #endif
    }
    
    public static func initialisePlatformInterface() {
        let platformIO = igGetPlatformIO()!
        platformIO.pointee.Platform_CreateWindow = { viewport in
            let viewport = viewport!
            let windowSize = WindowSize(Float(viewport.pointee.Size.x), Float(viewport.pointee.Size.y))
            let window = Application.sharedApplication.createWindow(title: "", dimensions: windowSize, flags: [.borderless, .hidden])
            viewport.pointee.PlatformHandle = Unmanaged<AnyObject>.passRetained(window).toOpaque()
        }
        
        platformIO.pointee.Platform_DestroyWindow = { viewport in
            assert(!viewport!.pointee.window.isMainWindow)
            Application.sharedApplication.destroyWindow(window: viewport!.pointee.window)
            Unmanaged<AnyObject>.fromOpaque(viewport!.pointee.PlatformHandle).release()
        }
        
        platformIO.pointee.Platform_ShowWindow = { viewport in
            viewport!.pointee.window.isVisible = true
        }
        
        platformIO.pointee.Platform_GetWindowPos = { (viewport) in
            let mainScreenHeight = Application.sharedApplication.screens[0].dimensions.height
            
            let window = viewport!.pointee.window
            return ImVec2(x: window.position.x, y: mainScreenHeight - (window.position.y + window.dimensions.height))
        }
        
        platformIO.pointee.Platform_SetWindowPos = { (viewport, position) in
            let mainScreenHeight = Application.sharedApplication.screens[0].dimensions.height
            
            let window = viewport!.pointee.window
            window.position = WindowPosition(position.x, mainScreenHeight - (position.y + window.dimensions.height))
        }
        
        platformIO.pointee.Platform_SetWindowSize = { (viewport, size) in
            // Setting the size conceptually takes place from the top left; we want to offset the
            // frame's y origin by the difference in the size
            
            let window = viewport!.pointee.window
            let oldHeight = window.dimensions.height
            window.dimensions = WindowSize(Float(size.x), Float(size.y))
            window.position.y -= size.y - oldHeight
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
    }
}
