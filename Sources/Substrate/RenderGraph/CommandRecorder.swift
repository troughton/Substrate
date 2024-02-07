//
//  LazyRenderGraph.swift
//  RenderGraph
//
//  Created by Thomas Roughton on 16/12/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

import SubstrateUtilities
import Foundation

#if canImport(Metal)
import Metal
#endif

#if canImport(MetalPerformanceShaders)
import MetalPerformanceShaders
#endif

#if canImport(Vulkan)
import Vulkan
#endif

@usableFromInline final class ReferenceBox<T> {
    public var value : T
    
    public init(_ value: T) {
        self.value = value
    }
}

@usableFromInline
final class ComputePipelineDescriptorBox {
    @usableFromInline var pipelineDescriptor : ComputePipelineDescriptor
    @usableFromInline var threadGroupSizeIsMultipleOfThreadExecutionWidth = true
    
    @inlinable
    init(_ pipelineDescriptor: ComputePipelineDescriptor) {
        self.pipelineDescriptor = pipelineDescriptor
    }
}

extension ChunkArray where Element == (Resource, ResourceUsage) {
    @inlinable
    var pointerToLastUsage: UnsafeMutablePointer<ResourceUsage> {
        return UnsafeMutableRawPointer(self.pointerToLast).advanced(by: MemoryLayout<Resource>.stride).assumingMemoryBound(to: ResourceUsage.self)
    }
}
