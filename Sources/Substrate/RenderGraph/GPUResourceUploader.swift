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
    private static let queue = DispatchQueue(label: "GPUResourceUploader Queue")
    
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
    
    private static func _flush(cacheMode: CPUCacheMode, buffer: Buffer, allocationRange: Range<Int>) -> RenderGraphExecutionWaitToken {
        let waitToken = self.renderGraph.execute()
        self.allocator(cacheMode: cacheMode).didSubmit(buffer: buffer, allocationRange: allocationRange, submissionIndex: waitToken.executionIndex)
        return waitToken
    }
    
    @discardableResult
    public static func runBlitPass(_ pass: @escaping (_ bce: BlitCommandEncoder) -> Void) -> RenderGraphExecutionWaitToken {
        precondition(self.renderGraph != nil, "GPUResourceLoader.initialise() has not been called.")
        
        return self.queue.sync {
            self.renderGraph.addPass(CallbackBlitRenderPass(name: "GPUResourceUploader Copy Pass", execute: pass))
            return self.renderGraph.execute()
        }
    }
    
    @discardableResult
    public static func generateMipmaps(for texture: Texture) -> RenderGraphExecutionWaitToken {
        return self.queue.sync {
            self.renderGraph.addPass(CallbackBlitRenderPass(name: "Generate Mipmaps for \(texture.label ?? "Texture(handle: \(texture.handle))")") { bce in
                bce.generateMipmaps(for: texture)
            })
            
            return self.renderGraph.execute()
        }
    }
    
    public final class UploadBufferToken {
        public private(set) var stagingBuffer: Buffer!
        public let stagingBufferRange: Range<Int>
        public private(set) var contents: UnsafeMutableRawBufferPointer
        let cacheMode: CPUCacheMode
        
        private var flushExecutionToken: RenderGraphExecutionWaitToken? = nil
        
        init(cacheMode: CPUCacheMode, stagingBuffer: Buffer, stagingBufferRange: Range<Int>) {
            self.cacheMode = cacheMode
            self.stagingBuffer = stagingBuffer
            self.stagingBufferRange = stagingBufferRange
            
            self.contents = stagingBuffer.withMutableContents(range: self.stagingBufferRange, { contents, writtenRange in
                writtenRange = writtenRange.lowerBound..<writtenRange.lowerBound
                return contents
            })
        }
        
        deinit {
            _ = self.flush()
        }
        
        public func didModifyBuffer() {
            precondition(self.flushExecutionToken == nil)
            
            if !self.stagingBufferRange.isEmpty, self.stagingBuffer.descriptor.storageMode != .shared {
                RenderBackend.buffer(self.stagingBuffer, didModifyRange: self.stagingBufferRange)
            }
        }
        
        public func didFlush(token: RenderGraphExecutionWaitToken) {
            precondition(self.flushExecutionToken == nil)
            
            GPUResourceUploader.queue.sync {
                GPUResourceUploader.allocator(cacheMode: self.stagingBuffer.descriptor.cacheMode).didSubmit(buffer: self.stagingBuffer, allocationRange: self.stagingBufferRange, submissionIndex: token.executionIndex)
            }
            
            self.flushExecutionToken = token
            
            self.stagingBuffer = nil
            self.contents = .init(start: nil, count: 0) // Invalidate this token to avoid use-after-free issues
        }
        
        
        @discardableResult
        public func flush() -> RenderGraphExecutionWaitToken {
            if let flushExecutionToken = self.flushExecutionToken {
                return flushExecutionToken
            }
            
            let executionToken = GPUResourceUploader.queue.sync {
                return GPUResourceUploader._flush(cacheMode: self.cacheMode, buffer: self.stagingBuffer, allocationRange: self.stagingBufferRange)
            }
            
            self.didFlush(token: executionToken)
            return executionToken
        }
    }
    
    @discardableResult
    public static func extendedLifetimeUploadBuffer(length: Int, alignment: Int, cacheMode: CPUCacheMode = .defaultCache) -> UploadBufferToken {
        precondition(self.renderGraph != nil, "GPUResourceLoader.initialise() has not been called.")
        
        // NOTE: this happens outside of the queue so we don't block concurrent execution of uploads.
        let (stagingBuffer, _, allocationRange) = self.queue.sync { self.allocator(cacheMode: cacheMode) }.withBufferContents(byteCount: length, alignedTo: alignment) { contents, writtenRange in
            writtenRange = 0..<0 // Prevent an unnecessary flush.
        }
        
        return UploadBufferToken(cacheMode: cacheMode, stagingBuffer: stagingBuffer, stagingBufferRange: allocationRange)
    }
    
    @discardableResult
    public static func withUploadBuffer(length: Int, cacheMode: CPUCacheMode = .writeCombined, fillBuffer: (UnsafeMutableRawBufferPointer, inout Range<Int>) throws -> Void, copyFromBuffer: @escaping (_ buffer: Buffer, _ offset: Int, _ blitEncoder: BlitCommandEncoder) -> Void) rethrows -> RenderGraphExecutionWaitToken {
        if GPUResourceUploader.skipUpload {
            return RenderGraphExecutionWaitToken(queue: self.renderGraph.queue, executionIndex: 0)
        }
        precondition(self.renderGraph != nil, "GPUResourceLoader.initialise() has not been called.")
        
        // NOTE: this happens outside of the queue so we don't block concurrent execution of uploads.
        let (stagingBuffer, stagingBufferOffset, allocationRange) = try self.queue.sync { self.allocator(cacheMode: cacheMode) }.withBufferContents(byteCount: length, alignedTo: 256) { contents, writtenRange in
            try fillBuffer(contents, &writtenRange)
        }
        
        return self.queue.sync {
            self.renderGraph.addBlitCallbackPass(name: "uploadBytes(length: \(length), cacheMode: \(cacheMode))") { bce in
                copyFromBuffer(stagingBuffer, stagingBufferOffset, bce)
            }
            
            return self._flush(cacheMode: cacheMode, buffer: stagingBuffer, allocationRange: allocationRange)
        }
    }
    
    @discardableResult
    public static func uploadBytes(_ bytes: UnsafeRawPointer, count: Int, to buffer: Buffer, offset: Int) -> RenderGraphExecutionWaitToken {
        self.uploadBytes(count: count, to: buffer, offset: offset) { (buffer, _) in buffer.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: count)) }
    }
    
    @discardableResult
    public static func uploadBytes(count: Int, to buffer: Buffer, offset: Int, _ bytes: (UnsafeMutableRawBufferPointer, inout Range<Int>) -> Void) -> RenderGraphExecutionWaitToken {
        if GPUResourceUploader.skipUpload {
            return RenderGraphExecutionWaitToken(queue: self.renderGraph.queue, executionIndex: 0)
        }
        precondition(self.renderGraph != nil, "GPUResourceLoader.initialise() has not been called.")
        
        assert(offset + count <= buffer.length)
        
        if buffer.storageMode == .shared || buffer.storageMode == .managed {
            buffer.withMutableContents(range: offset..<(offset + count)) {
                bytes($0, &$1)
            }
            return RenderGraphExecutionWaitToken(queue: self.renderGraph.queue, executionIndex: 0)
        } else {
            assert(buffer.storageMode == .private)
            
            let cacheMode = CPUCacheMode.writeCombined
            
            // NOTE: this happens outside of the queue so we don't block concurrent execution of uploads.
            let (stagingBuffer, stagingBufferOffset, allocationRange) = self.queue.sync { self.allocator(cacheMode: cacheMode) }.withBufferContents(byteCount: count, alignedTo: 256) { contents, writtenRange in
                bytes(contents, &writtenRange)
            }
            
            return self.queue.sync {
                self.renderGraph.addBlitCallbackPass(name: "uploadBytes(count: \(count), to: \(buffer), offset: \(offset))") { bce in
                    bce.copy(from: stagingBuffer, sourceOffset: stagingBufferOffset, to: buffer, destinationOffset: offset, size: count)
                }
                
                return self._flush(cacheMode: cacheMode, buffer: stagingBuffer, allocationRange: allocationRange)
            }
        }
    }
    
    @discardableResult
    public static func replaceTextureRegion(_ region: Region, mipmapLevel: Int, in texture: Texture, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) -> RenderGraphExecutionWaitToken {
        let rowCount = (texture.height >> mipmapLevel) / texture.descriptor.pixelFormat.rowsPerBlock
        return self.replaceTextureRegion(region, mipmapLevel: mipmapLevel, slice: 0, in: texture, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerRow * rowCount)
    }
    
    @discardableResult
    public static func replaceTextureRegion(_ region: Region, mipmapLevel: Int, slice: Int, in texture: Texture, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) -> RenderGraphExecutionWaitToken {
        if GPUResourceUploader.skipUpload {
            return RenderGraphExecutionWaitToken(queue: self.renderGraph.queue, executionIndex: 0)
        }
        precondition(self.renderGraph != nil, "GPUResourceLoader.initialise() has not been called.")
        
        if texture.storageMode == .shared || texture.storageMode == .managed {
            texture.replace(region: region, mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
            return RenderGraphExecutionWaitToken(queue: self.renderGraph.queue, executionIndex: 0)
        } else {
            assert(texture.storageMode == .private)
            
            let cacheMode = CPUCacheMode.writeCombined
            
            // NOTE: this happens outside of the queue so we don't block concurrent execution of uploads.
            let (stagingBuffer, stagingBufferOffset, allocationRange) = self.queue.sync { self.allocator(cacheMode: cacheMode) }.withBufferContents(byteCount: bytesPerImage, alignedTo: 256) { contents, _ in
                contents.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: bytesPerImage))
            }
            
            return self.queue.sync {
                self.renderGraph.addBlitCallbackPass(name: "replaceTextureRegion(\(region), mipmapLevel: \(mipmapLevel), slice: \(slice), in: \(texture), withBytes: \(bytes), bytesPerRow: \(bytesPerRow), bytesPerImage: \(bytesPerImage))") { bce in
                    bce.copy(from: stagingBuffer, sourceOffset: stagingBufferOffset, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: bytesPerImage, sourceSize: region.size, to: texture, destinationSlice: slice, destinationLevel: mipmapLevel, destinationOrigin: region.origin)
                }
                return self._flush(cacheMode: cacheMode, buffer: stagingBuffer, allocationRange: allocationRange)
            }
        }
    }
}

extension Range {
    fileprivate func contains(_ other: Range) -> Bool {
        return other.lowerBound >= self.lowerBound && other.upperBound <= self.upperBound
    }
}

extension GPUResourceUploader {
    fileprivate final class StagingBufferSubAllocator {
        private static let blockAlignment = 64
        private let queue = DispatchQueue(label: "StagingBufferSubAllocator Queue")
        
        let renderGraphQueue: Queue
        let capacity: Int
        let buffer: Buffer
        let bufferContents: UnsafeMutableRawPointer
        
        var freeRangeStart = 0
        var freeRangeEnd = -1
        
        let pendingCommands: RingBuffer<(command: UInt64, allocationRange: Range<Int>, tempBuffer: Buffer?)> = .init()
        
        public init(renderGraphQueue: Queue, stagingBufferLength: Int = 128 * 1024 * 1024, cacheMode: CPUCacheMode) {
            self.renderGraphQueue = renderGraphQueue
            self.capacity = stagingBufferLength
            self.buffer = Buffer(length: stagingBufferLength, storageMode: .shared, cacheMode: cacheMode, usage: .blitSource, flags: .persistent)
            self.bufferContents = RenderBackend.bufferContents(for: self.buffer, range: self.buffer.range)
        }
        
        deinit {
            self.buffer.dispose()
        }
        
        func didSubmit(buffer: Buffer, allocationRange: Range<Int>, submissionIndex: UInt64) {
            self.queue.sync {
                if buffer == self.buffer {
                    let index = self.pendingCommands.firstIndex(where: { $0.command == .max && $0.allocationRange == allocationRange })!
                    self.pendingCommands[index].command = submissionIndex
                } else {
                    // This is a buffer that was allocated specifically for this command.
                    let index = self.pendingCommands.firstIndex(where: { $0.command == .max && $0.tempBuffer == buffer })!
                    self.pendingCommands[index].command = submissionIndex
                    
                    DispatchQueue.global().async {
                        // Make sure the buffer gets disposed even if no more resource uploads are submitted.
                        RenderGraphExecutionWaitToken(queue: self.renderGraphQueue, executionIndex: submissionIndex).wait()
                        self.queue.async {
                            self.processCompletedCommands()
                        }
                    }
                }
            }
        }
        
        private func rangeIsInBounds(range: Range<Int>, limit: Int) -> Bool {
            if range.lowerBound > limit {
                return false
            }
            return limit >= range.upperBound // == limit - range.lowerBound >= range.count
        }
        
        private func findAllocation(byteCount: Int, alignedTo alignment: Int) -> Range<Int>? {
            dispatchPrecondition(condition: .onQueue(self.queue))
            self.processCompletedCommands()
            
            if self.freeRangeStart == self.freeRangeEnd {
                return nil // We're full.
            }
            
            var alignedPosition = self.freeRangeStart.roundedUpToMultipleOfPowerOfTwo(of: alignment)
            var allocationRange = alignedPosition..<(alignedPosition + byteCount)
            
            if self.freeRangeEnd < self.freeRangeStart {
                // The end of the free range is behind the cursor, so use the tail end of the buffer if we can.
                if !self.rangeIsInBounds(range: allocationRange, limit: self.capacity) {
                    // We have to go from the start of the buffer.
                    
                    if self.freeRangeEnd < 0 {
                        // There's no available space; freeRangeEnd being < 0 means that none of the previous allocations have been freed yet.
                        return nil
                    }
                    
                    alignedPosition = 0
                    allocationRange = 0..<byteCount
                    
                    if !self.rangeIsInBounds(range: allocationRange, limit: self.freeRangeEnd) {
                        return nil
                    }
                 
                }
            } else if !self.rangeIsInBounds(range: allocationRange, limit: self.freeRangeEnd) {
                return nil
            }
            
            self.freeRangeStart = allocationRange.upperBound
            self.pendingCommands.append((.max, allocationRange, nil)) // We don't know what command this is associated with yet, but we'll set that in didSubmit.
            
            return allocationRange
        }
        
        func withBufferContents(byteCount: Int, alignedTo alignment: Int, perform: (UnsafeMutableRawBufferPointer, inout Range<Int>) throws -> Void) rethrows -> (buffer: Buffer, offset: Int, allocationRange: Range<Int>) {
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
                
                self.queue.sync {
                    self.pendingCommands.append((.max, 0..<byteCount, buffer))
                }
                
                return (buffer, 0, 0..<buffer.length)
            }
            
            if byteCount == 0 {
                var range = 0..<0
                try perform(UnsafeMutableRawBufferPointer(start: nil, count: 0), &range)
                return (self.buffer, 0, 0..<0)
            }
            
            while true {
                if let bufferRange = self.queue.sync(execute: { self.findAllocation(byteCount: byteCount, alignedTo: alignment) }) {
                    var writtenRange = 0..<byteCount
                    try perform(UnsafeMutableRawBufferPointer(start: self.bufferContents.advanced(by: bufferRange.lowerBound), count: byteCount), &writtenRange)
                    if !writtenRange.isEmpty, self.buffer.storageMode != .shared {
                        RenderBackend.buffer(self.buffer, didModifyRange: (bufferRange.lowerBound + writtenRange.lowerBound)..<(bufferRange.lowerBound + writtenRange.lowerBound + writtenRange.count))
                    }
                    
                    return (self.buffer, bufferRange.lowerBound, bufferRange)
                }
            }
        }
        
        private func deallocate(range: Range<Int>) {
            if self.pendingCommands.allSatisfy({ $0.tempBuffer != nil }) {
                // If there are no pending commands, mark the entire staging buffer as being free.
                self.freeRangeStart = 0
                self.freeRangeEnd = -1
            } else {
                // Otherwise, move the free range's end forward to include the newly unused space.
                self.freeRangeEnd = range.upperBound
            }
        }
        
        private func processCompletedCommands() {
            dispatchPrecondition(condition: .onQueue(self.queue))
            while self.pendingCommands.first?.command ?? .max <= self.renderGraphQueue.lastCompletedCommand {
                let (_, range, tempBuffer) = self.pendingCommands.popFirst()!
                if let tempBuffer = tempBuffer {
                    tempBuffer.dispose()
                } else {
                    self.deallocate(range: range)
                }
            }
        }
    }
}
