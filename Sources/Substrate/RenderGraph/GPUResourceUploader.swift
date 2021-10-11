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
    
    @GPUResourceUploader
    private static func _flush(cacheMode: CPUCacheMode, buffer: Buffer, allocationRange: (lowerBound: Int, upperBound: Int)) async -> RenderGraphExecutionWaitToken {
        let waitToken = await self.renderGraph.execute()
        await self.allocator(cacheMode: cacheMode).didSubmit(buffer: buffer, allocationRange: allocationRange, submissionIndex: waitToken.executionIndex)
        return waitToken
    }
    
    @discardableResult
    @GPUResourceUploader
    public static func runBlitPass(_ pass: @escaping @Sendable (_ bce: BlitCommandEncoder) -> Void) async -> RenderGraphExecutionWaitToken {
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
    
    public final class UploadBufferToken {
        public private(set) var stagingBuffer: Buffer!
        public let stagingBufferRange: Range<Int>
        public private(set) var contents: UnsafeMutableRawBufferPointer
        let cacheMode: CPUCacheMode
        let allocationRange: (lowerBound: Int, upperBound: Int)
        
        private var flushExecutionToken: RenderGraphExecutionWaitToken? = nil
        
        init(cacheMode: CPUCacheMode, stagingBuffer: Buffer, stagingBufferRange: Range<Int>, allocationRange: (lowerBound: Int, upperBound: Int)) {
            self.cacheMode = cacheMode
            self.stagingBuffer = stagingBuffer
            self.stagingBufferRange = stagingBufferRange
            self.allocationRange = allocationRange
            
            self.contents = stagingBuffer.withMutableContents(range: self.stagingBufferRange, { contents, writtenRange in
                writtenRange = writtenRange.lowerBound..<writtenRange.lowerBound
                return contents
            })
        }
        
        deinit {
            if self.flushExecutionToken == nil {
                _ = Task.detached { [cacheMode, stagingBuffer, allocationRange] in
                    await GPUResourceUploader._flush(cacheMode: cacheMode, buffer: stagingBuffer!, allocationRange: allocationRange)
                }
            }
        }
        
        public func didModifyBuffer() {
            precondition(self.flushExecutionToken == nil)
            
            if !self.stagingBufferRange.isEmpty {
                RenderBackend.buffer(self.stagingBuffer, didModifyRange: self.stagingBufferRange)
            }
        }
        
        @GPUResourceUploader
        @discardableResult
        public func flush() async -> RenderGraphExecutionWaitToken {
            if let flushExecutionToken = self.flushExecutionToken {
                return flushExecutionToken
            }
            
            let executionToken = await GPUResourceUploader._flush(cacheMode: self.cacheMode, buffer: self.stagingBuffer, allocationRange: self.allocationRange)
            
            self.flushExecutionToken = executionToken
            
            self.stagingBuffer = nil
            self.contents = .init(start: nil, count: 0) // Invalidate this token to avoid use-after-free issues
            
            return executionToken
        }
    }
    
    @discardableResult
    public static func extendedLifetimeUploadBuffer(length: Int, alignment: Int, cacheMode: CPUCacheMode = .defaultCache) async -> UploadBufferToken {
        precondition(self.renderGraph != nil, "GPUResourceLoader.initialise() has not been called.")
        
        // NOTE: this happens outside of the queue so we don't block concurrent execution of uploads.
        let (stagingBuffer, stagingBufferOffset, allocationRange) = await self.allocator(cacheMode: cacheMode).withBufferContents(byteCount: length, alignedTo: alignment) { contents, writtenRange in
            writtenRange = 0..<0 // Prevent an unnecessary flush.
        }
        
        return UploadBufferToken(cacheMode: cacheMode, stagingBuffer: stagingBuffer, stagingBufferRange: stagingBufferOffset..<(stagingBufferOffset + length), allocationRange: allocationRange)
    }
    
    @GPUResourceUploader
    @discardableResult
    public static func withUploadBuffer(length: Int, cacheMode: CPUCacheMode = .writeCombined, fillBuffer:  @Sendable (UnsafeMutableRawBufferPointer, inout Range<Int>) throws -> Void, copyFromBuffer: @escaping @Sendable (_ buffer: Buffer, _ offset: Int, _ blitEncoder: BlitCommandEncoder) -> Void) async rethrows -> RenderGraphExecutionWaitToken {
        if GPUResourceUploader.skipUpload {
            return RenderGraphExecutionWaitToken(queue: self.renderGraph.queue, executionIndex: 0)
        }
        precondition(self.renderGraph != nil, "GPUResourceLoader.initialise() has not been called.")
        
        let (stagingBuffer, stagingBufferOffset, allocationRange) = try await self.allocator(cacheMode: cacheMode).withBufferContents(byteCount: length, alignedTo: 256) { contents, writtenRange in
            try fillBuffer(contents, &writtenRange)
        }
        
        self.renderGraph.addBlitCallbackPass(name: "uploadBytes(length: \(length), cacheMode: \(cacheMode))") { bce in
            copyFromBuffer(stagingBuffer, stagingBufferOffset, bce)
        }
            
        return await self._flush(cacheMode: cacheMode, buffer: stagingBuffer, allocationRange: allocationRange)
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
            
            let (stagingBuffer, stagingBufferOffset, allocationRange) = try await self.allocator(cacheMode: cacheMode).withBufferContents(byteCount: count, alignedTo: 256) { contents, writtenRange in
                try bytes(contents, &writtenRange)
            }
            
            self.renderGraph.addBlitCallbackPass(name: "uploadBytes(count: \(count), to: \(buffer), offset: \(offset))") { bce in
                bce.copy(from: stagingBuffer, sourceOffset: stagingBufferOffset, to: buffer, destinationOffset: offset, size: count)
            }
            return await self._flush(cacheMode: cacheMode, buffer: stagingBuffer, allocationRange: allocationRange)
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
            
            let (stagingBuffer, stagingBufferOffset, allocationRange) = await self.allocator(cacheMode: cacheMode).withBufferContents(byteCount: bytesPerImage, alignedTo: 256) { contents, _ in
                contents.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: bytesPerImage))
            }
            
            self.renderGraph.addBlitCallbackPass(name: "replaceTextureRegion(\(region), mipmapLevel: \(mipmapLevel), slice: \(slice), in: \(texture), withBytes: \(bytes), bytesPerRow: \(bytesPerRow), bytesPerImage: \(bytesPerImage))") { bce in
                bce.copy(from: stagingBuffer, sourceOffset: stagingBufferOffset, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: bytesPerImage, sourceSize: region.size, to: texture, destinationSlice: slice, destinationLevel: mipmapLevel, destinationOrigin: region.origin)
            }
            return await self._flush(cacheMode: cacheMode, buffer: stagingBuffer, allocationRange: allocationRange)
        }
    }
}

extension Range {
    fileprivate func contains(_ other: Range) -> Bool {
        return other.lowerBound >= self.lowerBound && other.upperBound <= self.upperBound
    }
}

extension GPUResourceUploader {
    fileprivate final actor StagingBufferSubAllocator {
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
        
        
        func didSubmit(buffer: Buffer, allocationRange: (lowerBound: Int, upperBound: Int), submissionIndex: UInt64) {
            if buffer == self.buffer {
                let index = self.pendingCommands.firstIndex(where: { $0.command == .max && $0.allocationRange == allocationRange })!
                self.pendingCommands[index].command = submissionIndex
            } else {
                // This is a buffer that was allocated specifically for this command.
                let index = self.pendingCommands.firstIndex(where: { $0.command == .max && $0.tempBuffer == buffer })!
                self.pendingCommands[index].command = submissionIndex
                
                _ = Task {
                    // Make sure the buffer gets disposed even if no more resource uploads are submitted.
                    await RenderGraphExecutionWaitToken(queue: self.renderGraphQueue, executionIndex: submissionIndex).wait()
                    await self.processCompletedCommands()
                }
            }
        }
        func withBufferContents(byteCount: Int, alignedTo alignment: Int, perform: (UnsafeMutableRawBufferPointer, inout Range<Int>) throws -> Void) async rethrows -> (buffer: Buffer, offset: Int, allocationRange: (lowerBound: Int, upperBound: Int)) {
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
                self.pendingCommands.append((.max, (0, 0), buffer))
                
                return (buffer, 0, (0, 0))
            }
            
            if byteCount == 0 {
                var range = 0..<0
                try perform(UnsafeMutableRawBufferPointer(start: nil, count: 0), &range)
                return (self.buffer, 0, (lowerBound: 0, upperBound: 0))
            }
            
            while true {
                await self.processCompletedCommands()
            
                var alignedPosition = self.inUseRangeEnd.roundedUpToMultipleOfPowerOfTwo(of: alignment)
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
                
                let suballocatedRange = (self.inUseRangeEnd, allocationRange.endIndex)
                self.pendingCommands.append((.max, (self.inUseRangeEnd, allocationRange.endIndex), nil))
                self.inUseRangeEnd = allocationRange.endIndex
                
                if self.inUseRangeEnd < self.inUseRangeStart {
                    precondition((0..<self.inUseRangeEnd).contains(allocationRange))
                } else {
                    self.inUseRangeStart = min(self.inUseRangeStart, allocationRange.lowerBound)
                    precondition((self.inUseRangeStart..<self.inUseRangeEnd).contains(allocationRange))
                }
                
                var writtenRange = 0..<byteCount
                try perform(UnsafeMutableRawBufferPointer(start: self.bufferContents.advanced(by: allocationRange.lowerBound), count: byteCount), &writtenRange)
                
                if !writtenRange.isEmpty {
                    RenderBackend.buffer(self.buffer, didModifyRange: (allocationRange.lowerBound + writtenRange.lowerBound)..<(allocationRange.lowerBound + writtenRange.lowerBound + writtenRange.count))
                }
                
                return (self.buffer, allocationRange.lowerBound, suballocatedRange)
            }
        }
        
        private func processCompletedCommands() async {
            while self.pendingCommands.first?.command ?? .max <= self.renderGraphQueue.lastCompletedCommand {
                let (_, range, tempBuffer) = self.pendingCommands.popFirst()!
                if let tempBuffer = tempBuffer {
                    tempBuffer.dispose()
                } else {
                    self.inUseRangeStart = range.upperBound
                }
            }
        }
    }
}
