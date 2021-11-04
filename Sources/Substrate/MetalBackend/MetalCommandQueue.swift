//
//  MetalCommandQueue.swift
//  
//
//  Created by Thomas Roughton on 2/08/20.
//


#if canImport(Metal)

import SubstrateUtilities
import Metal

final class MetalCommandQueue: BackendQueue {
    typealias Backend = MetalBackend
    
    let backend: MetalBackend
    let queue: MTLCommandQueue
    
    init(backend: MetalBackend, queue: MTLCommandQueue) {
        self.backend = backend
        self.queue = queue
    }
    
    func makeCommandBuffer(commandInfo: FrameCommandInfo<Backend.RenderTargetDescriptor>, resourceMap: FrameResourceMap<Backend>, compactedResourceCommands: [CompactedResourceCommand<Backend.CompactedResourceCommandType>]) -> MetalCommandBuffer {
        return MetalCommandBuffer(backend: self.backend, queue: self.queue, commandInfo: commandInfo, resourceMap: resourceMap, compactedResourceCommands: compactedResourceCommands)
    }
}

#endif // canImport(Metal)
