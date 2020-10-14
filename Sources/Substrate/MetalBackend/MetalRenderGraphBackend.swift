//
//  MetalRenderGraph.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

#if canImport(Metal)

import Metal
import SubstrateUtilities
import CAtomics

enum MetalCompactedResourceCommandType {
    // These commands need to be executed during render pass execution and do not modify the MetalResourceRegistry.
    case useResources(UnsafeMutableBufferPointer<MTLResource>, usage: MTLResourceUsage, stages: MTLRenderStages)
    case resourceMemoryBarrier(resources: UnsafeMutableBufferPointer<MTLResource>, afterStages: MTLRenderStages, beforeStages: MTLRenderStages)
    case scopedMemoryBarrier(scope: MTLBarrierScope, afterStages: MTLRenderStages, beforeStages: MTLRenderStages)
    case updateFence(MetalFenceHandle, afterStages: MTLRenderStages)
    case waitForFence(MetalFenceHandle, beforeStages: MTLRenderStages)
}

struct UseResourceKey: Hashable {
    var stages: MTLRenderStages
    var usage: MTLResourceUsage
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(stages.rawValue)
        hasher.combine(usage.rawValue)
    }
    
    static func ==(lhs: UseResourceKey, rhs: UseResourceKey) -> Bool {
        return lhs.stages == rhs.stages && lhs.usage == rhs.usage
    }
}

struct MetalResidentResource: Hashable, Equatable {
    var resource: Unmanaged<MTLResource>
    var stages: MTLRenderStages
    var usage: MTLResourceUsage
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(resource.toOpaque())
        hasher.combine(stages.rawValue)
        hasher.combine(usage.rawValue)
    }
    
    static func ==(lhs: MetalResidentResource, rhs: MetalResidentResource) -> Bool {
        return lhs.resource.toOpaque() == rhs.resource.toOpaque() && lhs.stages == rhs.stages && lhs.usage == rhs.usage
    }
}

extension MTLRenderStages {
    var first: MTLRenderStages {
        if self.contains(.vertex) { return .vertex }
        return self
    }
    
    var last: MTLRenderStages {
        if self.contains(.fragment) { return .fragment }
        return self
    }
}

#endif // canImport(Metal)
