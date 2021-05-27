//
//  GPUResourceUploader.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 10/01/19.
//

import SubstrateUtilities
import Dispatch

extension DispatchSemaphore {
    @inlinable
    public func withSemaphore<T>(_ perform: () throws -> T) rethrows -> T {
        self.wait()
        let result = try perform()
        self.signal()
        return result
    }
}

public final class GPUResourceUploader {
    // Useful to bypass uploading when running in GPU-less mode.
    public static var skipUpload = false
    
    static let lock = DispatchSemaphore(value: 1)
    @usableFromInline static var renderGraph : RenderGraph! = nil
    private static var maxUploadSize = 128 * 1024 * 1024
    private static var enqueuedPasses = [BlitRenderPass]()
    
    @usableFromInline
    final class UploadResourcePass : BlitRenderPass {
        public let name: String = "GPU Resource Upload"
        public let cacheMode: CPUCacheMode
        
        @usableFromInline let closure : (RawBufferSlice, _ bce: BlitCommandEncoder) -> Void
        @usableFromInline let stagingBufferLength: Int
        
        @inlinable
        init(stagingBufferLength: Int, cacheMode: CPUCacheMode, closure: @escaping (_ stagingBuffer: RawBufferSlice, _ bce: BlitCommandEncoder) -> Void) {
            assert(stagingBufferLength > 0)
            self.stagingBufferLength = stagingBufferLength
            self.cacheMode = cacheMode
            self.closure = closure
        }
        
        @inlinable
        public func execute(blitCommandEncoder: BlitCommandEncoder) {
            let stagingBuffer = Buffer(descriptor: BufferDescriptor(length: self.stagingBufferLength, storageMode: .shared, cacheMode: self.cacheMode, usage: .blitSource))
            let bufferSlice = stagingBuffer[stagingBuffer.range, accessType: .write]
            self.closure(bufferSlice, blitCommandEncoder)
        }
    }
    
    public static func initialise(maxUploadSize: Int = 128 * 1024 * 1024) {
        self.maxUploadSize = maxUploadSize
        self.renderGraph = RenderGraph(inflightFrameCount: 1)
    }
    
    private init() {}

    private static func flushHoldingLock() {
        precondition(self.enqueuedPasses.isEmpty || self.renderGraph != nil, "GPUResourceUploader has not been initialised.")
        
        var enqueuedBytes = 0
        for pass in self.enqueuedPasses {
            let passStagingBufferLength = (pass as? UploadResourcePass)?.stagingBufferLength ?? 0
            if enqueuedBytes > 0, enqueuedBytes + passStagingBufferLength > self.maxUploadSize {
                self.renderGraph.execute()
                enqueuedBytes = 0
            }
            self.renderGraph.addPass(pass)
            enqueuedBytes += passStagingBufferLength
        }
        self.enqueuedPasses.removeAll()
        
        if self.renderGraph?.hasEnqueuedPasses ?? false {
            self.renderGraph.execute()
        }
    }
    
    public static func flush() {
        self.lock.withSemaphore {
            self.flushHoldingLock()
        }
    }
    
    public static func onSubmission(_ perform: @escaping () -> Void) {
        self.lock.withSemaphore {
            self.renderGraph.onSubmission(perform)
        }
    }
    
    public static func addCopyPass(_ pass: @escaping (_ bce: BlitCommandEncoder) -> Void) {
        precondition(self.renderGraph != nil, "GPUResourceLoader.initialise() has not been called.")
        
        self.lock.withSemaphore {
            self.enqueuedPasses.append(CallbackBlitRenderPass(name: "Blit Callback Pass", execute: pass))
        }
    }
    
    public static func addUploadPass(stagingBufferLength: Int, cacheMode: CPUCacheMode = .defaultCache, pass: @escaping (RawBufferSlice, _ bce: BlitCommandEncoder) -> Void) {
        if GPUResourceUploader.skipUpload {
            return
        }
        precondition(self.renderGraph != nil, "GPUResourceLoader.initialise() has not been called.")
        
        self.lock.withSemaphore {
            self.enqueuedPasses.append(UploadResourcePass(stagingBufferLength: stagingBufferLength, cacheMode: cacheMode, closure: pass))
        }
    }
    
    public static func generateMipmaps(for texture: Texture) {
        self.lock.withSemaphore {
            self.enqueuedPasses.append(CallbackBlitRenderPass(name: "Generate Mipmaps for \(texture.label ?? "Texture(handle: \(texture.handle))")") { bce in
                bce.generateMipmaps(for: texture)
            })
        }
    }
    
    @available(*, deprecated, renamed: "uploadBytes(_:count:to:offset:onBytesCopied:)")
    public static func uploadBytes(_ bytes: UnsafeRawPointer, count: Int, to buffer: Buffer, offset: Int, onUploadCompleted: @escaping ((Buffer, UnsafeRawPointer) -> Void)) {
        self.uploadBytes(bytes, count: count, to: buffer, offset: offset, onBytesCopied: onUploadCompleted)
    }
    
    public static func uploadBytes(_ bytes: UnsafeRawPointer, count: Int, to buffer: Buffer, offset: Int, onBytesCopied: ((Buffer, UnsafeRawPointer) -> Void)? = nil) {
        assert(offset + count <= buffer.length)
        
        if buffer.storageMode == .shared || buffer.storageMode == .managed {
            buffer[offset..<(offset + count), accessType: .write].withContents {
                $0.copyMemory(from: bytes, byteCount: count)
            }
            onBytesCopied?(buffer, bytes)
        } else {
            assert(buffer.storageMode == .private)
            self.addUploadPass(stagingBufferLength: count, cacheMode: .writeCombined, pass: { slice, bce in
                slice.withContents {
                    $0.copyMemory(from: bytes, byteCount: count)
                }
                bce.copy(from: slice.buffer, sourceOffset: slice.range.lowerBound, to: buffer, destinationOffset: offset, size: count)
                onBytesCopied?(buffer, bytes)
            })
        }
    }
    
    @available(*, deprecated, renamed: "replaceTextureRegion(_:mipmapLevel:in:withBytes:bytesPerRow:onBytesCopied:)")
    public static func replaceTextureRegion(_ region: Region, mipmapLevel: Int, in texture: Texture, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, onUploadCompleted: @escaping ((Texture, UnsafeRawPointer) -> Void)) {
        self.replaceTextureRegion(region, mipmapLevel: mipmapLevel, in: texture, withBytes: bytes, bytesPerRow: bytesPerRow, onBytesCopied: onUploadCompleted)
    }
    
    public static func replaceTextureRegion(_ region: Region, mipmapLevel: Int, in texture: Texture, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, onBytesCopied: ((Texture, UnsafeRawPointer) -> Void)? = nil) {
        let rowCount = (texture.height >> mipmapLevel) / texture.descriptor.pixelFormat.rowsPerBlock
        self.replaceTextureRegion(region, mipmapLevel: mipmapLevel, slice: 0, in: texture, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerRow * rowCount, onBytesCopied: onBytesCopied)
    }
        
    
    @available(*, deprecated, renamed: "replaceTextureRegion(_:mipmapLevel:slice:in:withBytes:bytesPerRow:bytesPerImage:onBytesCopied:)")
    public static func replaceTextureRegion(_ region: Region, mipmapLevel: Int, slice: Int, in texture: Texture, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int, onUploadCompleted: @escaping ((Texture, UnsafeRawPointer) -> Void)) {
        self.replaceTextureRegion(region, mipmapLevel: mipmapLevel, slice: slice, in: texture, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage, onBytesCopied: onUploadCompleted)
    }
    
    public static func replaceTextureRegion(_ region: Region, mipmapLevel: Int, slice: Int, in texture: Texture, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int, onBytesCopied: ((Texture, UnsafeRawPointer) -> Void)? = nil) {
        if texture.storageMode == .shared || texture.storageMode == .managed {
            texture.replace(region: region, mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
            onBytesCopied?(texture, bytes)
        } else {
            assert(texture.storageMode == .private)
            
            self.addUploadPass(stagingBufferLength: bytesPerImage, cacheMode: .writeCombined, pass: { bufferSlice, bce in
                bufferSlice.withContents {
                    $0.copyMemory(from: bytes, byteCount: bytesPerImage)
                }
                bce.copy(from: bufferSlice.buffer, sourceOffset: bufferSlice.range.lowerBound, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: bytesPerImage, sourceSize: region.size, to: texture, destinationSlice: slice, destinationLevel: mipmapLevel, destinationOrigin: region.origin)
                
                onBytesCopied?(texture, bytes)
            })
        }
    }
}
