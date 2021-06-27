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

@globalActor
public final actor GPUResourceUploader {
    // Useful to bypass uploading when running in GPU-less mode.
    public static var skipUpload = false
    
    @usableFromInline static var renderGraph : RenderGraph! = nil
    private static var maxUploadSize = 128 * 1024 * 1024
    
    public static let shared = GPUResourceUploader()
    
    private static var defaultCacheAllocator: StagingBufferSubAllocator! = nil
    private static var writeCombinedAllocator: StagingBufferSubAllocator! = nil
    
    public static func initialise(maxUploadSize: Int = 128 * 1024 * 1024) {
        self.maxUploadSize = maxUploadSize
        self.renderGraph = RenderGraph(inflightFrameCount: 0) //
    }
    
    @available(*, deprecated, message: "GPUResourceUploader now flushes immediately on each upload.")
    public static func flush() {
        
    }
    
    private init() {}
    
    private static func allocator(cacheMode: CPUCacheMode) -> StagingBufferSubAllocator {
        switch cacheMode {
        case .defaultCache:
            if self.defaultCacheAllocator == nil {
                self.defaultCacheAllocator = .init(renderGraphQueue: self.renderGraph.queue, stagingBufferLength: self.maxUploadSize, cacheMode: cacheMode)
            }
            return self.defaultCacheAllocator
        case .writeCombined:
            if self.writeCombinedAllocator == nil {
                self.writeCombinedAllocator = .init(renderGraphQueue: self.renderGraph.queue, stagingBufferLength: self.maxUploadSize, cacheMode: cacheMode)
            }
            return self.writeCombinedAllocator
        }
    }

    static var nextCommandIndex: UInt64 {
        return self.renderGraph.queue.lastSubmittedCommand + 1
    }
    
    @GPUResourceUploader
    @discardableResult
    public static func runBlitPass(_ pass: @escaping (_ bce: BlitCommandEncoder) -> Void) async -> RenderGraphExecutionWaitToken {
        precondition(self.renderGraph != nil, "GPUResourceLoader.initialise() has not been called.")
        
        self.renderGraph.addPass(CallbackBlitRenderPass(name: "GPUResourceUploader Copy Pass", execute: pass))
        return await self.renderGraph.execute()
    }
    
    @GPUResourceUploader
    @discardableResult
    public static func generateMipmaps(for texture: Texture) async -> RenderGraphExecutionWaitToken {
            self.renderGraph.addPass(CallbackBlitRenderPass(name: "Generate Mipmaps for \(texture.label ?? "Texture(handle: \(texture.handle))")") { bce in
                bce.generateMipmaps(for: texture)
            })
            
            return await self.renderGraph.execute()
    }
    
    @GPUResourceUploader
    @discardableResult
    public static func withUploadBuffer(length: Int, cacheMode: CPUCacheMode = .writeCombined, fillBuffer: (UnsafeMutableRawBufferPointer, inout Range<Int>) throws -> Void, copyFromBuffer: @escaping (_ buffer: Buffer, _ offset: Int, _ blitEncoder: BlitCommandEncoder) -> Void) async rethrows -> RenderGraphExecutionWaitToken {
        if GPUResourceUploader.skipUpload {
            return RenderGraphExecutionWaitToken(queue: self.renderGraph.queue, executionIndex: 0)
        }
        precondition(self.renderGraph != nil, "GPUResourceLoader.initialise() has not been called.")
        
            let (stagingBuffer, stagingBufferOffset) = try await self.allocator(cacheMode: cacheMode).withBufferContents(byteCount: length, alignedTo: 256, submissionIndex: self.nextCommandIndex) { contents, writtenRange in
                try fillBuffer(contents, &writtenRange)
            }
            
            self.renderGraph.addBlitCallbackPass(name: "uploadBytes(length: \(length), cacheMode: \(cacheMode))") { bce in
                copyFromBuffer(stagingBuffer, stagingBufferOffset, bce)
            }
            
            return await self.renderGraph.execute()
    }
    
    @GPUResourceUploader
    @discardableResult
    public static func uploadBytes(_ bytes: UnsafeRawPointer, count: Int, to buffer: Buffer, offset: Int) async -> RenderGraphExecutionWaitToken {
        return await self.uploadBytes(count: count, to: buffer, offset: offset) { (buffer, _) in buffer.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: count)) }
    }
    
    @GPUResourceUploader
    @discardableResult
    public static func uploadBytes(count: Int, to buffer: Buffer, offset: Int, _ bytes: (UnsafeMutableRawBufferPointer, inout Range<Int>) throws -> Void) async rethrows -> RenderGraphExecutionWaitToken {
        if GPUResourceUploader.skipUpload {
            return RenderGraphExecutionWaitToken(queue: self.renderGraph.queue, executionIndex: 0)
        }
        precondition(self.renderGraph != nil, "GPUResourceLoader.initialise() has not been called.")
        
        assert(offset + count <= buffer.length)
        
            if buffer.storageMode == .shared || buffer.storageMode == .managed {
                try buffer.withMutableContents(range: offset..<(offset + count)) {
                    try bytes($0, &$1)
                }
                return RenderGraphExecutionWaitToken(queue: self.renderGraph.queue, executionIndex: 0)
            } else {
                assert(buffer.storageMode == .private)
                
                let cacheMode = CPUCacheMode.writeCombined
                
                let (stagingBuffer, stagingBufferOffset) = try await self.allocator(cacheMode: cacheMode).withBufferContents(byteCount: count, alignedTo: 256, submissionIndex: self.nextCommandIndex) { contents, writtenRange in
                    try bytes(contents, &writtenRange)
                }
                
                self.renderGraph.addBlitCallbackPass(name: "uploadBytes(count: \(count), to: \(buffer), offset: \(offset))") { bce in
                    bce.copy(from: stagingBuffer, sourceOffset: stagingBufferOffset, to: buffer, destinationOffset: offset, size: count)
                }
                return await self.renderGraph.execute()
            }
    }
    
    @GPUResourceUploader
    @discardableResult
    public static func replaceTextureRegion(_ region: Region, mipmapLevel: Int, in texture: Texture, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) async -> RenderGraphExecutionWaitToken {
        let rowCount = (texture.height >> mipmapLevel) / texture.descriptor.pixelFormat.rowsPerBlock
        return await self.replaceTextureRegion(region, mipmapLevel: mipmapLevel, slice: 0, in: texture, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerRow * rowCount)
    }
    
    @GPUResourceUploader
    @discardableResult
    public static func replaceTextureRegion(_ region: Region, mipmapLevel: Int, slice: Int, in texture: Texture, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) async -> RenderGraphExecutionWaitToken {
        if GPUResourceUploader.skipUpload {
            return RenderGraphExecutionWaitToken(queue: self.renderGraph.queue, executionIndex: 0)
        }
        precondition(self.renderGraph != nil, "GPUResourceLoader.initialise() has not been called.")
        
        if texture.storageMode == .shared || texture.storageMode == .managed {
            await texture.replace(region: region, mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
            return RenderGraphExecutionWaitToken(queue: self.renderGraph.queue, executionIndex: 0)
        } else {
            assert(texture.storageMode == .private)
            
            let cacheMode = CPUCacheMode.writeCombined
            
            let (stagingBuffer, stagingBufferOffset) = await self.allocator(cacheMode: cacheMode).withBufferContents(byteCount: bytesPerImage, alignedTo: 256, submissionIndex: self.nextCommandIndex) { contents, _ in
                contents.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: bytesPerImage))
            }
            
            self.renderGraph.addBlitCallbackPass(name: "replaceTextureRegion(\(region), mipmapLevel: \(mipmapLevel), slice: \(slice), in: \(texture), withBytes: \(bytes), bytesPerRow: \(bytesPerRow), bytesPerImage: \(bytesPerImage))") { bce in
                bce.copy(from: stagingBuffer, sourceOffset: stagingBufferOffset, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: bytesPerImage, sourceSize: region.size, to: texture, destinationSlice: slice, destinationLevel: mipmapLevel, destinationOrigin: region.origin)
            }
            return await self.renderGraph.execute()
        }
    }
}

extension GPUResourceUploader {
    
    // NOTE: synchronised by the GPUResourceUploader global actor
    fileprivate final class StagingBufferSubAllocator {
        private static let blockAlignment = 64
        
        let renderGraphQueue: Queue
        let capacity: Int
        let buffer: Buffer
        let bufferContents: UnsafeMutableRawPointer
        
        var inUseRangeStart = 0
        var inUseRangeEnd = 0
        
        let pendingCommands: RingBuffer<(command: UInt64, allocationRange: (lowerBound: Int, upperBound: Int), tempBuffer: Buffer?)> = .init()
        
        public init(renderGraphQueue: Queue, stagingBufferLength: Int = 128 * 1024 * 1024, cacheMode: CPUCacheMode) {
            self.renderGraphQueue = renderGraphQueue
            self.capacity = stagingBufferLength
            self.buffer = Buffer(length: stagingBufferLength, storageMode: .managed, cacheMode: cacheMode, usage: .blitSource, flags: .persistent)
            self.bufferContents = RenderBackend.bufferContents(for: self.buffer, range: self.buffer.range)!
        }
        
        deinit {
            self.buffer.dispose()
        }
        
        @GPUResourceUploader
        func withBufferContents(byteCount: Int, alignedTo alignment: Int, submissionIndex: UInt64, perform: (UnsafeMutableRawBufferPointer, inout Range<Int>) throws -> Void) async rethrows -> (buffer: Buffer, offset: Int) {
            
            if byteCount > self.capacity {
                // Allocate a buffer specifically for this staging command.
                let buffer = Buffer(length: byteCount, storageMode: .shared, cacheMode: self.buffer.descriptor.cacheMode, usage: .blitSource, flags: .persistent)
                
                do {
                    try buffer.withMutableContents { buffer, range in
                        try perform(buffer, &range)
                    }
                } catch {
                    buffer.dispose()
                    throw error
                }
                self.pendingCommands.append((submissionIndex, (0, 0), buffer))
                
                _ = Task {
                    await RenderGraphExecutionWaitToken(queue: self.renderGraphQueue, executionIndex: submissionIndex).wait()
                    await self.processCompletedCommands()
                }
                
                return (buffer, 0)
            }
            
            let alignment = byteCount == 0 ? 1 : alignment // Don't align for empty allocations
            
            while true {
                await self.processCompletedCommands()
                
                var alignedPosition = ((self.inUseRangeEnd + alignment - 1) & ~(alignment - 1)) % self.capacity
                var allocationRange = alignedPosition..<(alignedPosition + byteCount)
                
                if allocationRange.endIndex > self.capacity {
                    alignedPosition = 0
                    allocationRange = alignedPosition..<(alignedPosition + byteCount)
                }
                
                if self.inUseRangeStart > self.inUseRangeEnd {
                    if (self.inUseRangeStart..<self.capacity).overlaps(allocationRange) ||
                        (0..<self.inUseRangeEnd).overlaps(allocationRange) {
                        await Task.yield() // Wait until some pending commands are completed on the GPU.
                        continue
                    }
                } else {
                    if (self.inUseRangeStart..<self.inUseRangeEnd).overlaps(allocationRange) {
                        await Task.yield() // Wait until some pending commands are completed on the GPU.
                        continue
                    }
                }
                
                self.pendingCommands.append((submissionIndex, (self.inUseRangeEnd, allocationRange.endIndex), nil))
                self.inUseRangeEnd = allocationRange.endIndex
                
                var writtenRange = 0..<byteCount
                try perform(UnsafeMutableRawBufferPointer(start: self.bufferContents.advanced(by: allocationRange.lowerBound), count: byteCount), &writtenRange)
                RenderBackend.buffer(self.buffer, didModifyRange: (allocationRange.lowerBound + writtenRange.lowerBound)..<(allocationRange.lowerBound + writtenRange.lowerBound + writtenRange.count))
                
                return (self.buffer, allocationRange.lowerBound)
            }
        }
        
        @GPUResourceUploader
        private func processCompletedCommands() async {
            while self.pendingCommands.first?.command ?? .max <= self.renderGraphQueue.lastCompletedCommand {
                let (_, range, tempBuffer) = self.pendingCommands.popFirst()!
                if let tempBuffer = tempBuffer {
                    tempBuffer.dispose()
                } else {
                    precondition(range.lowerBound == self.inUseRangeStart)
                    self.inUseRangeStart = range.upperBound
                }
            }
        }
    }
}
