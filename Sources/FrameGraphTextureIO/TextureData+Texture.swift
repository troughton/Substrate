//
//  TextureData+Texture.swift
//  SwiftFrameGraph
//
//  Created by Thomas Roughton on 11/03/20.
//

import SwiftFrameGraph

extension Texture {
    /// Uploads a TextureData to a GPU texture using the GPUResourceUploader.
    public init<T>(data textureData: TextureData<T>, pixelFormat: PixelFormat, mipmapped: Bool = false, storageMode: StorageMode = .private, usage: TextureUsage = .shaderRead, flags: ResourceFlags = .persistent) throws {
        let usage = usage.union(storageMode == .private ? TextureUsage.blitDestination : [])
        let descriptor = TextureDescriptor(type: .type2D, format: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
        self = Texture(descriptor: descriptor, flags: flags)
        
        let mips = mipmapped ? textureData.generateMipChain(wrapMode: .wrap, compressedBlockSize: pixelFormat.rowsPerBlock) : [textureData]
    
        for (i, data) in mips.enumerated() {
            let bytesPerRow = Double(data.width * pixelFormat.rowsPerBlock) * pixelFormat.bytesPerPixel
            let storage = data.storage
            GPUResourceUploader.replaceTextureRegion(Region(x: 0, y: 0, width: data.width, height: data.height), mipmapLevel: i, in: self, withBytes: storage.data.baseAddress!, bytesPerRow: Int(bytesPerRow), onUploadCompleted: { [storage] _, _ in
                _ = storage
            })
        }
    }
}

extension TextureData {
    public init(texture: Texture, mipmapLevel: Int = 0, hasPremultipliedAlpha: Bool = false) {
        let pixelFormat = texture.descriptor.pixelFormat
        assert(pixelFormat.bytesPerPixel == Double(MemoryLayout<T>.stride * pixelFormat.channelCount))
        assert(texture.descriptor.textureType == .type2D)
        assert(texture.storageMode != .private)
        
        self.init(width: max(texture.width >> mipmapLevel, 1), height: max(texture.height >> mipmapLevel, 1),
                  channels: pixelFormat.channelCount, colourSpace: pixelFormat.isSRGB ? .sRGB : .linearSRGB, premultipliedAlpha: hasPremultipliedAlpha)
        
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
