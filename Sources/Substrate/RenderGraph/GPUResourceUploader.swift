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
    
    @usableFromInline static var renderGraph : RenderGraph! = nil
    private static var maxUploadSize = 128 * 1024 * 1024
    private static var enqueuedPassLock = SpinLock()
    private static var enqueuedPasses = [UploadResourcePass]()
    
    @usableFromInline
    final class UploadResourcePass : BlitRenderPass {
        public let name: String = "GPU Resource Upload"
        
        @usableFromInline let closure : (_ buffer: Buffer, _ bce: BlitCommandEncoder) async -> Void
        @usableFromInline let stagingBufferLength: Int
        
        @inlinable
        init(stagingBufferLength: Int, closure: @escaping (_ buffer: Buffer, _ bce: BlitCommandEncoder) async -> Void) {
            assert(stagingBufferLength > 0)
            self.stagingBufferLength = stagingBufferLength
            self.closure = closure
        }
        
        @inlinable
        public func execute(blitCommandEncoder: BlitCommandEncoder) async {
            let stagingBuffer = Buffer(descriptor: BufferDescriptor(length: self.stagingBufferLength, storageMode: .shared, cacheMode: .writeCombined, usage: .blitSource))
            await self.closure(stagingBuffer, blitCommandEncoder)
        }
    }
    
    public static func initialise(maxUploadSize: Int = 128 * 1024 * 1024) {
        self.maxUploadSize = maxUploadSize
        self.renderGraph = RenderGraph(inflightFrameCount: 1)
    }
    
    private init() {}

    public static func flush() async {
        var enqueuedBytes = 0
        for pass in self.enqueuedPasses {
            if enqueuedBytes > 0, enqueuedBytes + pass.stagingBufferLength > self.maxUploadSize {
                self.renderGraph.execute()
                enqueuedBytes = 0
            }
            self.renderGraph.addPass(pass)
            enqueuedBytes += pass.stagingBufferLength
        }
        self.enqueuedPasses.removeAll()
        
        if self.renderGraph.hasEnqueuedPasses {
            self.renderGraph.execute()
        }
    }
    
    public static func addCopyPass(_ pass: @escaping (_ bce: BlitCommandEncoder) async -> Void) {
        precondition(self.renderGraph != nil, "GPUResourceLoader.initialise() has not been called.")
        
        renderGraph.addBlitCallbackPass(pass)
    }
    
    public static func addUploadPass(stagingBufferLength: Int, pass: @escaping (_ buffer: Buffer, _ bce: BlitCommandEncoder) async -> Void) {
        if GPUResourceUploader.skipUpload {
            return
        }
        precondition(self.renderGraph != nil, "GPUResourceLoader.initialise() has not been called.")
        
        self.enqueuedPasses.append(UploadResourcePass(stagingBufferLength: stagingBufferLength, closure: pass))
    }
    
    public static func generateMipmaps(for texture: Texture) {
        self.renderGraph.addBlitCallbackPass(name: "Generate Mipmaps for \(texture.label ?? "Texture(handle: \(texture.handle))")") { bce in
            bce.generateMipmaps(for: texture)
        }
    }
    
    public static func uploadBytes(_ bytes: UnsafeRawPointer, count: Int, to buffer: Buffer, offset: Int) -> Task.Handle<Void, Never> {
        assert(offset + count <= buffer.length)
        
        if buffer.storageMode == .shared || buffer.storageMode == .managed {
            return detach {
                await buffer.withMutableContentsAsync(range: offset..<(offset + count)) {
                    $0.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: count))
                    _ = $1
                }
            }
        } else {
            assert(buffer.storageMode == .private)
            
            let group = DispatchGroup()
            group.enter()
            
            self.addUploadPass(stagingBufferLength: count, pass: { stagingBuffer, bce in
                stagingBuffer.withMutableContents { contents, _ in contents.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: count)) }
                bce.copy(from: stagingBuffer, sourceOffset: stagingBuffer.range.lowerBound, to: buffer, destinationOffset: offset, size: count)
                group.leave()
            })
            
            return detach {
                while group.wait(timeout: .now()) == .timedOut {
                    await Task.yield()
                }
            }
        }
    }
    
    public static func replaceTextureRegion(_ region: Region, mipmapLevel: Int, in texture: Texture, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) -> Task.Handle<Void, Never> {
        let rowCount = (texture.height >> mipmapLevel) / texture.descriptor.pixelFormat.rowsPerBlock
        return self.replaceTextureRegion(region, mipmapLevel: mipmapLevel, slice: 0, in: texture, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerRow * rowCount)
    }
    
    public static func replaceTextureRegion(_ region: Region, mipmapLevel: Int, slice: Int, in texture: Texture, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) -> Task.Handle<Void, Never> {
        if texture.storageMode == .shared || texture.storageMode == .managed {
            return detach {
                await texture.replace(region: region, mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
            }
        } else {
            assert(texture.storageMode == .private)
            
            let group = DispatchGroup()
            group.enter()
            
            self.addUploadPass(stagingBufferLength: bytesPerImage, pass: { stagingBuffer, bce in
                stagingBuffer.withMutableContents { contents, _ in
                    contents.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: bytesPerImage))
                }
                bce.copy(from: stagingBuffer, sourceOffset: stagingBuffer.range.lowerBound, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: bytesPerImage, sourceSize: region.size, to: texture, destinationSlice: slice, destinationLevel: mipmapLevel, destinationOrigin: region.origin)
                
                group.leave()
            })
            
            return detach {
                while group.wait(timeout: .now()) == .timedOut {
                    await Task.yield()
                }
            }
        }
    }
}
