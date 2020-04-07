//
//  File.swift
//  
//
//  Created by Thomas Roughton on 7/04/20.
//

import FrameGraphUtilities

protocol SpecificRenderBackend: _RenderBackendProtocol {
    associatedtype RenderTargetDescriptor: BackendRenderTargetDescriptor
    
    associatedtype TransientResourceRegistry: BackendTransientResourceRegistry where TransientResourceRegistry.Backend == Self
    associatedtype PersistentResourceRegistry: BackendPersistentResourceRegistry where PersistentResourceRegistry.Backend == Self
    
    associatedtype BufferReference
    associatedtype TextureReference
    associatedtype ArgumentBufferReference
    associatedtype ArgumentBufferArrayReference
}

protocol BackendRenderTargetDescriptor: class {
    init(renderPass: DrawRenderPass)
    var descriptor: RenderTargetDescriptor { get }
    func descriptorMergedWithPass(_ pass: DrawRenderPass, resourceUsages: ResourceUsages, storedTextures: inout [Texture]) -> Self
    func finalise(resourceUsages: ResourceUsages, storedTextures: inout [Texture])
}

protocol ResourceRegistry: class {
    associatedtype Backend: SpecificRenderBackend
    
    associatedtype PersistentResourceRegistry: ResourceRegistry
    associatedtype TransientResourceRegistry: ResourceRegistry
    
    
    subscript(buffer: Buffer) -> Backend.BufferReference? { get set }
    subscript(texture: Texture) -> Backend.TextureReference? { get set }
    subscript(argumentBuffer: _ArgumentBuffer) -> Backend.ArgumentBufferReference? { get set }
    subscript(argumentBufferArray: _ArgumentBufferArray) -> Backend.ArgumentBufferArrayReference? { get set }
}

protocol BackendTransientResourceRegistry: ResourceRegistry where TransientResourceRegistry == Self {
    var accessLock: SpinLock { get set }
    
    func allocateBufferIfNeeded(_ buffer: Buffer, usage: BufferUsage, forceGPUPrivate: Bool) -> Backend.BufferReference
    func allocateTextureIfNeeded(_ texture: Texture, usage: TextureUsageProperties, forceGPUPrivate: Bool) -> Backend.TextureReference
    func allocateWindowHandleTexture(_ texture: Texture, persistentRegistry: PersistentResourceRegistry) throws -> Backend.TextureReference
}

protocol BackendPersistentResourceRegistry: ResourceRegistry where PersistentResourceRegistry == Self {
    
}
