//
//  File.swift
//  
//
//  Created by Thomas Roughton on 7/04/20.
//


struct FrameResourceMap<Backend: SpecificRenderBackend> {
    let persistentRegistry : Backend.PersistentResourceRegistry
    let transientRegistry : Backend.TransientResourceRegistry?
    
    subscript(buffer: Buffer) -> Backend.BufferReference? {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            return transientRegistry![buffer] // Optional because the resource may be unused in this frame.
        }
    }
    
    subscript(texture: Texture) -> Backend.TextureReference? {
        if texture._usesPersistentRegistry {
            return persistentRegistry[texture]!
        } else {
            return transientRegistry![texture] // Optional because the resource may be unused in this frame.
        }
    }
    
    subscript(buffer: ArgumentBuffer) -> Backend.ArgumentBufferReference {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            return transientRegistry![buffer]!
        }
    }
    
    subscript(buffer: ArgumentBufferArray) -> Backend.ArgumentBufferArrayReference {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            return transientRegistry![buffer]!
        }
    }
    
    subscript(sampler: SamplerDescriptor) -> Backend.SamplerReference {
        get async {
            return await persistentRegistry[sampler]
        }
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    subscript(accelerationStructure: AccelerationStructure) -> AnyObject? {
        return persistentRegistry[accelerationStructure]
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    subscript(visibleFunctionTable: VisibleFunctionTable) -> Backend.VisibleFunctionTableReference? {
        return persistentRegistry[visibleFunctionTable]
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    subscript(intersectionFunctionTable: IntersectionFunctionTable) -> Backend.IntersectionFunctionTableReference? {
        return persistentRegistry[intersectionFunctionTable]
    }
    
    func bufferForCPUAccess(_ buffer: Buffer, needsLock: Bool) -> Backend.BufferReference {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            if needsLock {
                transientRegistry!.accessLock.lock()
            }
            let result = transientRegistry!.allocateBufferIfNeeded(buffer, forceGPUPrivate: false)
            if needsLock {
                transientRegistry!.accessLock.unlock()
            }
            return result
        }
    }
    
    func textureForCPUAccess(_ texture: Texture, needsLock: Bool) async -> Backend.TextureReference {
        if texture._usesPersistentRegistry {
            return persistentRegistry[texture]!
        } else {
            if needsLock {
                await transientRegistry!.accessLock.lock()
            }
            let result = await transientRegistry!.allocateTextureIfNeeded(texture, forceGPUPrivate: false, isStoredThisFrame: true) // Conservatively mark the texture as stored this frame.
            if needsLock {
                transientRegistry!.accessLock.unlock()
            }
            return result
        }
    }
    
    func renderTargetTexture(_ texture: Texture) async throws -> Backend.TextureReference {
        if texture.flags.contains(.windowHandle) {
            return try await self.transientRegistry!.allocateWindowHandleTexture(texture)
        }
        return self[texture]!
    }
}
