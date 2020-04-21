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
        let descriptor = TextureDescriptor(type: .type2D, format: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usage: usage.union(.blitDestination))
        self = Texture(descriptor: descriptor, flags: flags)
        
        let mips = mipmapped ? textureData.generateMipChain(wrapMode: .wrap, compressedBlockSize: pixelFormat.rowsPerBlock) : [textureData]
    
        for (i, data) in mips.enumerated() {
            let bytesPerRow = Double(data.width * pixelFormat.rowsPerBlock) * pixelFormat.bytesPerPixel
            GPUResourceUploader.replaceTextureRegion(Region(x: 0, y: 0, width: data.width, height: data.height), mipmapLevel: i, in: self, withBytes: data.data, bytesPerRow: Int(bytesPerRow), onUploadCompleted: { [data] _, _ in
                _ = data
            })
        }
    }
}

extension TextureData {
    public convenience init(texture: Texture, hasPremultipliedAlpha: Bool = false) {
        let pixelFormat = texture.descriptor.pixelFormat
        assert(pixelFormat.bytesPerPixel == Double(MemoryLayout<T>.stride * pixelFormat.channelCount))
        assert(texture.descriptor.textureType == .type2D)
        assert(texture.storageMode != .private)
        
        self.init(width: texture.width, height: texture.height,
                  channels: pixelFormat.channelCount, colourSpace: pixelFormat.isSRGB ? .sRGB : .linearSRGB, premultipliedAlpha: hasPremultipliedAlpha)
        texture.copyBytes(to: self.data, bytesPerRow: self.width * self.channels * MemoryLayout<T>.stride,
                          region: Region(x: 0, y: 0, width: texture.width, height: texture.height),
                          mipmapLevel: 0)
        
        if pixelFormat == .bgra8Unorm_sRGB {
            let buffer = self.data as! UnsafeMutablePointer<UInt8>
            let texturePixels = texture.width * texture.height
            
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
