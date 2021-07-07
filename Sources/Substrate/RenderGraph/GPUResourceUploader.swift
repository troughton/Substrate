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
    
    private static func _flush(cacheMode: CPUCacheMode, buffer: Buffer, allocationRange: (lowerBound: Int, upperBound: Int)) -> RenderGraphExecutionWaitToken {
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
        
        var inUseRangeStart = 0
        var inUseRangeEnd = 0
        
        let pendingCommands: RingBuffer<(command: UInt64, allocationRange: (lowerBound: Int, upperBound: Int), tempBuffer: Buffer?)> = .init()
        
        public init(renderGraphQueue: Queue, stagingBufferLength: Int = 128 * 1024 * 1024, cacheMode: CPUCacheMode) {
            self.renderGraphQueue = renderGraphQueue
            self.capacity = stagingBufferLength
            self.buffer = Buffer(length: stagingBufferLength, storageMode: .managed, cacheMode: cacheMode, usage: .blitSource, flags: .persistent)
            self.bufferContents = RenderBackend.bufferContents(for: self.buffer, range: self.buffer.range)
        }
        
        deinit {
            self.buffer.dispose()
        }
        
        
        func didSubmit(buffer: Buffer, allocationRange: (lowerBound: Int, upperBound: Int), submissionIndex: UInt64) {
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
        
        func withBufferContents(byteCount: Int, alignedTo alignment: Int, perform: (UnsafeMutableRawBufferPointer, inout Range<Int>) throws -> Void) rethrows -> (buffer: Buffer, offset: Int, allocationRange: (lowerBound: Int, upperBound: Int)) {
            
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
                    self.pendingCommands.append((.max, (0, 0), buffer))
                }
                
                return (buffer, 0, (0, 0))
            }
            
            if byteCount == 0 {
                var range = 0..<0
                try perform(UnsafeMutableRawBufferPointer(start: nil, count: 0), &range)
                return (self.buffer, 0, (lowerBound: 0, upperBound: 0))
            }
            
            while true {
                if let (bufferRange, allocationRange) = self.queue.sync(execute: { () -> (Range<Int>, (lowerBound: Int, upperBound: Int))? in
                    self.processCompletedCommands()
                    
                    var alignedPosition = self.inUseRangeEnd.roundedUpToMultipleOfPowerOfTwo(of: alignment)
                    var allocationRange = alignedPosition..<(alignedPosition + byteCount)
                    
                    if allocationRange.endIndex > self.capacity {
                        alignedPosition = 0
                        allocationRange = alignedPosition..<(alignedPosition + byteCount) // 0..<byteCount
                    }
                    
                    if self.inUseRangeStart > self.inUseRangeEnd {
                        if (self.inUseRangeStart..<self.capacity).overlaps(allocationRange) ||
                            (0..<self.inUseRangeEnd).overlaps(allocationRange) {
                            return nil
                        }
                    } else {
                        if (self.inUseRangeStart..<self.inUseRangeEnd).overlaps(allocationRange) {
                            return nil
                        }
                    }
                    
                    let suballocatedRange = (self.inUseRangeEnd, allocationRange.endIndex)
                    self.inUseRangeEnd = allocationRange.endIndex
                    self.pendingCommands.append((.max, suballocatedRange, nil)) // We don't know what command this is associated with yet, but we'll set that in didSubmit.
                    
                    if self.inUseRangeEnd < self.inUseRangeStart {
                        precondition((0..<self.inUseRangeEnd).contains(allocationRange))
                    } else {
                        self.inUseRangeStart = min(self.inUseRangeStart, allocationRange.lowerBound)
                        precondition((self.inUseRangeStart..<self.inUseRangeEnd).contains(allocationRange))
                    }
                    
                    return (allocationRange, suballocatedRange)
                }) {
                    var writtenRange = 0..<byteCount
                    try perform(UnsafeMutableRawBufferPointer(start: self.bufferContents.advanced(by: bufferRange.lowerBound), count: byteCount), &writtenRange)
                    RenderBackend.buffer(self.buffer, didModifyRange: (bufferRange.lowerBound + writtenRange.lowerBound)..<(bufferRange.lowerBound + writtenRange.lowerBound + writtenRange.count))
                    
                    return (self.buffer, bufferRange.lowerBound, allocationRange)
                }
            }
        }
        
        private func processCompletedCommands() {
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
