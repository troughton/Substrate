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
    let backend: Backend
    let resourceRegistry: Backend.TransientResourceRegistry?
    let commandGenerator: ResourceCommandGenerator<Backend>
    let taskStream: TaskStream
    
    var queueCommandBufferIndex: QueueCommandIndex = 0 // The last command buffer submitted
    let syncEvent: Backend.Event
       
    let commandQueue: Backend.QueueImpl
       
    public let transientRegistryIndex: Int
    let renderGraphQueue: Queue
    
    var compactedResourceCommands = [CompactedResourceCommand<Backend.CompactedResourceCommandType>]()
    
    var enqueuedEmptyFrameCompletionHandlers = [(UInt64, @Sendable (_ queueCommandRange: Range<UInt64>) async -> Void)]()
    
    let accessSemaphore: AsyncSemaphore?
    var needsWaitOnAccessSemaphore: Bool = true // This gets set to false if we've already waited on the semaphore for the next RenderGraph.
    
    public init(backend: Backend, inflightFrameCount: Int, transientRegistryIndex: Int) {
        self.backend = backend
        self.renderGraphQueue = Queue()
        self.commandQueue = backend.makeQueue(renderGraphQueue: self.renderGraphQueue)
        self.transientRegistryIndex = transientRegistryIndex
        self.resourceRegistry = inflightFrameCount > 0 ? backend.makeTransientRegistry(index: transientRegistryIndex, inflightFrameCount: inflightFrameCount, queue: self.renderGraphQueue) : nil
        
        if inflightFrameCount > 0 {
            self.accessSemaphore = AsyncSemaphore(count: inflightFrameCount)
        } else {
            self.accessSemaphore = nil
        }
        
        self.commandGenerator = ResourceCommandGenerator()
        self.syncEvent = backend.makeSyncEvent(for: self.renderGraphQueue)
        
        self.taskStream = TaskStream()
    }
                                             
                                             
    deinit {
        backend.freeSyncEvent(for: self.renderGraphQueue)
        self.renderGraphQueue.dispose()
    }
    
    public nonisolated var transientRegistry: (any BackendTransientResourceRegistry)? {
        self.resourceRegistry
    }
    
    public func acquireResourceAccess() async {
        if self.needsWaitOnAccessSemaphore {
            await self.accessSemaphore?.wait()
            self.needsWaitOnAccessSemaphore = false
        }
        self.resourceRegistry?.prepareFrame()
    }
    
    func registerWindowTexture(for texture: Texture, swapchain: Swapchain) async {
        guard let resourceRegistry = self.resourceRegistry else {
            print("Error: cannot associate a window texture with a no-transient-resources RenderGraph")
            return
        }

        await resourceRegistry.registerWindowTexture(for: texture, swapchain: swapchain)
    }
    
    @_unsafeInheritExecutor
    public nonisolated func withContext<T>(@_inheritActorContext @_implicitSelfCapture _ perform: @Sendable () async -> T) async -> T {
        return await self.taskStream.enqueueAndWait(perform)
    }
    
    public nonisolated func withContextAsync(@_inheritActorContext @_implicitSelfCapture _ perform: @escaping @Sendable () async -> Void) {
        return self.taskStream.enqueue(perform)
    }
    
    func processEmptyFrameCompletionHandlers(afterSubmissionIndex: UInt64) async {
        // Notify any completion handlers that were enqueued for frames with no work.
        while let (afterCBIndex, completionHandler) = self.enqueuedEmptyFrameCompletionHandlers.first {
            if afterCBIndex > afterSubmissionIndex { break }
            await completionHandler(afterCBIndex..<afterCBIndex)
            self.accessSemaphore?.signal()
            self.enqueuedEmptyFrameCompletionHandlers.removeFirst()
        }
    }
    
    func submitCommandBuffer(_ commandBuffer: Backend.CommandBuffer, isLast: Bool, syncEvent: Backend.Event, onCompletion: (@Sendable () async -> Void)? = nil) async {
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
        
        self.renderGraphQueue.submitCommand(commandIndex: queueCBIndex)
        commandBuffer.commit { commandBuffer in
            Task.detached {
                if let error = commandBuffer.error {
                    print("Error executing command buffer \(queueCBIndex): \(error)")
                }
                
                self.renderGraphQueue.setGPUStartTime(commandBuffer.gpuStartTime, for: queueCBIndex)
                self.renderGraphQueue.setGPUEndTime(commandBuffer.gpuEndTime, for: queueCBIndex)
                
                self.renderGraphQueue.didCompleteCommand(queueCBIndex, completionTime: .now())
                
                if isLast {
                    CommandEndActionManager.didCompleteCommand(queueCBIndex, on: self.renderGraphQueue)
                    self.backend.didCompleteCommand(queueCBIndex, queue: self.renderGraphQueue, context: self)
                    self.accessSemaphore?.signal()
                }
                await onCompletion?()
            }
        }
    }
    
//    @_specialize(kind: full, where Backend == MetalBackend)
//    @_specialize(kind: full, where Backend == VulkanBackend)
    func executeRenderGraph(_ renderGraph: RenderGraph, renderPasses: [RenderPassRecord],
                            waitingFor gpuQueueWaitIndices: QueueCommandIndices,
                            onSwapchainPresented: RenderGraph.SwapchainPresentedCallback? = nil,
                            onCompletion: @Sendable @escaping (_ queueCommandRange: Range<UInt64>) async -> Void) async -> RenderGraphExecutionWaitToken {
        return await self.taskStream.enqueueAndWait {
            await self.acquireResourceAccess()
            await self.backend.reloadShaderLibraryIfNeeded()
            
            defer {
                self.needsWaitOnAccessSemaphore = true
            }
            
            return await Backend.activeContextTaskLocal.withValue(self) {
                return await RenderGraph.$activeRenderGraph.withValue(renderGraph) {
                    let (cpuPasses, passes, _, usedResources) = await renderGraph.compile(renderPasses: renderPasses)
                    
                    // Use separate command buffers for onscreen and offscreen work (Delivering Optimised Metal Apps and Games, WWDC 2019)
                    
                    if passes.isEmpty {
                        for pass in cpuPasses {
                            await pass.execute()
                        }
                        
                        if self.renderGraphQueue.lastCompletedCommand >= self.renderGraphQueue.lastSubmittedCommand {
                            self.accessSemaphore?.signal()
                            self.needsWaitOnAccessSemaphore = true
                            await onCompletion(self.queueCommandBufferIndex..<self.queueCommandBufferIndex)
                        } else {
                            self.enqueuedEmptyFrameCompletionHandlers.append((self.queueCommandBufferIndex, onCompletion))
                        }
                        return RenderGraphExecutionWaitToken(queue: self.renderGraphQueue, executionIndex: 0)
                    }
                    
                    var frameCommandInfo = FrameCommandInfo<Backend.RenderTargetDescriptor>(passes: passes, initialCommandBufferGlobalIndex: self.queueCommandBufferIndex + 1)
                    self.commandGenerator.generateCommands(passes: passes, usedResources: usedResources, transientRegistry: self.resourceRegistry, backend: backend, frameCommandInfo: &frameCommandInfo)
                    await self.commandGenerator.executePreFrameCommands(context: self, frameCommandInfo: &frameCommandInfo)
                    
                    // We've now executed the pre-frame commands and materialised any resources we need, which means it's safe to run the CPU passes.
                    for pass in cpuPasses {
                        await pass.execute()
                    }
                    
                    await RenderGraph.signposter.withIntervalSignpost("Sort and Compact Resource Commands") {
                        self.commandGenerator.commands.sort() // We do this here since executePreFrameCommands may have added to the commandGenerator commands.
                        
                        var compactedResourceCommands = self.compactedResourceCommands // Re-use its storage
                        self.compactedResourceCommands = []
                        await backend.compactResourceCommands(queue: self.renderGraphQueue, commandInfo: frameCommandInfo, commandGenerator: self.commandGenerator, into: &compactedResourceCommands)
                        self.compactedResourceCommands = compactedResourceCommands
                    }
                    
                    self.commandGenerator.updateQueueWaitCommandIndices(frameCommandInfo: &frameCommandInfo, queue: self.renderGraphQueue)
                    
                    var commandBuffers = [Backend.CommandBuffer]()
                    commandBuffers.reserveCapacity(frameCommandInfo.commandBufferCount)
                    var waitedEvents = QueueCommandIndices(repeating: 0)
                    
                    for (i, encoderInfo) in frameCommandInfo.commandEncoders.enumerated() {
                        let commandBufferIndex = encoderInfo.commandBufferIndex
                        if commandBufferIndex != commandBuffers.endIndex - 1 {
                            if let transientRegistry = self.resourceRegistry {
                                commandBuffers.last?.presentSwapchains(resourceRegistry: transientRegistry, onPresented: onSwapchainPresented)
                            }
                            
                            if let lastCommandBuffer = commandBuffers.last {
                                await self.submitCommandBuffer(lastCommandBuffer, isLast: false, syncEvent: self.syncEvent)
                            }
                            commandBuffers.append(self.commandQueue.makeCommandBuffer(commandInfo: frameCommandInfo,
                                                                                      transientRegistry: self.resourceRegistry,
                                                                                      compactedResourceCommands: self.compactedResourceCommands))
                        }
                        
                        let waitEventValues = pointwiseMax(encoderInfo.queueCommandWaitIndices, gpuQueueWaitIndices)
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
                    
                    if let transientRegistry = self.resourceRegistry {
                        commandBuffers.last?.presentSwapchains(resourceRegistry: transientRegistry, onPresented: onSwapchainPresented)
                    }
                    
                    for passRecord in passes {
                        passRecord.pass = nil // Release references to the RenderPasses.
                    }
                    
                    TaggedHeap.free(tag: .renderGraphResourceCommandArrayTag)
                    
                    self.resourceRegistry?.cycleFrames()
                    self.commandGenerator.reset()
                    self.compactedResourceCommands.removeAll(keepingCapacity: true)

                    let commandBufferRange = frameCommandInfo.baseCommandBufferGlobalIndex..<(frameCommandInfo.baseCommandBufferGlobalIndex + UInt64(frameCommandInfo.commandBufferCount))

                    if let lastCommandBuffer = commandBuffers.last {
                        await self.submitCommandBuffer(lastCommandBuffer, isLast: true, syncEvent: self.syncEvent, onCompletion: {
                            await onCompletion(commandBufferRange)
                        })
                    }
                    return RenderGraphExecutionWaitToken(queue: self.renderGraphQueue, executionIndex: self.queueCommandBufferIndex)
                }
            }
        }
    }
}
