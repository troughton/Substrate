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
@preconcurrency import Metal
#endif

#if canImport(MetalPerformanceShaders)
@preconcurrency import MetalPerformanceShaders
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
    
    public typealias SetRenderPipelineStateArgs = (state: UnsafeRawPointer, hasFragmentFunction: Bool, triangleFillMode: TriangleFillMode)
    case setRenderPipelineState(UnsafePointer<SetRenderPipelineStateArgs>)
    
    public typealias DrawPrimitivesArgs = (primitiveType: PrimitiveType, vertexStart: UInt32, vertexCount: UInt32, instanceCount: UInt32, baseInstance: UInt32)
    case drawPrimitives(UnsafePointer<DrawPrimitivesArgs>)
    
    public typealias DrawIndexedPrimitivesArgs = (primitiveType: PrimitiveType, indexCount: UInt32, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: UInt32, instanceCount: UInt32, baseVertex: Int32, baseInstance: UInt32)
    case drawIndexedPrimitives(UnsafePointer<DrawIndexedPrimitivesArgs>)
    
    case setViewport(UnsafePointer<Viewport>)
    
    case setFrontFacing(Winding)
    
    case setCullMode(CullMode)
    
    case setDepthStencilDescriptor(Unmanaged<ReferenceBox<DepthStencilDescriptor>>)
    
    case setScissorRect(UnsafePointer<ScissorRect>)
    
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
    
    var isDispatchCommand: Bool {
        switch self {
        case .dispatchThreads, .dispatchThreadgroups, .dispatchThreadgroupsIndirect:
            return true
        default:
            return false
        }
    }
    
    var isBlitCommand: Bool {
        switch self {
        case .copyBufferToTexture, .copyBufferToBuffer, .copyTextureToBuffer, .copyTextureToTexture, .blitTextureToTexture, .fillBuffer, .generateMipmaps, .synchroniseTexture, .synchroniseTextureSlice, .synchroniseBuffer:
            return true
        default:
            return false
        }
    }
    
    var isExternalCommand: Bool {
        switch self {
        case .encodeExternalCommand, .encodeRayIntersection, .encodeRayIntersectionRayCountBuffer:
            return true
        default:
            return false
        }
    }
    
    var isGPUActionCommand: Bool {
        return self.isDrawCommand || self.isDispatchCommand || self.isBlitCommand || self.isExternalCommand
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
    
    @usableFromInline var resourceUsages = ChunkArray<(Resource, ExplicitResourceUsage)>()
    
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
}
