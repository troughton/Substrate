//
//  TextureData+Texture.swift
//  Substrate
//
//  Created by Thomas Roughton on 11/03/20.
//

import Substrate

extension Texture {
    /// Uploads a TextureData to a GPU texture using the GPUResourceUploader.
    @inlinable
    public init(data textureData: AnyTextureData, pixelFormat: PixelFormat, mipmapped: Bool = false, mipGenerationMode: MipGenerationMode = .gpuDefault, storageMode: StorageMode = .private, usage: TextureUsage = .shaderRead, flags: ResourceFlags = .persistent) throws {
        precondition(textureData.preferredPixelFormat.bytesPerPixel == pixelFormat.bytesPerPixel)
        let usage = usage.union(storageMode == .private ? TextureUsage.blitDestination : [])
        let descriptor = TextureDescriptor(type: .type2D, format: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
        self = Texture(descriptor: descriptor, flags: flags)
        
        try textureData.copyData(to: self, mipGenerationMode: mipGenerationMode)
    }
    
    /// Uploads a TextureData to a GPU texture using the GPUResourceUploader.
    @inlinable
    public init(data textureData: AnyTextureData, mipmapped: Bool = false, mipGenerationMode: MipGenerationMode = .gpuDefault, storageMode: StorageMode = .private, usage: TextureUsage = .shaderRead, flags: ResourceFlags = .persistent) throws {
        try self.init(data: textureData, pixelFormat: textureData.preferredPixelFormat, mipmapped: mipmapped, mipGenerationMode: mipGenerationMode, storageMode: storageMode, usage: usage, flags: flags)
    }
}

extension TextureData {
    public init(texture: Texture, mipmapLevel: Int = 0, hasPremultipliedAlpha: Bool = true) {
        let pixelFormat = texture.descriptor.pixelFormat
        precondition(pixelFormat.bytesPerPixel == Double(MemoryLayout<T>.stride * pixelFormat.channelCount))
        precondition(texture.descriptor.textureType == .type2D)
        
        if texture.descriptor.storageMode == .private {
            var descriptor = texture.descriptor
            descriptor.storageMode = .managed
            descriptor.width = max(descriptor.width >> mipmapLevel, 1)
            descriptor.height = max(descriptor.height >> mipmapLevel, 1)
            descriptor.mipmapLevelCount = 1
            
            let cpuVisibleTexture = Texture(descriptor: descriptor, flags: .persistent)
            GPUResourceUploader.addCopyPass { encoder in
                encoder.copy(from: texture, sourceSlice: 0, sourceLevel: mipmapLevel, sourceOrigin: Origin(), sourceSize: descriptor.size, to: cpuVisibleTexture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: Origin())
                encoder.synchronize(texture: cpuVisibleTexture)
            }
            GPUResourceUploader.flush()
            
            self.init(texture: cpuVisibleTexture, hasPremultipliedAlpha: hasPremultipliedAlpha)
            cpuVisibleTexture.dispose()
            
            return
        }
        
        assert(texture.storageMode != .private)
        
        self.init(width: max(texture.width >> mipmapLevel, 1), height: max(texture.height >> mipmapLevel, 1),
                  channels: pixelFormat.channelCount, colorSpace: pixelFormat.isSRGB ? .sRGB : .linearSRGB, alphaMode: hasPremultipliedAlpha ? .premultiplied : .postmultiplied)
        
        texture.waitForCPUAccess(accessType: .read)
        texture.copyBytes(to: self.storage.data.baseAddress!, bytesPerRow: self.width * self.channelCount * MemoryLayout<T>.stride,
                          region: Region(x: 0, y: 0, width: self.width, height: self.height),
                          mipmapLevel: mipmapLevel)
        
        if pixelFormat == .bgra8Unorm_sRGB {
            let buffer = self.storage.data.baseAddress as! UnsafeMutablePointer<UInt8>
            let texturePixels = self.width * self.height
            
            for i in 0..<texturePixels {
                let bufferPtr = buffer.advanced(by: 4 * i)
                let b = bufferPtr[0]
                let r = bufferPtr[2]
                bufferPtr[0] = r
                bufferPtr[2] = b
            }
        }
    }
}
