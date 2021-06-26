//
//  RenderGraphContext.swift
//  
//
//  Created by Thomas Roughton on 21/06/20.
//

import SubstrateUtilities
import Foundation
import Dispatch

extension TaggedHeap.Tag {
    static var renderGraphResourceCommandArrayTag: Self {
        return 2807157891446559070
    }
}

final class RenderGraphContextImpl<Backend: SpecificRenderBackend>: _RenderGraphContext {
    public var accessSemaphore: DispatchSemaphore?
    
    let queue = DispatchQueue(label: "Render Graph Context Queue")
    
    let backend: Backend
    let resourceRegistry: Backend.TransientResourceRegistry?
    let commandGenerator: ResourceCommandGenerator<Backend>
    
    // var compactedResourceCommands = [CompactedResourceCommand<MetalCompactedResourceCommandType>]()
       
    var queueCommandBufferIndex: UInt64 = 0 // The last command buffer submitted
    let syncEvent: Backend.Event
       
    let commandQueue: Backend.QueueImpl
       
    public let transientRegistryIndex: Int
    var renderGraphQueue: Queue
    
    var compactedResourceCommands = [CompactedResourceCommand<Backend.CompactedResourceCommandType>]()
       
    let emptyFrameCompletionHandlerSemaphore = DispatchSemaphore(value: 1)
    var enqueuedEmptyFrameCompletionHandlers = [(queueCBIndex: UInt64, handler: (Double) -> Void)]()
    
    public init(backend: Backend, inflightFrameCount: Int, transientRegistryIndex: Int) {
        self.backend = backend
        self.renderGraphQueue = Queue()
        self.commandQueue = backend.makeQueue(renderGraphQueue: self.renderGraphQueue)
        self.transientRegistryIndex = transientRegistryIndex
        self.resourceRegistry = inflightFrameCount > 0 ? backend.makeTransientRegistry(index: transientRegistryIndex, inflightFrameCount: inflightFrameCount, queue: self.renderGraphQueue) : nil
        self.accessSemaphore = inflightFrameCount > 0 ? DispatchSemaphore(value: inflightFrameCount) : nil
        
        self.commandGenerator = ResourceCommandGenerator()
        self.syncEvent = backend.makeSyncEvent(for: self.renderGraphQueue)
    }
    
    deinit {
        backend.freeSyncEvent(for: self.renderGraphQueue)
        self.renderGraphQueue.dispose()
    }
    
    public func beginFrameResourceAccess() {
        self.backend.setActiveContext(self)
    }
    
    var resourceMap : FrameResourceMap<Backend> {
        return FrameResourceMap<Backend>(persistentRegistry: self.backend.resourceRegistry, transientRegistry: self.resourceRegistry)
    }

    func executeRenderGraph(passes: [RenderPassRecord], usedResources: Set<Resource>, dependencyTable: DependencyTable<Substrate.DependencyType>, completion: @escaping (Double) -> Void) {
        
        // Use separate command buffers for onscreen and offscreen work (Delivering Optimised Metal Apps and Games, WWDC 2019)
        self.resourceRegistry?.prepareFrame()
        
        defer {
            TaggedHeap.free(tag: .renderGraphResourceCommandArrayTag)
            
            self.resourceRegistry?.cycleFrames()
            
            self.commandGenerator.reset()
            self.compactedResourceCommands.removeAll(keepingCapacity: true)
            
            self.backend.setActiveContext(nil)
        }
        
        if passes.isEmpty {
            if self.renderGraphQueue.lastCompletedCommand >= self.renderGraphQueue.lastSubmittedCommand {
                completion(0.0)
                self.accessSemaphore?.signal()
            } else {
                // Enqueue the completion handler to run immediately
                self.emptyFrameCompletionHandlerSemaphore.withSemaphore {
                    self.enqueuedEmptyFrameCompletionHandlers.append((self.queueCommandBufferIndex, completion))
                }
            }
            return
        }
        
        var frameCommandInfo = FrameCommandInfo<Backend>(passes: passes, initialCommandBufferSignalValue: self.queueCommandBufferIndex + 1)
        self.commandGenerator.generateCommands(passes: passes, usedResources: usedResources, transientRegistry: self.resourceRegistry, backend: backend, frameCommandInfo: &frameCommandInfo)
        self.commandGenerator.executePreFrameCommands(context: self, frameCommandInfo: &frameCommandInfo)
        self.commandGenerator.commands.sort() // We do this here since executePreFrameCommands may have added to the commandGenerator commands.
        backend.compactResourceCommands(queue: self.renderGraphQueue, resourceMap: self.resourceMap, commandInfo: frameCommandInfo, commandGenerator: self.commandGenerator, into: &self.compactedResourceCommands)
        
        let lastCommandBufferIndex = frameCommandInfo.commandBufferCount - 1
        
        var commandBuffer : Backend.CommandBuffer? = nil
        
        var committedCommandBufferCount = 0
        
        var gpuStartTime: Double = 0.0
        
        let syncEvent = backend.syncEvent(for: self.renderGraphQueue)!
        
        func processCommandBuffer() {
            if let commandBuffer = commandBuffer {
                if let transientRegistry = resourceMap.transientRegistry {
                    commandBuffer.presentSwapchains(resourceRegistry: transientRegistry)
                }
                
                // Make sure that the sync event value is what we expect, so we don't update it past
                // the signal for another buffer before that buffer has completed.
                // We only need to do this if we haven't already waited in this command buffer for it.
                // if commandEncoderWaitEventValues[commandEncoderIndex] != self.queueCommandBufferIndex {
                //     commandBuffer.encodeWaitForEvent(self.syncEvent, value: self.queueCommandBufferIndex)
                // }
                // Then, signal our own completion.
                self.queueCommandBufferIndex += 1
                commandBuffer.signalEvent(syncEvent, value: self.queueCommandBufferIndex)
                
                let cbIndex = committedCommandBufferCount
                let queueCBIndex = self.queueCommandBufferIndex
                
                self.renderGraphQueue.lastSubmittedCommand = queueCBIndex
                self.renderGraphQueue.lastSubmissionTime = DispatchTime.now()
                
                commandBuffer.commit(onCompletion: { (commandBuffer) in
                    if let error = commandBuffer.error {
                        print("Error executing command buffer \(queueCBIndex): \(error)")
                    }
                    self.renderGraphQueue.lastCompletedCommand = queueCBIndex
                    self.renderGraphQueue.lastCompletionTime = DispatchTime.now()
                    
                    CommandEndActionManager.manager.didCompleteCommand(queueCBIndex, on: self.renderGraphQueue)
                    
                    if cbIndex == 0 {
                        gpuStartTime = commandBuffer.gpuStartTime
                    }
                    if cbIndex == lastCommandBufferIndex { // Only call completion for the last command buffer.
                        let gpuEndTime = commandBuffer.gpuEndTime
                        completion((gpuEndTime - gpuStartTime) * 1000.0)
                        self.accessSemaphore?.signal()
                        
                        self.queue.async {
                            self.backend.didCompleteCommand(queueCBIndex, queue: self.renderGraphQueue, context: self)
                        }
                        
                        self.emptyFrameCompletionHandlerSemaphore.withSemaphore {
                            // Notify any completion handlers that were enqueued for frames with no work.
                            while let (afterCBIndex, completionHandler) = self.enqueuedEmptyFrameCompletionHandlers.first {
                                if afterCBIndex > queueCBIndex { break }
                                
                                completionHandler(0.0)
                                self.accessSemaphore?.signal()
                                self.enqueuedEmptyFrameCompletionHandlers.removeFirst()
                            }
                        }
                    }
                })
                committedCommandBufferCount += 1
                
            }
            commandBuffer = nil
        }
        
        var waitedEvents = QueueCommandIndices(repeating: 0)
        
        for (i, encoderInfo) in frameCommandInfo.commandEncoders.enumerated() {
            let commandBufferIndex = encoderInfo.commandBufferIndex
            if commandBufferIndex != committedCommandBufferCount {
                processCommandBuffer()
            }
            
            if commandBuffer == nil {
                commandBuffer = self.commandQueue.makeCommandBuffer(commandInfo: frameCommandInfo,
                                                      resourceMap: resourceMap,
                                                      compactedResourceCommands: self.compactedResourceCommands)
            }
            
            let waitEventValues = encoderInfo.queueCommandWaitIndices
            for queue in QueueRegistry.allQueues {
                if waitedEvents[Int(queue.index)] < waitEventValues[Int(queue.index)],
                    waitEventValues[Int(queue.index)] > queue.lastCompletedCommand {
                    if let event = backend.syncEvent(for: queue) {
                        commandBuffer!.waitForEvent(event, value: waitEventValues[Int(queue.index)])
                    } else {
                        // It's not a queue known to this backend, so the best we can do is sleep and wait until the queue is completd.
                        queue.waitForCommandCompletion(waitEventValues[Int(queue.index)])
                    }
                }
            }
            waitedEvents = pointwiseMax(waitEventValues, waitedEvents)
            
            commandBuffer!.encodeCommands(encoderIndex: i)
        }
        
        processCommandBuffer()
        
        for passRecord in passes {
            passRecord.pass = nil // Release references to the RenderPasses.
        }
    }
}
