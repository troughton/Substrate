#if canImport(WebGPU)
import WebGPU

final class WebGPUBlitCommandEncoder: BlitCommandEncoderImpl {
    let encoder: WGPUCommandEncoder
    
    init(passRecord: RenderPassRecord, encoder: WGPUCommandEncoder) {
        self.encoder = encoder
    }
    
    func pushDebugGroup(_ string: String) {
        wgpuCommandEncoderPushDebugGroup(self.encoder, string)
    }
    
    func popDebugGroup() {
        wgpuCommandEncoderPopDebugGroup(self.encoder)
    }
    
    func insertDebugSignpost(_ string: String) {
        wgpuCommandEncoderInsertDebugMarker(self.encoder, string)
    }
    
    func setLabel(_ label: String) {
        wgpuCommandEncoderSetLabel(self.encoder, label)
    }
    
    func copy(from sourceBuffer: Buffer, sourceOffset: Int, sourceBytesPerRow: Int, sourceBytesPerImage: Int, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin, options: BlitOption) {
        let sourceBuffer = sourceBuffer.wgpuBuffer!
        
        var source = WGPUImageCopyBuffer()
        source.buffer = sourceBuffer.buffer
        source.layout = .init(nextInChain: nil,
                              offset: UInt64(sourceOffset + sourceBuffer.offset),
                              bytesPerRow: UInt32(sourceBytesPerRow),
                              rowsPerImage: UInt32(sourceBytesPerImage / sourceBytesPerRow))
        
        var dest = WGPUImageCopyTexture()
        dest.texture = destinationTexture.wgpuTexture!
        dest.origin = .init(x: UInt32(destinationOrigin.x), y: UInt32(destinationOrigin.y), z: UInt32(destinationOrigin.z))
        dest.aspect = WGPUTextureAspect_All
        dest.mipLevel = UInt32(destinationLevel)
        
        var copySize = WGPUExtent3D(width: UInt32(sourceSize.width), height: UInt32(sourceSize.height), depthOrArrayLayers: UInt32(sourceSize.depth))
        
        wgpuCommandEncoderCopyBufferToTexture(self.encoder, &source, &dest, &copySize)
    }
    
    func copy(from sourceBuffer: Buffer, sourceOffset: Int, to destinationBuffer: Buffer, destinationOffset: Int, size: Int) {
        let sourceBuffer = sourceBuffer.wgpuBuffer!
        let destinationBuffer = destinationBuffer.wgpuBuffer!
        wgpuCommandEncoderCopyBufferToBuffer(self.encoder, sourceBuffer.buffer, UInt64(sourceBuffer.offset + sourceOffset), destinationBuffer.buffer, UInt64(destinationBuffer.offset), UInt64(size))
    }
    
    func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationBuffer: Buffer, destinationOffset: Int, destinationBytesPerRow: Int, destinationBytesPerImage: Int, options: BlitOption) {
        var source = WGPUImageCopyTexture()
        source.texture = sourceTexture.wgpuTexture!
        source.origin = .init(x: UInt32(sourceOrigin.x), y: UInt32(sourceOrigin.y), z: UInt32(sourceOrigin.z))
        source.aspect = WGPUTextureAspect_All
        source.mipLevel = UInt32(sourceLevel)
        
        let destBuffer = destinationBuffer.wgpuBuffer!
        
        var dest = WGPUImageCopyBuffer()
        dest.buffer = destBuffer.buffer
        dest.layout = .init(nextInChain: nil,
                              offset: UInt64(destinationOffset + destBuffer.offset),
                              bytesPerRow: UInt32(destinationBytesPerRow),
                              rowsPerImage: UInt32(destinationBytesPerImage / destinationBytesPerRow))
        
        var copySize = WGPUExtent3D(width: UInt32(sourceSize.width), height: UInt32(sourceSize.height), depthOrArrayLayers: UInt32(sourceSize.depth))
        
        wgpuCommandEncoderCopyTextureToBuffer(self.encoder, &source, &dest, &copySize)
    }
    
    func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin) {
        var source = WGPUImageCopyTexture()
        source.texture = sourceTexture.wgpuTexture!
        source.origin = .init(x: UInt32(sourceOrigin.x), y: UInt32(sourceOrigin.y), z: UInt32(sourceOrigin.z))
        source.aspect = WGPUTextureAspect_All
        source.mipLevel = UInt32(sourceLevel)
        
        var dest = WGPUImageCopyTexture()
        dest.texture = destinationTexture.wgpuTexture!
        dest.origin = .init(x: UInt32(destinationOrigin.x), y: UInt32(destinationOrigin.y), z: UInt32(destinationOrigin.z))
        dest.aspect = WGPUTextureAspect_All
        dest.mipLevel = UInt32(destinationLevel)
        
        var copySize = WGPUExtent3D(width: UInt32(sourceSize.width), height: UInt32(sourceSize.height), depthOrArrayLayers: UInt32(sourceSize.depth))
        
        wgpuCommandEncoderCopyTextureToTexture(self.encoder, &source, &dest, &copySize)
    }
    
    func fill(buffer: Buffer, range: Range<Int>, value: UInt8) {
        precondition(value == 0, "WebGPU only supports clearing buffers.")
        let buffer = buffer.wgpuBuffer!
        
        wgpuCommandEncoderClearBuffer(self.encoder, buffer.buffer, UInt64(buffer.offset + range.lowerBound), UInt64(range.count))
    }
    
    func generateMipmaps(for texture: Texture) {
        unavailableFunction(.webGPU)
    }
    
    func synchronize(buffer: Buffer) {
        unavailableFunction(.webGPU)
    }
    
    func synchronize(texture: Texture) {
        unavailableFunction(.webGPU)
    }
    
    func synchronize(texture: Texture, slice: Int, level: Int) {
        unavailableFunction(.webGPU)
    }
}

#endif // canImport(WebGPU)
