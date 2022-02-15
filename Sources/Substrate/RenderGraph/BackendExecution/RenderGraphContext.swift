//
//  RenderGraphContext.swift
//  
//
//  Created by Thomas Roughton on 21/06/20.
//

import SubstrateUtilities
import Foundation
import Dispatch
import Atomics

extension TaggedHeap.Tag {
    static var renderGraphResourceCommandArrayTag: Self {
        return 2807157891446559070
    }
}

actor RenderGraphContextImpl<Backend: SpecificRenderBackend>: _RenderGraphContext {
    let accessStream: AsyncStream<Void>? // Acts as a semaphore to prevent too many frames being submitted at once.
       
    let backend: Backend
    let resourceRegistry: Backend.TransientResourceRegistry?
    let commandGenerator: ResourceCommandGenerator<Backend>
    let activeContextLock = AsyncSpinLock()
    
    var queueCommandBufferIndex: UInt64 = 0 // The last command buffer submitted
    let syncEvent: Backend.Event
       
    let commandQueue: Backend.QueueImpl
       
    public let transientRegistryIndex: Int
    let renderGraphQueue: Queue
    
    var compactedResourceCommands = [CompactedResourceCommand<Backend.CompactedResourceCommandType>]()
       
    var enqueuedEmptyFrameCompletionHandlers = [(UInt64, @Sendable (RenderGraphExecutionResult) async -> Void)]()
    private nonisolated let accessStreamContinuation: AsyncStream<Void>.Continuation?
    
    public init(backend: Backend, inflightFrameCount: Int, transientRegistryIndex: Int) {
        self.backend = backend
        self.renderGraphQueue = Queue()
        self.commandQueue = backend.makeQueue(renderGraphQueue: self.renderGraphQueue)
        self.transientRegistryIndex = transientRegistryIndex
        self.resourceRegistry = inflightFrameCount > 0 ? backend.makeTransientRegistry(index: transientRegistryIndex, inflightFrameCount: inflightFrameCount, queue: self.renderGraphQueue) : nil
        
        if inflightFrameCount > 0 {
            var accessStreamContinuation: AsyncStream<Void>.Continuation? = nil
            let accessStream = AsyncStream<Void> { continuation in
                accessStreamContinuation = continuation
                for _ in 0..<inflightFrameCount {
                    continuation.yield()
                }
            }
            self.accessStream = accessStream
            self.accessStreamContinuation = accessStreamContinuation
        } else {
            self.accessStream = nil
            self.accessStreamContinuation = nil
        }
        
        self.commandGenerator = ResourceCommandGenerator()
        self.syncEvent = backend.makeSyncEvent(for: self.renderGraphQueue)
    }
    
    
    deinit {
        backend.freeSyncEvent(for: self.renderGraphQueue)
        self.renderGraphQueue.dispose()
    }
    
    func registerWindowTexture(for texture: Texture, swapchain: Any) async {
        guard let resourceRegistry = self.resourceRegistry else {
            print("Error: cannot associate a window texture with a no-transient-resources RenderGraph")
            return
        }

        await resourceRegistry.registerWindowTexture(for: texture, swapchain: swapchain)
    }
    
    nonisolated var resourceMap : FrameResourceMap<Backend> {
        return FrameResourceMap<Backend>(persistentRegistry: self.backend.resourceRegistry, transientRegistry: self.resourceRegistry)
    }
    
    func processEmptyFrameCompletionHandlers(afterSubmissionIndex: UInt64) async {
        // Notify any completion handlers that were enqueued for frames with no work.
        while let (afterCBIndex, completionHandler) = self.enqueuedEmptyFrameCompletionHandlers.first {
            if afterCBIndex > afterSubmissionIndex { break }
            await completionHandler(.init())
            self.accessStreamContinuation?.yield()
            self.enqueuedEmptyFrameCompletionHandlers.removeFirst()
        }
    }
    
    
    func submitCommandBuffer(_ commandBuffer: Backend.CommandBuffer, commandBufferIndex: Int, lastCommandBufferIndex: Int, syncEvent: Backend.Event, onCompletion: @Sendable @escaping (RenderGraphExecutionResult) async -> Void) async {
        // Make sure that the sync event value is what we expect, so we don't update it past
        // the signal for another buffer before that buffer has completed.
        // We only need to do this if we haven't already waited in this command buffer for it.
        // if commandEncoderWaitEventValues[commandEncoderIndex] != self.queueCommandBufferIndex {
        //     commandBuffer.encodeWaitForEvent(self.syncEvent, value: self.queueCommandBufferIndex)
        // }
        // Then, signal our own completion.
        self.queueCommandBufferIndex += 1
        commandBuffer.signalEvent(syncEvent, value: self.queueCommandBufferIndex)
        
        let queueCBIndex = self.queueCommandBufferIndex
        await self.processEmptyFrameCompletionHandlers(afterSubmissionIndex: queueCBIndex)
        
        let isFirst = commandBufferIndex == 0
        let isLast = commandBufferIndex == lastCommandBufferIndex
    
        let executionResult = RenderGraphExecutionResult()
        
        let continuation = DeferredContinuation()
        
        commandBuffer.commit { _ in
            continuation.resume()
        }
        
        self.renderGraphQueue.submitCommand(commandIndex: queueCBIndex) {
            await continuation.wait()
            
            if let error = commandBuffer.error {
                print("Error executing command buffer \(queueCBIndex): \(error)")
            }
            
            if isFirst {
                await executionResult.setGPUStartTime(to: commandBuffer.gpuStartTime)
            }
            if isLast { // Only call completion for the last command buffer.
                await executionResult.setGPUEndTime(to: commandBuffer.gpuEndTime)
                await onCompletion(executionResult)
            }
            
            await self.renderGraphQueue.didCompleteCommand(queueCBIndex)
            
            if isLast {
                CommandEndActionManager.didCompleteCommand(queueCBIndex, on: self.renderGraphQueue)
                self.backend.didCompleteCommand(queueCBIndex, queue: self.renderGraphQueue, context: self)
                self.accessStreamContinuation?.yield()
            }
        }
    }
    
//    @_specialize(kind: full, where Backend == MetalBackend)
//    @_specialize(kind: full, where Backend == VulkanBackend)
    func executeRenderGraph(_ executeFunc: @escaping () async -> (passes: [RenderPassRecord], usedResources: Set<Resource>), onCompletion: @Sendable @escaping (RenderGraphExecutionResult) async -> Void) async {
        if self.accessStream != nil {
            // Wait until we have a frame's ring buffers available.
            for await completedFrame in self.accessStream! {
                _ = completedFrame
                break
            }
        }
        
        await self.backend.reloadShaderLibraryIfNeeded()
        
        return await self.activeContextLock.withLock {
            return await Backend.activeContextTaskLocal.withValue(self) {
                let (passes, usedResources) = await executeFunc()
                
                // Use separate command buffers for onscreen and offscreen work (Delivering Optimised Metal Apps and Games, WWDC 2019)
                self.resourceRegistry?.prepareFrame()
                
                if passes.isEmpty {
                    if self.renderGraphQueue.lastCompletedCommand >= self.renderGraphQueue.lastSubmittedCommand {
                        self.accessStreamContinuation?.yield()
                        await onCompletion(RenderGraphExecutionResult())
                    } else {
                        self.enqueuedEmptyFrameCompletionHandlers.append((self.queueCommandBufferIndex, onCompletion))
                    }
                    return
                }
                
                var frameCommandInfo = FrameCommandInfo<Backend.RenderTargetDescriptor>(passes: passes, initialCommandBufferGlobalIndex: self.queueCommandBufferIndex + 1)
                self.commandGenerator.generateCommands(passes: passes, usedResources: usedResources, transientRegistry: self.resourceRegistry, backend: backend, frameCommandInfo: &frameCommandInfo)
                await self.commandGenerator.executePreFrameCommands(context: self, frameCommandInfo: &frameCommandInfo)
                
                await RenderGraph.signposter.withIntervalSignpost("Sort and Compact Resource Commands") {
                    self.commandGenerator.commands.sort() // We do this here since executePreFrameCommands may have added to the commandGenerator commands.
                    
                    var compactedResourceCommands = self.compactedResourceCommands // Re-use its storage
                    self.compactedResourceCommands = []
                    await backend.compactResourceCommands(queue: self.renderGraphQueue, resourceMap: self.resourceMap, commandInfo: frameCommandInfo, commandGenerator: self.commandGenerator, into: &compactedResourceCommands)
                    self.compactedResourceCommands = compactedResourceCommands
                }
                
                var commandBuffers = [Backend.CommandBuffer]()
                var waitedEvents = QueueCommandIndices(repeating: 0)
                
                for (i, encoderInfo) in frameCommandInfo.commandEncoders.enumerated() {
                    let commandBufferIndex = encoderInfo.commandBufferIndex
                    if commandBufferIndex != commandBuffers.endIndex - 1 {
                        if let transientRegistry = resourceMap.transientRegistry {
                            commandBuffers.last?.presentSwapchains(resourceRegistry: transientRegistry)
                        }
                        commandBuffers.append(self.commandQueue.makeCommandBuffer(commandInfo: frameCommandInfo,
                                                                                  resourceMap: resourceMap,
                                                                                  compactedResourceCommands: self.compactedResourceCommands))
                    }
                    
                    let waitEventValues = encoderInfo.queueCommandWaitIndices
                    for queue in QueueRegistry.allQueues {
                        if waitedEvents[Int(queue.index)] < waitEventValues[Int(queue.index)],
                            waitEventValues[Int(queue.index)] > queue.lastCompletedCommand {
                            if let event = backend.syncEvent(for: queue) {
                                commandBuffers.last!.waitForEvent(event, value: waitEventValues[Int(queue.index)])
                            } else {
                                // It's not a queue known to this backend, so the best we can do is sleep and wait until the queue is completd.
                                await queue.waitForCommandCompletion(waitEventValues[Int(queue.index)])
                            }
                        }
                    }
                    waitedEvents = pointwiseMax(waitEventValues, waitedEvents)
                    
                    await RenderGraph.signposter.withIntervalSignpost("Encode to Command Buffer", "Encode commands for command encoder \(i)") {
                        await commandBuffers.last!.encodeCommands(encoderIndex: i)
                    }
                }
                
                if let transientRegistry = resourceMap.transientRegistry {
                    commandBuffers.last?.presentSwapchains(resourceRegistry: transientRegistry)
                }
                
                for passRecord in passes {
                    passRecord.pass = nil // Release references to the RenderPasses.
                }
                
                TaggedHeap.free(tag: .renderGraphResourceCommandArrayTag)
                
                self.resourceRegistry?.cycleFrames()
                self.commandGenerator.reset()
                self.compactedResourceCommands.removeAll(keepingCapacity: true)
                
                let syncEvent = backend.syncEvent(for: self.renderGraphQueue)!
                for (i, commandBuffer) in commandBuffers.enumerated() {
                    await self.submitCommandBuffer(commandBuffer, commandBufferIndex: i, lastCommandBufferIndex: commandBuffers.count - 1, syncEvent: syncEvent, onCompletion: onCompletion)
                }
            }
        }
    }
}
