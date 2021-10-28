//
//  Image+Texture.swift
//  Substrate
//
//  Created by Thomas Roughton on 11/03/20.
//

import Substrate

extension Texture {
    @available(*, deprecated, renamed: "init(image:pixelFormat:mipmapped:mipGenerationMode:storageMode:usage:flags:)")
    @inlinable
    public init(data: AnyImage, pixelFormat: PixelFormat, mipmapped: Bool = false, mipGenerationMode: MipGenerationMode = .gpuDefault, storageMode: StorageMode = .private, usage: TextureUsage = .shaderRead, flags: ResourceFlags = .persistent) async throws {
        try await self.init(image: data, pixelFormat: pixelFormat, mipmapped: mipmapped, mipGenerationMode: mipGenerationMode, storageMode: storageMode, usage: usage, flags: flags)
    }
    
    @available(*, deprecated, renamed: "init(image:mipmapped:mipGenerationMode:storageMode:usage:flags:)")
    @inlinable
    public init(data textureData: AnyImage, mipmapped: Bool = false, mipGenerationMode: MipGenerationMode = .gpuDefault, storageMode: StorageMode = .private, usage: TextureUsage = .shaderRead, flags: ResourceFlags = .persistent) async throws {
        try await self.init(image: textureData, pixelFormat: textureData.preferredPixelFormat, mipmapped: mipmapped, mipGenerationMode: mipGenerationMode, storageMode: storageMode, usage: usage, flags: flags)
    }
    
    /// Uploads a Image to a GPU texture using the GPUResourceUploader.
    @inlinable
    public init(image: AnyImage, pixelFormat: PixelFormat, mipmapped: Bool = false, mipGenerationMode: MipGenerationMode = .gpuDefault, storageMode: StorageMode = .private, usage: TextureUsage = .shaderRead, flags: ResourceFlags = .persistent) async throws {
        precondition(image.preferredPixelFormat.bytesPerPixel == pixelFormat.bytesPerPixel)
        let usage = usage.union(storageMode == .private ? TextureUsage.blitDestination : [])
        let descriptor = TextureDescriptor(type: .type2D, format: pixelFormat, width: image.width, height: image.height, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
        self = Texture(descriptor: descriptor, flags: flags)
        
        try await image.copyData(to: self, mipGenerationMode: mipGenerationMode)
    }
    
    /// Uploads a Image to a GPU texture using the GPUResourceUploader.
    @inlinable
    public init(image: AnyImage, mipmapped: Bool = false, mipGenerationMode: MipGenerationMode = .gpuDefault, storageMode: StorageMode = .private, usage: TextureUsage = .shaderRead, flags: ResourceFlags = .persistent) async throws {
        try await self.init(image: image, pixelFormat: image.preferredPixelFormat, mipmapped: mipmapped, mipGenerationMode: mipGenerationMode, storageMode: storageMode, usage: usage, flags: flags)
    }
}

extension Image {
    public init(texture: Texture, slice: Int = 0, mipmapLevel: Int = 0, alphaMode: ImageAlphaMode = .premultiplied) async {
        let pixelFormat = texture.descriptor.pixelFormat
        precondition(pixelFormat.bytesPerPixel == Double(MemoryLayout<T>.stride * pixelFormat.channelCount))
        
        if texture.descriptor.storageMode == .private {
            var descriptor = texture.descriptor
            descriptor.storageMode = .managed
            descriptor.textureType = .type2D
            descriptor.width = max(descriptor.width >> mipmapLevel, 1)
            descriptor.height = max(descriptor.height >> mipmapLevel, 1)
            descriptor.mipmapLevelCount = 1
            
            let cpuVisibleTexture = Texture(descriptor: descriptor, flags: .persistent)
            await GPUResourceUploader.runBlitPass { [descriptor] encoder in
                encoder.copy(from: texture, sourceSlice: slice, sourceLevel: mipmapLevel, sourceOrigin: Origin(), sourceSize: descriptor.size, to: cpuVisibleTexture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: Origin())
                encoder.synchronize(texture: cpuVisibleTexture)
            }
            
            await self.init(texture: cpuVisibleTexture, alphaMode: alphaMode)
            cpuVisibleTexture.dispose()
            
            return
        }
        
        assert(texture.storageMode != .private)
        
        self.init(width: max(texture.width >> mipmapLevel, 1), height: max(texture.height >> mipmapLevel, 1),
                  channelCount: pixelFormat.channelCount, colorSpace: pixelFormat.isSRGB ? .sRGB : .linearSRGB, alphaMode: alphaMode)
        
        let bytesPerRow = self.width * self.channelCount * MemoryLayout<T>.stride
        let width = self.width
        let height = self.height
        var region = Region(x: 0, y: 0, width: width, height: height)
        region.origin.z = slice
        await self.withUnsafeMutableBufferPointer { storage in
            await texture.copyBytes(to: storage.baseAddress!, bytesPerRow: bytesPerRow,
                                    region: region,
                                    mipmapLevel: mipmapLevel)
            
            if pixelFormat == .bgra8Unorm_sRGB {
                let buffer = storage.baseAddress as! UnsafeMutablePointer<UInt8>
                let texturePixels = width * height
                
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
}
