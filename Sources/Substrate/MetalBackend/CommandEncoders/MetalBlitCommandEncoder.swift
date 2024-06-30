//
//  File.swift
//  
//
//  Created by Thomas Roughton on 6/07/22.
//

#if canImport(Metal)
import Foundation
import Metal

final class MetalBlitCommandEncoder: BlitCommandEncoderImpl {
    let encoder: MTLBlitCommandEncoder
    let isAppleSiliconGPU: Bool
    
    init(encoder: MTLBlitCommandEncoder, isAppleSiliconGPU: Bool) {
        self.encoder = encoder
        self.isAppleSiliconGPU = isAppleSiliconGPU
    }
    
    func setLabel(_ label: String) {
        encoder.label = label
    }
    
    func pushDebugGroup(_ groupName: String) {
        encoder.pushDebugGroup(groupName)
    }
    
    func popDebugGroup() {
        encoder.popDebugGroup()
    }
    
    func insertDebugSignpost(_ string: String) {
        encoder.insertDebugSignpost(string)
    }
    
    func copy(from sourceBuffer: Buffer, sourceOffset: Int, sourceBytesPerRow: Int, sourceBytesPerImage: Int, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin, options: BlitOption = []) {
        assert(sourceBuffer.length - sourceOffset >= sourceSize.height * sourceBytesPerRow)
     
        let sourceBuffer = sourceBuffer.mtlBuffer!
        encoder.copy(from: sourceBuffer.buffer, sourceOffset: Int(sourceOffset) + sourceBuffer.offset, sourceBytesPerRow: Int(sourceBytesPerRow), sourceBytesPerImage: Int(sourceBytesPerImage), sourceSize: MTLSize(sourceSize), to: destinationTexture.mtlTexture!, destinationSlice: Int(destinationSlice), destinationLevel: Int(destinationLevel), destinationOrigin: MTLOrigin(destinationOrigin), options: MTLBlitOption(options))
    }
    
    func copy(from sourceBuffer: Buffer, sourceOffset: Int, to destinationBuffer: Buffer, destinationOffset: Int, size: Int) {
        let sourceBuffer = sourceBuffer.mtlBuffer!
        let destinationBuffer = destinationBuffer.mtlBuffer!
        encoder.copy(from: sourceBuffer.buffer, sourceOffset: Int(sourceOffset) + sourceBuffer.offset, to: destinationBuffer.buffer, destinationOffset: Int(destinationOffset) + destinationBuffer.offset, size: Int(size))
    }
    
    func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationBuffer: Buffer, destinationOffset: Int, destinationBytesPerRow: Int, destinationBytesPerImage: Int, options: BlitOption = []) {
        let destinationBuffer = destinationBuffer.mtlBuffer!
        encoder.copy(from: sourceTexture.mtlTexture!, sourceSlice: Int(sourceSlice), sourceLevel: Int(sourceLevel), sourceOrigin: MTLOrigin(sourceOrigin), sourceSize: MTLSize(sourceSize), to: destinationBuffer.buffer, destinationOffset: Int(destinationOffset) + destinationBuffer.offset, destinationBytesPerRow: Int(destinationBytesPerRow), destinationBytesPerImage: Int(destinationBytesPerImage), options: MTLBlitOption(options))
    }
    
    func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin) {
        encoder.copy(from: sourceTexture.mtlTexture!, sourceSlice: Int(sourceSlice), sourceLevel: Int(sourceLevel), sourceOrigin: MTLOrigin(sourceOrigin), sourceSize: MTLSize(sourceSize), to: destinationTexture.mtlTexture!, destinationSlice: Int(destinationSlice), destinationLevel: Int(destinationLevel), destinationOrigin: MTLOrigin(destinationOrigin))
    }
    
    func fill(buffer: Buffer, range: Range<Int>, value: UInt8) {
        let buffer = buffer.mtlBuffer!
        let range = (range.lowerBound + buffer.offset)..<(range.upperBound + buffer.offset)
        encoder.fill(buffer: buffer.buffer, range: range, value: value)
    }
    
    func generateMipmaps(for texture: Texture) {
        guard texture.descriptor.mipmapLevelCount > 1 else { return }
        encoder.generateMipmaps(for: texture.mtlTexture!)
    }
    
    func synchronize(buffer: Buffer) {
        #if os(macOS) || targetEnvironment(macCatalyst)
        if !self.isAppleSiliconGPU {
            encoder.synchronize(resource: buffer.mtlBuffer!.buffer)
        }
        #endif
    }
    
    func synchronize(texture: Texture) {
        #if os(macOS) || targetEnvironment(macCatalyst)
        if !self.isAppleSiliconGPU {
            encoder.synchronize(resource: texture.mtlTexture!)
        }
        #endif
    }
    
    func synchronize(texture: Texture, slice: Int, level: Int) {
        #if os(macOS) || targetEnvironment(macCatalyst)
        if !self.isAppleSiliconGPU {
            encoder.synchronize(texture: texture.mtlTexture!, slice: Int(slice), level: Int(level))
        }
        #endif
    }
}

extension MTLBlitCommandEncoder {
    func executeResourceCommands(resourceCommandIndex: inout Int, resourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>], passIndex: Int, order: PerformOrder, isAppleSiliconGPU: Bool) {
        while resourceCommandIndex < resourceCommands.count {
            let command = resourceCommands[resourceCommandIndex]
            
            guard command.index < passIndex || (command.index == passIndex && command.order == order) else {
                break
            }
            
            switch command.command {
            case .resourceMemoryBarrier, .scopedMemoryBarrier, .useResources, .useHeaps:
                break
                
            case .updateFence(let fence, _):
                self.updateFence(fence.fence)
                
            case .waitForFence(let fence, _):
                self.waitForFence(fence.fence)
            }
            
            resourceCommandIndex += 1
        }
    }
}

#endif // canImport(Metal)

