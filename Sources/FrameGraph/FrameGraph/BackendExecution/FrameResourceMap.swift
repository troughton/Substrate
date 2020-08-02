//
//  File.swift
//  
//
//  Created by Thomas Roughton on 7/04/20.
//


struct FrameResourceMap<Backend: SpecificRenderBackend> {
    let persistentRegistry : Backend.PersistentResourceRegistry
    let transientRegistry : Backend.TransientResourceRegistry
    
    subscript(buffer: Buffer) -> Backend.BufferReference {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            return transientRegistry[buffer]!
        }
    }
    
    subscript(texture: Texture) -> Backend.TextureReference {
        if texture._usesPersistentRegistry {
            return persistentRegistry[texture]!
        } else {
            return transientRegistry[texture]!
        }
    }
    
    subscript(buffer: _ArgumentBuffer) -> Backend.ArgumentBufferReference {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            return transientRegistry[buffer]!
        }
    }
    
    subscript(buffer: _ArgumentBufferArray) -> Backend.ArgumentBufferArrayReference {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            return transientRegistry[buffer]!
        }
    }
    
    subscript(sampler: SamplerDescriptor) -> Backend.SamplerReference {
        return persistentRegistry[sampler]
    }
    
    func bufferForCPUAccess(_ buffer: Buffer) -> Backend.BufferReference {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            return transientRegistry.accessLock.withLock { transientRegistry.allocateBufferIfNeeded(buffer, forceGPUPrivate: false) }
        }
    }
    
    func textureForCPUAccess(_ texture: Texture) -> Backend.TextureReference {
        if texture._usesPersistentRegistry {
            return persistentRegistry[texture]!
        } else {
            return transientRegistry.accessLock.withLock { transientRegistry.allocateTextureIfNeeded(texture, forceGPUPrivate: false) }
        }
    }
    
    func renderTargetTexture(_ texture: Texture) throws -> Backend.TextureReference {
        if texture.flags.contains(.windowHandle) {
            return try self.transientRegistry.allocateWindowHandleTexture(texture)
        }
        return self[texture]
    }
}
