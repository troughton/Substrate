//
//  File.swift
//  
//
//  Created by Thomas Roughton on 6/07/22.
//

import Foundation
import Metal

final class MetalBlitCommandEncoder: BlitCommandEncoder {
    let encoder: MTLBlitCommandEncoder
    let resourceMap: FrameResourceMap<MetalBackend>
    let isAppleSiliconGPU: Bool
    
    init(encoder: MTLBlitCommandEncoder, resourceMap: FrameResourceMap<MetalBackend>, isAppleSiliconGPU: Bool) {
        self.encoder = encoder
        self.resourceMap = resourceMap
        self.isAppleSiliconGPU = isAppleSiliconGPU
    }
    
    override func copy(from sourceBuffer: Buffer, sourceOffset: Int, sourceBytesPerRow: Int, sourceBytesPerImage: Int, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin, options: BlitOption = []) {
        assert(sourceBuffer.length - sourceOffset >= sourceSize.height * sourceBytesPerRow)
     
        let sourceBuffer = resourceMap[sourceBuffer]!
        encoder.copy(from: sourceBuffer.buffer, sourceOffset: Int(sourceOffset) + sourceBuffer.offset, sourceBytesPerRow: Int(sourceBytesPerRow), sourceBytesPerImage: Int(sourceBytesPerImage), sourceSize: MTLSize(sourceSize), to: resourceMap[destinationTexture]!.texture, destinationSlice: Int(destinationSlice), destinationLevel: Int(destinationLevel), destinationOrigin: MTLOrigin(destinationOrigin), options: MTLBlitOption(options))
    }
    
    override func copy(from sourceBuffer: Buffer, sourceOffset: Int, to destinationBuffer: Buffer, destinationOffset: Int, size: Int) {
        let sourceBuffer = resourceMap[sourceBuffer]!
        let destinationBuffer = resourceMap[destinationBuffer]!
        encoder.copy(from: sourceBuffer.buffer, sourceOffset: Int(sourceOffset) + sourceBuffer.offset, to: destinationBuffer.buffer, destinationOffset: Int(destinationOffset) + destinationBuffer.offset, size: Int(size))
    }
    
    override func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationBuffer: Buffer, destinationOffset: Int, destinationBytesPerRow: Int, destinationBytesPerImage: Int, options: BlitOption = []) {
        let destinationBuffer = resourceMap[destinationBuffer]!
        encoder.copy(from: resourceMap[sourceTexture]!.texture, sourceSlice: Int(sourceSlice), sourceLevel: Int(sourceLevel), sourceOrigin: MTLOrigin(sourceOrigin), sourceSize: MTLSize(sourceSize), to: destinationBuffer.buffer, destinationOffset: Int(destinationOffset) + destinationBuffer.offset, destinationBytesPerRow: Int(destinationBytesPerRow), destinationBytesPerImage: Int(destinationBytesPerImage), options: MTLBlitOption(options))
    }
    
    override func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin) {
        encoder.copy(from: resourceMap[sourceTexture]!.texture, sourceSlice: Int(sourceSlice), sourceLevel: Int(sourceLevel), sourceOrigin: MTLOrigin(sourceOrigin), sourceSize: MTLSize(sourceSize), to: resourceMap[destinationTexture]!.texture, destinationSlice: Int(destinationSlice), destinationLevel: Int(destinationLevel), destinationOrigin: MTLOrigin(destinationOrigin))
    }
    
    override func fill(buffer: Buffer, range: Range<Int>, value: UInt8) {
        let buffer = resourceMap[buffer]!
        let range = (range.lowerBound + buffer.offset)..<(range.upperBound + buffer.offset)
        encoder.fill(buffer: buffer.buffer, range: range, value: value)
    }
    
    override func generateMipmaps(for texture: Texture) {
        guard texture.descriptor.mipmapLevelCount > 1 else { return }
        encoder.generateMipmaps(for: resourceMap[texture]!.texture)
    }
    
    override func synchronize(buffer: Buffer) {
        #if os(macOS) || targetEnvironment(macCatalyst)
        if !self.isAppleSiliconGPU {
            let buffer = resourceMap[buffer]!
            encoder.synchronize(resource: buffer.buffer)
        }
        #endif
    }
    
    override func synchronize(texture: Texture) {
        #if os(macOS) || targetEnvironment(macCatalyst)
        if !self.isAppleSiliconGPU {
            encoder.synchronize(resource: resourceMap[texture]!.texture)
        }
        #endif
    }
    
    override func synchronize(texture: Texture, slice: Int, level: Int) {
        #if os(macOS) || targetEnvironment(macCatalyst)
        if !self.isAppleSiliconGPU {
            encoder.synchronize(texture: resourceMap[texture]!.texture, slice: Int(slice), level: Int(level))
        }
        #endif
    }
}
