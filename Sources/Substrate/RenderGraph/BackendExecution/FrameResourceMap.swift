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
        return persistentRegistry[sampler]
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
    
    func bufferForCPUAccess(_ buffer: Buffer) -> Backend.BufferReference {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            return transientRegistry!.accessLock.withLock { transientRegistry!.allocateBufferIfNeeded(buffer, forceGPUPrivate: false) }
        }
    }
    
    func textureForCPUAccess(_ texture: Texture) -> Backend.TextureReference {
        if texture._usesPersistentRegistry {
            return persistentRegistry[texture]!
        } else {
            return transientRegistry!.accessLock.withLock { transientRegistry!.allocateTextureIfNeeded(texture, forceGPUPrivate: false, frameStoredTextures: [texture]) } // Conservatively mark the texture as stored this frame.
        }
    }
    
    func renderTargetTexture(_ texture: Texture) throws -> Backend.TextureReference {
        if texture.flags.contains(.windowHandle) {
            return try self.transientRegistry!.allocateWindowHandleTexture(texture)
        }
        return self[texture]!
    }
}
