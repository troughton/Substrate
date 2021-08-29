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

@usableFromInline
final class ExternalCommandBox {
    @usableFromInline let command: (UnsafeRawPointer) -> Void
    
    @inlinable
    init(command: @escaping (UnsafeRawPointer) -> Void) {
        self.command = command
    }
}


// We're skipping management functions here (fences, most resource synchronisation etc.) since they
// should be taken care of automatically by the frame graph/resource transitions.
//
// Payload pointees must be exclusively value types (or an unmanaged reference type).
// We're also only allowing a 64 bit payload, since RenderGraphCommand will be sized to fit
// its biggest member (so if you add a struct...)
//
@usableFromInline
enum RenderGraphCommand {
    
    // General
    
    case setLabel(UnsafePointer<CChar>)
    case pushDebugGroup(UnsafePointer<CChar>)
    case popDebugGroup
    case insertDebugSignpost(UnsafePointer<CChar>)
    
    public typealias SetBytesArgs = (bindingPath: ResourceBindingPath, bytes: UnsafeRawPointer, length: UInt32)
    case setBytes(UnsafePointer<SetBytesArgs>)
    
    public typealias SetBufferArgs = (bindingPath: ResourceBindingPath, buffer: Buffer, offset: UInt32, hasDynamicOffset: Bool)
    case setBuffer(UnsafePointer<SetBufferArgs>)
    
    public typealias SetBufferOffsetArgs = (bindingPath: ResourceBindingPath, buffer: Buffer?, offset: UInt32)
    case setBufferOffset(UnsafePointer<SetBufferOffsetArgs>)
    
    public typealias SetTextureArgs = (bindingPath: ResourceBindingPath, texture: Texture)
    case setTexture(UnsafePointer<SetTextureArgs>)
    
    public typealias SetAccelerationStructureArgs = (bindingPath: ResourceBindingPath, structure: AccelerationStructure)
    case setAccelerationStructure(UnsafePointer<SetAccelerationStructureArgs>)
    
    public typealias SetVisibleFunctionTableArgs = (bindingPath: ResourceBindingPath, table: VisibleFunctionTable)
    case setVisibleFunctionTable(UnsafePointer<SetVisibleFunctionTableArgs>)
    
    public typealias SetIntersectionFunctionTableArgs = (bindingPath: ResourceBindingPath, table: IntersectionFunctionTable)
    case setIntersectionFunctionTable(UnsafePointer<SetIntersectionFunctionTableArgs>)
    
    public typealias SetSamplerStateArgs = (bindingPath: ResourceBindingPath, descriptor: SamplerDescriptor)
    case setSamplerState(UnsafePointer<SetSamplerStateArgs>)
    
    public typealias SetArgumentBufferArgs = (bindingPath: ResourceBindingPath, argumentBuffer: ArgumentBuffer)
    case setArgumentBuffer(UnsafePointer<SetArgumentBufferArgs>)
    
    public typealias SetArgumentBufferArrayArgs = (bindingPath: ResourceBindingPath, argumentBuffer: ArgumentBufferArray, isBound: Bool)
    case setArgumentBufferArray(UnsafePointer<SetArgumentBufferArrayArgs>)
    
    // Render
    
    case clearRenderTargets
    
    public typealias SetVertexBufferArgs = (buffer: Buffer?, offset: UInt32, index: UInt32)
    case setVertexBuffer(UnsafePointer<SetVertexBufferArgs>)
    
    case setVertexBufferOffset(offset: UInt32, index: UInt32)
    
    case setRenderPipelineDescriptor(Unmanaged<ReferenceBox<RenderPipelineDescriptor>>)
    
    case setRenderPipelineState(Unmanaged<RenderPipelineState>)
    
    public typealias DrawPrimitivesArgs = (primitiveType: PrimitiveType, vertexStart: UInt32, vertexCount: UInt32, instanceCount: UInt32, baseInstance: UInt32)
    case drawPrimitives(UnsafePointer<DrawPrimitivesArgs>)
    
    public typealias DrawIndexedPrimitivesArgs = (primitiveType: PrimitiveType, indexCount: UInt32, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: UInt32, instanceCount: UInt32, baseVertex: Int32, baseInstance: UInt32)
    case drawIndexedPrimitives(UnsafePointer<DrawIndexedPrimitivesArgs>)
    
    case setViewport(UnsafePointer<Viewport>)
    
    case setFrontFacing(Winding)
    
    case setCullMode(CullMode)
    
    case setTriangleFillMode(TriangleFillMode)
    
    case setDepthStencilDescriptor(Unmanaged<ReferenceBox<DepthStencilDescriptor>>)
    
    case setScissorRect(UnsafePointer<ScissorRect>)
    
    case setDepthClipMode(DepthClipMode)
    
    public typealias SetDepthBiasArgs = (depthBias: Float, slopeScale: Float, clamp: Float)
    case setDepthBias(UnsafePointer<SetDepthBiasArgs>)
    
    case setStencilReferenceValue(UInt32)
    
    case setStencilReferenceValues(front: UInt32, back: UInt32)
    
    
    // Compute
    
    public typealias DispatchThreadsArgs = (threads: Size, threadsPerThreadgroup: Size)
    case dispatchThreads(UnsafePointer<DispatchThreadsArgs>)
    
    public typealias DispatchThreadgroupsArgs = (threadgroupsPerGrid: Size, threadsPerThreadgroup: Size)
    case dispatchThreadgroups(UnsafePointer<DispatchThreadgroupsArgs>)
    
    public typealias DispatchThreadgroupsIndirectArgs = (indirectBuffer: Buffer, indirectBufferOffset: UInt32, threadsPerThreadgroup: Size)
    case dispatchThreadgroupsIndirect(UnsafePointer<DispatchThreadgroupsIndirectArgs>)
    
    case setComputePipelineDescriptor(Unmanaged<ComputePipelineDescriptorBox>)
    
    case setComputePipelineState(Unmanaged<ComputePipelineState>)
    
    case setStageInRegion(UnsafePointer<Region>)
    
    case setThreadgroupMemoryLength(length: UInt32, index: UInt32)
    
    
    // Blit
    
    public typealias CopyBufferToTextureArgs = (sourceBuffer: Buffer, sourceOffset: UInt32, sourceBytesPerRow: UInt32, sourceBytesPerImage: UInt32, sourceSize: Size, destinationTexture: Texture, destinationSlice: UInt32, destinationLevel: UInt32, destinationOrigin: Origin, options: BlitOption)
    case copyBufferToTexture(UnsafePointer<CopyBufferToTextureArgs>)
    
    public typealias CopyBufferToBufferArgs = (sourceBuffer: Buffer, sourceOffset: UInt32, destinationBuffer: Buffer, destinationOffset: UInt32, size: UInt32)
    case copyBufferToBuffer(UnsafePointer<CopyBufferToBufferArgs>)
    
    public typealias CopyTextureToBufferArgs = (sourceTexture: Texture, sourceSlice: UInt32, sourceLevel: UInt32, sourceOrigin: Origin, sourceSize: Size, destinationBuffer: Buffer, destinationOffset: UInt32, destinationBytesPerRow: UInt32, destinationBytesPerImage: UInt32, options: BlitOption)
    case copyTextureToBuffer(UnsafePointer<CopyTextureToBufferArgs>)
    
    public typealias CopyTextureToTextureArgs = (sourceTexture: Texture, sourceSlice: UInt32, sourceLevel: UInt32, sourceOrigin: Origin, sourceSize: Size, destinationTexture: Texture, destinationSlice: UInt32, destinationLevel: UInt32, destinationOrigin: Origin)
    case copyTextureToTexture(UnsafePointer<CopyTextureToTextureArgs>)
    
    
    public typealias BlitTextureToTextureArgs = (sourceTexture: Texture, sourceSlice: UInt32, sourceLevel: UInt32, sourceOrigin: Origin, sourceSize: Size, destinationTexture: Texture, destinationSlice: UInt32, destinationLevel: UInt32, destinationOrigin: Origin, destinationSize: Size, filter: SamplerMinMagFilter)
    case blitTextureToTexture(UnsafePointer<BlitTextureToTextureArgs>)
    
    public typealias FillBufferArgs = (buffer: Buffer, range: Range<Int>, value: UInt8)
    case fillBuffer(UnsafePointer<FillBufferArgs>)
    
    case generateMipmaps(Texture)
    
    case synchroniseTexture(Texture)
    
    public typealias SynchroniseTextureArgs = (texture: Texture, slice: UInt32, level: UInt32)
    case synchroniseTextureSlice(UnsafePointer<SynchroniseTextureArgs>)
    
    case synchroniseBuffer(Buffer)
    
    // External:
    
    case encodeExternalCommand(Unmanaged<ExternalCommandBox>)
    
    #if canImport(MetalPerformanceShaders)
    
    @available(OSX 10.14, *)
    public typealias EncodeRayIntersectionArgs = (intersector: Unmanaged<MPSRayIntersector>, intersectionType: MPSIntersectionType, rayBuffer: Buffer, rayBufferOffset: Int, intersectionBuffer: Buffer, intersectionBufferOffset: Int, rayCount: Int, accelerationStructure: Unmanaged<MPSAccelerationStructure>)
    @available(OSX 10.14, *)
    case encodeRayIntersection(UnsafePointer<EncodeRayIntersectionArgs>)
    
    @available(OSX 10.14, *)
    public typealias EncodeRayIntersectionRayCountBufferArgs = (intersector: Unmanaged<MPSRayIntersector>, intersectionType: MPSIntersectionType, rayBuffer: Buffer, rayBufferOffset: Int, intersectionBuffer: Buffer, intersectionBufferOffset: Int, rayCountBuffer: Buffer, rayCountBufferOffset: Int, accelerationStructure: Unmanaged<MPSAccelerationStructure>)
    @available(OSX 10.14, *)
    case encodeRayIntersectionRayCountBuffer(UnsafePointer<EncodeRayIntersectionRayCountBufferArgs>)
    
    #endif
    
    // Acceleration Structure:
    
    public typealias BuildAccelerationStructureArgs = (structure: AccelerationStructure, descriptor: AccelerationStructureDescriptor, scratchBuffer: Buffer, scratchBufferOffset: Int)

    case buildAccelerationStructure(UnsafePointer<BuildAccelerationStructureArgs>)

    public typealias RefitAccelerationStructureArgs = (source: AccelerationStructure, descriptor: AccelerationStructureDescriptor, destination: AccelerationStructure?, scratchBuffer: Buffer, scratchBufferOffset: Int)
    case refitAccelerationStructure(UnsafePointer<RefitAccelerationStructureArgs>)

    public typealias CopyAccelerationStructureArgs = (source: AccelerationStructure, destination: AccelerationStructure)
    case copyAccelerationStructure(UnsafePointer<CopyAccelerationStructureArgs>)
    
    public typealias WriteCompactedAccelerationStructureSizeArgs = (structure: AccelerationStructure, toBuffer: Buffer, bufferOffset: Int)
    case writeCompactedAccelerationStructureSize(UnsafePointer<WriteCompactedAccelerationStructureSizeArgs>)
    
    case copyAndCompactAccelerationStructure(UnsafePointer<CopyAccelerationStructureArgs>)
    
    var isDrawCommand: Bool {
        switch self {
        case .clearRenderTargets, .drawPrimitives, .drawIndexedPrimitives:
            return true
        default:
            return false
        }
    }
}

extension ChunkArray where Element == (Resource, ResourceUsage) {
    @inlinable
    var pointerToLastUsage: UnsafeMutablePointer<ResourceUsage> {
        return UnsafeMutableRawPointer(self.pointerToLast).advanced(by: MemoryLayout<Resource>.stride).assumingMemoryBound(to: ResourceUsage.self)
    }
}

// Lifetime: one render pass.
@usableFromInline
final class RenderGraphCommandRecorder {
    @usableFromInline let renderGraphTransientRegistryIndex: Int
    @usableFromInline let activeRenderGraphMask: ActiveRenderGraphMask
    @usableFromInline let renderPassScratchAllocator : ThreadLocalTagAllocator
    @usableFromInline let resourceUsageAllocator : TagAllocator
    @usableFromInline var commands : ChunkArray<RenderGraphCommand> // Lifetime: RenderGraph compilation (copied to another array for the backend).
    @usableFromInline var dataAllocator : TagAllocator // Lifetime: RenderGraph execution.
    @usableFromInline var unmanagedReferences : ChunkArray<Unmanaged<AnyObject>> // Lifetime: RenderGraph execution.
    @usableFromInline var readResources : HashSet<Resource>
    @usableFromInline var writtenResources : HashSet<Resource>
    
    @usableFromInline var resourceUsages = ChunkArray<(Resource, ResourceUsage)>()
    
    init(renderGraphTransientRegistryIndex: Int, renderGraphQueue: Queue, renderPassScratchAllocator: ThreadLocalTagAllocator, renderGraphExecutionAllocator: TagAllocator, resourceUsageAllocator: TagAllocator) {
        assert(_isPOD(RenderGraphCommand.self))
        self.renderGraphTransientRegistryIndex = renderGraphTransientRegistryIndex
        self.activeRenderGraphMask = 1 << renderGraphQueue.index
        self.commands = ChunkArray() // (allocator: AllocatorType(renderGraphExecutionAllocator), initialCapacity: 64)
        self.renderPassScratchAllocator = renderPassScratchAllocator
        self.resourceUsageAllocator = resourceUsageAllocator
        self.dataAllocator = renderGraphExecutionAllocator
        self.readResources = .init(allocator: .tag(renderGraphExecutionAllocator))
        self.writtenResources = .init(allocator: .tag(renderGraphExecutionAllocator))
        self.unmanagedReferences = .init()
    }
    
    @inlinable
    public var nextCommandIndex : Int {
        return self.commands.count
    }
    
    @inlinable
    public func copyData<T>(_ data: T) -> UnsafePointer<T> {
        let result = self.dataAllocator.dynamicThreadView.allocate(capacity: 1) as UnsafeMutablePointer<T>
        result.initialize(to: data)
        return UnsafePointer(result)
    }
    
    @inlinable
    public func record<T>(_ commandGenerator: (UnsafePointer<T>) -> RenderGraphCommand, _ data: T) {
        let command = commandGenerator(copyData(data))
        self.commands.append(command, allocator: .tag(self.dataAllocator))
    }
    
    @inlinable
    public func record(_ command: RenderGraphCommand) {
        self.commands.append(command, allocator: .tag(self.dataAllocator))
    }
    
    @inlinable
    public func record(_ commandGenerator: (UnsafePointer<CChar>) -> RenderGraphCommand, _ string: String) {
        let cStringAddress = string.withCString { label -> UnsafePointer<CChar> in
            let numChars = strlen(label)
            let destination : UnsafeMutablePointer<CChar> = self.dataAllocator.dynamicThreadView.allocate(capacity: numChars + 1)
            destination.initialize(from: label, count: numChars)
            destination[numChars] = 0
            return UnsafePointer(destination)
        }
        
        let command = commandGenerator(cStringAddress)
        self.commands.append(command, allocator: .tag(self.dataAllocator))
    }
    
    @discardableResult
    @inlinable
    public func copyBytes(_ bytes: UnsafeRawPointer, length: Int) -> UnsafeRawPointer {
        let newBytes = self.dataAllocator.dynamicThreadView.allocate(bytes: length, alignment: 16)
        newBytes.copyMemory(from: bytes, byteCount: length)
        return UnsafeRawPointer(newBytes)
    }
    
    @inlinable
    public func setLabel(_ label: String) {
        self.record(RenderGraphCommand.setLabel, label)
    }
    
    @inlinable
    public func pushDebugGroup(_ string: String) {
        self.record(RenderGraphCommand.pushDebugGroup, string)
    }
    
    @inlinable
    public func insertDebugSignpost(_ string: String) {
        self.record(RenderGraphCommand.insertDebugSignpost, string)
    }
    
    func addUnmanagedReference<T>(_ item: Unmanaged<T>) {
        self.unmanagedReferences.append(Unmanaged<AnyObject>.fromOpaque(item.toOpaque()), allocator: .tag(self.dataAllocator))
    }
    
    func resourceUsagePointers<C : CommandEncoder>(`for` specificResource: Resource, encoder: C, usageType: ResourceUsageType, stages: RenderStages, activeRange: ActiveResourceRange, isIndirectlyBound: Bool, firstCommandOffset: Int) -> ResourceUsagePointerList {
        let resource = specificResource.resourceForUsageTracking
        let activeRange = specificResource == resource ? activeRange : .fullResource
        
        assert(encoder.renderPass.writtenResources.isEmpty || encoder.renderPass.writtenResources.contains(where: { $0.handle == resource.handle }) || encoder.renderPass.readResources.contains(where: { $0.handle == resource.handle }), "Resource \(resource.handle) used but not declared.")
        
        precondition(resource.isValid, "Resource \(resource) is invalid; it may be being used in a frame after it was created if it's a transient resource, or else may have been disposed if it's a persistent resource.")
        assert(resource._usesPersistentRegistry || resource.transientRegistryIndex == self.renderGraphTransientRegistryIndex, "Transient resource \(resource) is being used on a RenderGraph other than the one it was created on.")
        
        assert(resource.type != .argumentBuffer || !usageType.isWrite, "Read-write argument buffers are currently unsupported.")
        assert(!usageType.isWrite || !resource.flags.contains(.immutableOnceInitialised) || !resource.stateFlags.contains(.initialised), "immutableOnceInitialised resource \(resource) is being written to after it has been initialised.")
        
        if resource._usesPersistentRegistry {
            resource.markAsUsed(activeRenderGraphMask: self.activeRenderGraphMask)
            if let textureUsage = Texture(resource)?.descriptor.usageHint {
                if usageType == .read {
                    assert(textureUsage.contains(.shaderRead))
                }
                if usageType.isRenderTarget {
                    assert(textureUsage.contains(.renderTarget))
                }
                if usageType == .write || usageType == .readWrite {
                    assert(textureUsage.contains(.shaderWrite))
                }
                if usageType == .blitSource {
                    assert(textureUsage.contains(.blitSource))
                }
                if usageType == .blitDestination {
                    assert(textureUsage.contains(.blitDestination))
                }
            } else if let bufferUsage = Buffer(resource)?.descriptor.usageHint {
                if usageType == .read {
                    assert(bufferUsage.contains(.shaderRead))
                }
                if usageType == .write || usageType == .readWrite {
                    assert(bufferUsage.contains(.shaderWrite))
                }
                if usageType == .blitSource {
                    assert(bufferUsage.contains(.blitSource))
                }
                if usageType == .blitDestination {
                    assert(bufferUsage.contains(.blitDestination))
                }
                if usageType == .vertexBuffer {
                    assert(bufferUsage.contains(.vertexBuffer))
                }
                if usageType == .indexBuffer {
                    assert(bufferUsage.contains(.indexBuffer))
                }
            }
        }
        
        if usageType.isRead {
            self.readResources.insert(resource)
        }
        if usageType.isWrite {
            self.writtenResources.insert(resource)
        }
        
        let usage = ResourceUsage(resource: resource, type: usageType, stages: stages, activeRange: activeRange, isIndirectlyBound: isIndirectlyBound, firstCommandOffset: firstCommandOffset, renderPass: encoder.passRecord)
        self.resourceUsages.append((specificResource, usage), allocator: .tag(resourceUsageAllocator))
        
        let usagePointer = self.resourceUsages.pointerToLastUsage
        
        if #available(macOS 11.0, iOS 14.0, *) {
            var subresourcePointers: [ResourceUsagePointer] = []
            if let accelerationStructureDescriptor = AccelerationStructure(specificResource)?.descriptor {
                subresourcePointers = self.resourceUsagePointers(for: accelerationStructureDescriptor, commandIndex: firstCommandOffset, stages: stages, encoder: encoder)
               
            } else if let intersectionFunctionTable = IntersectionFunctionTable(specificResource) {
                subresourcePointers = self.resourceUsagePointers(for: intersectionFunctionTable.descriptor, commandIndex: firstCommandOffset, stages: stages, encoder: encoder)
            }
            if !subresourcePointers.isEmpty {
                let subresourceList = resourceUsageAllocator.dynamicThreadView.allocate(type: ResourceUsagePointer.self, capacity: 1 + subresourcePointers.count)
                subresourceList.initialize(to: usagePointer)
                for i in 0..<subresourcePointers.count {
                    subresourceList.advanced(by: i + 1).initialize(to: subresourcePointers[i])
                }
                return .init(usagePointers: UnsafeMutableBufferPointer<ResourceUsagePointer>(start: subresourceList, count: 1 + subresourcePointers.count))
            }
        }
        return .init(usagePointer: usagePointer)
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    func resourceUsagePointers<C : CommandEncoder>(`for` resource: ArgumentBuffer, encoder: C, usageType: ResourceUsageType, stages: RenderStages, firstCommandOffset: Int) -> ResourceUsagePointerList {
        return self.resourceUsagePointers(for: Resource(resource), encoder: encoder, usageType: usageType, stages: stages, activeRange: .fullResource, isIndirectlyBound: false, firstCommandOffset: firstCommandOffset)
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    func resourceUsagePointers<C : CommandEncoder>(`for` resource: Buffer, bufferRange: Range<Int>, encoder: C, usageType: ResourceUsageType, stages: RenderStages, isIndirectlyBound: Bool, firstCommandOffset: Int) -> ResourceUsagePointerList {
        return self.resourceUsagePointers(for: Resource(resource), encoder: encoder, usageType: usageType, stages: stages, activeRange: .buffer(bufferRange), isIndirectlyBound: isIndirectlyBound, firstCommandOffset: firstCommandOffset)
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    func resourceUsagePointers<C : CommandEncoder>(`for` resource: Texture, slice: Int?, level: Int?, encoder: C, usageType: ResourceUsageType, stages: RenderStages, isIndirectlyBound: Bool, firstCommandOffset: Int) -> ResourceUsagePointerList {
        var subresourceMask = SubresourceMask()
        if let slice = slice, let level = level {
            subresourceMask.clear(subresourceCount: resource.descriptor.subresourceCount, allocator: .tag(self.dataAllocator))
            subresourceMask[slice: slice, level: level, descriptor: resource.descriptor, allocator: .tag(self.dataAllocator)] = true
        } else {
            assert(slice == nil && level == nil)
        }
        
        return self.resourceUsagePointers(for: Resource(resource), encoder: encoder, usageType: usageType, stages: stages, activeRange: .texture(subresourceMask), isIndirectlyBound: isIndirectlyBound, firstCommandOffset: firstCommandOffset)
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    @available(macOS 11.0, iOS 14.0, *)
    func resourceUsagePointers<C : CommandEncoder>(`for` resource: AccelerationStructure, encoder: C, usageType: ResourceUsageType, stages: RenderStages, isIndirectlyBound: Bool, firstCommandOffset: Int) -> ResourceUsagePointerList {
        return self.resourceUsagePointers(for: Resource(resource), encoder: encoder, usageType: usageType, stages: stages, activeRange: .fullResource, isIndirectlyBound: isIndirectlyBound, firstCommandOffset: firstCommandOffset)
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    func addResourceUsage<C : CommandEncoder>(`for` resource: ArgumentBuffer, commandIndex: Int, encoder: C, usageType: ResourceUsageType, stages: RenderStages) {
        let _ = self.resourceUsagePointers(for: resource, encoder: encoder, usageType: usageType, stages: stages, firstCommandOffset: commandIndex)
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    func addResourceUsage<C : CommandEncoder>(`for` resource: Buffer, bufferRange: Range<Int>, commandIndex: Int, encoder: C, usageType: ResourceUsageType, stages: RenderStages, isIndirectlyBound: Bool) {
        let _ = self.resourceUsagePointers(for: resource, bufferRange: bufferRange, encoder: encoder, usageType: usageType, stages: stages, isIndirectlyBound: isIndirectlyBound, firstCommandOffset: commandIndex)
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    func addResourceUsage<C : CommandEncoder>(`for` resource: Texture, slice: Int?, level: Int?, commandIndex: Int, encoder: C, usageType: ResourceUsageType, stages: RenderStages, isIndirectlyBound: Bool) {
        let _ = self.resourceUsagePointers(for: resource, slice: slice, level: level, encoder: encoder, usageType: usageType, stages: stages, isIndirectlyBound: isIndirectlyBound, firstCommandOffset: commandIndex)
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    @available(macOS 11.0, iOS 14.0, *)
    func addResourceUsage<C : CommandEncoder>(`for` resource: AccelerationStructure, commandIndex: Int, encoder: C, usageType: ResourceUsageType, stages: RenderStages, isIndirectlyBound: Bool) {
        let _ = self.resourceUsagePointers(for: resource, encoder: encoder, usageType: usageType, stages: stages, isIndirectlyBound: isIndirectlyBound, firstCommandOffset: commandIndex)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    fileprivate func resourceUsagePointers<C: CommandEncoder>(for descriptor: AccelerationStructureDescriptor, commandIndex: Int, stages: RenderStages, encoder: C) -> [ResourceUsagePointer] {
        var usagePointers = [ResourceUsagePointer]()
        switch descriptor.type {
        case .bottomLevelPrimitive(let primitiveDescriptors):
            for descriptor in primitiveDescriptors {
                switch descriptor.geometry {
                case .boundingBox(let boundingBoxDescriptor):
                    usagePointers.append(
                        self.resourceUsagePointers(for: boundingBoxDescriptor.boundingBoxBuffer,
                                                      bufferRange: boundingBoxDescriptor.boundingBoxBufferOffset..<(boundingBoxDescriptor.boundingBoxBufferOffset + boundingBoxDescriptor.boundingBoxCount * boundingBoxDescriptor.boundingBoxStride),
                                                      encoder: encoder, usageType: .read, stages: stages, isIndirectlyBound: true, firstCommandOffset: commandIndex).first!
                    )
                case .triangle(let triangleDescriptor):
                    usagePointers.append(
                    self.resourceUsagePointers(for: triangleDescriptor.vertexBuffer,
                                          bufferRange: triangleDescriptor.vertexBufferOffset..<min(triangleDescriptor.vertexBufferOffset + 3 * triangleDescriptor.vertexStride * triangleDescriptor.triangleCount, triangleDescriptor.vertexBuffer.length),
                                                  encoder: encoder, usageType: .vertexBuffer, stages: stages, isIndirectlyBound: true, firstCommandOffset: commandIndex).first!
                    )
                    if let indexBuffer = triangleDescriptor.indexBuffer {
                        let bytesPerIndex = triangleDescriptor.indexType == .uint16 ? MemoryLayout<UInt16>.stride : MemoryLayout<UInt32>.stride
                        usagePointers.append(
                            self.resourceUsagePointers(for: indexBuffer,
                                                          bufferRange: triangleDescriptor.indexBufferOffset..<(triangleDescriptor.indexBufferOffset + 3 * triangleDescriptor.triangleCount * bytesPerIndex),
                                                          encoder: encoder, usageType: .indexBuffer, stages: stages, isIndirectlyBound: true, firstCommandOffset: commandIndex).first!
                        )
                    }
                }
            }
        case .topLevelInstance(let instanceDescriptor):
            for structure in instanceDescriptor.primitiveStructures {
                usagePointers.append(
                    self.resourceUsagePointers(for: structure, encoder: encoder, usageType: .read, stages: stages, isIndirectlyBound: true, firstCommandOffset: commandIndex).first!
                    )
            }
            
            usagePointers.append(
                self.resourceUsagePointers(for: instanceDescriptor.instanceDescriptorBuffer, bufferRange: instanceDescriptor.instanceDescriptorBufferOffset..<(instanceDescriptor.instanceDescriptorBufferOffset + instanceDescriptor.instanceDescriptorStride * instanceDescriptor.instanceCount), encoder: encoder, usageType: .read, stages: stages, isIndirectlyBound: true, firstCommandOffset: commandIndex).first!
            )
        }
        return usagePointers
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    fileprivate func resourceUsagePointers<C: CommandEncoder>(for descriptor: IntersectionFunctionTableDescriptor, commandIndex: Int, stages: RenderStages, encoder: C) -> [ResourceUsagePointer] {
        var usagePointers = [ResourceUsagePointer]()
        for bufferBinding in descriptor.buffers {
            guard let bufferBinding = bufferBinding else { continue }
            switch bufferBinding {
            case .buffer(let buffer, let offset):
                usagePointers.append(
                    self.resourceUsagePointers(for: buffer, bufferRange: offset..<buffer.length, encoder: encoder, usageType: .read, stages: stages, isIndirectlyBound: true, firstCommandOffset: commandIndex).first!
                )
            case .functionTable:
                break
            }
        }
        return usagePointers
    }
}
