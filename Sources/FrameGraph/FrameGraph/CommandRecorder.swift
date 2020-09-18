//
//  LazyFrameGraph.swift
//  FrameGraph
//
//  Created by Thomas Roughton on 16/12/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

import FrameGraphUtilities
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

public protocol Releasable {
    func release()
}

extension Unmanaged : Releasable { }

public final class ReferenceBox<T> {
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
// We're also only allowing a 64 bit payload, since FrameGraphCommand will be sized to fit
// its biggest member (so if you add a struct...)
//
@usableFromInline
enum FrameGraphCommand {
    
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
    
    public typealias SetSamplerStateArgs = (bindingPath: ResourceBindingPath, descriptor: SamplerDescriptor)
    case setSamplerState(UnsafePointer<SetSamplerStateArgs>)
    
    public typealias SetArgumentBufferArgs = (bindingPath: ResourceBindingPath, argumentBuffer: _ArgumentBuffer)
    case setArgumentBuffer(UnsafePointer<SetArgumentBufferArgs>)
    
    public typealias SetArgumentBufferArrayArgs = (bindingPath: ResourceBindingPath, argumentBuffer: _ArgumentBufferArray, isBound: Bool)
    case setArgumentBufferArray(UnsafePointer<SetArgumentBufferArrayArgs>)
    
    // Render
    
    case clearRenderTargets
    
    public typealias SetVertexBufferArgs = (buffer: Buffer?, offset: UInt32, index: UInt32)
    case setVertexBuffer(UnsafePointer<SetVertexBufferArgs>)
    
    case setVertexBufferOffset(offset: UInt32, index: UInt32)
    
    case setRenderPipelineDescriptor(Unmanaged<ReferenceBox<RenderPipelineDescriptor>>)
    
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
final class FrameGraphCommandRecorder {
    @usableFromInline let frameGraphTransientRegistryIndex: Int
    @usableFromInline let renderPassScratchAllocator : ThreadLocalTagAllocator
    @usableFromInline let resourceUsageAllocator : TagAllocator.ThreadView
    @usableFromInline var commands : ChunkArray<FrameGraphCommand> // Lifetime: FrameGraph compilation (copied to another array for the backend).
    @usableFromInline var dataAllocator : TagAllocator.ThreadView // Lifetime: FrameGraph execution.
    @usableFromInline let unmanagedReferences : ExpandingBuffer<Releasable> // Lifetime: FrameGraph execution.
    @usableFromInline var readResources : HashSet<Resource>
    @usableFromInline var writtenResources : HashSet<Resource>
    
    @usableFromInline var resourceUsages = ChunkArray<(Resource, ResourceUsage)>()
    
    @inlinable
    init(frameGraphTransientRegistryIndex: Int, renderPassScratchAllocator: ThreadLocalTagAllocator, frameGraphExecutionAllocator: TagAllocator.ThreadView, resourceUsageAllocator: TagAllocator.ThreadView, unmanagedReferences: ExpandingBuffer<Releasable>) {
        assert(_isPOD(FrameGraphCommand.self))
        self.frameGraphTransientRegistryIndex = frameGraphTransientRegistryIndex
        self.commands = ChunkArray() // (allocator: AllocatorType(frameGraphExecutionAllocator), initialCapacity: 64)
        self.renderPassScratchAllocator = renderPassScratchAllocator
        self.resourceUsageAllocator = resourceUsageAllocator
        self.dataAllocator = frameGraphExecutionAllocator
        self.readResources = .init(allocator: .tagThreadView(frameGraphExecutionAllocator))
        self.writtenResources = .init(allocator: .tagThreadView(frameGraphExecutionAllocator))
        self.unmanagedReferences = unmanagedReferences
    }
    
    @inlinable
    public var nextCommandIndex : Int {
        return self.commands.count
    }
    
    @inlinable
    public func copyData<T>(_ data: T) -> UnsafePointer<T> {
        let result = self.dataAllocator.allocate(capacity: 1) as UnsafeMutablePointer<T>
        result.initialize(to: data)
        return UnsafePointer(result)
    }
    
    @inlinable
    public func record<T>(_ commandGenerator: (UnsafePointer<T>) -> FrameGraphCommand, _ data: T) {
        let command = commandGenerator(copyData(data))
        self.commands.append(command, allocator: .tagThreadView(self.dataAllocator))
    }
    
    @inlinable
    public func record(_ command: FrameGraphCommand) {
        self.commands.append(command, allocator: .tagThreadView(self.dataAllocator))
    }
    
    @inlinable
    public func record(_ commandGenerator: (UnsafePointer<CChar>) -> FrameGraphCommand, _ string: String) {
        let cStringAddress = string.withCString { label -> UnsafePointer<CChar> in
            let numChars = strlen(label)
            let destination : UnsafeMutablePointer<CChar> = self.dataAllocator.allocate(capacity: numChars + 1)
            destination.initialize(from: label, count: numChars)
            destination[numChars] = 0
            return UnsafePointer(destination)
        }
        
        let command = commandGenerator(cStringAddress)
        self.commands.append(command, allocator: .tagThreadView(self.dataAllocator))
    }
    
    @discardableResult
    @inlinable
    public func copyBytes(_ bytes: UnsafeRawPointer, length: Int) -> UnsafeRawPointer {
        let newBytes = self.dataAllocator.allocate(bytes: length, alignment: 16)
        newBytes.copyMemory(from: bytes, byteCount: length)
        return UnsafeRawPointer(newBytes)
    }
    
    @inlinable
    public func setLabel(_ label: String) {
        self.record(FrameGraphCommand.setLabel, label)
    }
    
    @inlinable
    public func pushDebugGroup(_ string: String) {
        self.record(FrameGraphCommand.pushDebugGroup, string)
    }
    
    @inlinable
    public func insertDebugSignpost(_ string: String) {
        self.record(FrameGraphCommand.insertDebugSignpost, string)
    }
    
    @inlinable
    public func boundResourceUsageNode<C : CommandEncoder>(`for` resource: Resource, encoder: C, usageType: ResourceUsageType, stages: RenderStages, activeRange: ActiveResourceRange, inArgumentBuffer: Bool, firstCommandOffset: Int) -> ResourceUsagePointer {
        assert(encoder.renderPass.writtenResources.isEmpty || encoder.renderPass.writtenResources.contains(where: { $0.handle == resource.handle }) || encoder.renderPass.readResources.contains(where: { $0.handle == resource.handle }), "Resource \(resource.handle) used but not declared.")
        
        assert(resource.isValid, "Resource \(resource) is invalid; it may be being used in a frame after it was created if it's a transient resource, or else may have been disposed if it's a persistent resource.")
        assert(resource._usesPersistentRegistry || resource.transientRegistryIndex == self.frameGraphTransientRegistryIndex, "Transient resource \(resource) is being used on a FrameGraph other than the one it was created on.")
        
        assert(resource.type != .argumentBuffer || !usageType.isWrite, "Read-write argument buffers are currently unsupported.")
        assert(!usageType.isWrite || !resource.flags.contains(.immutableOnceInitialised) || !resource.stateFlags.contains(.initialised), "immutableOnceInitialised resource \(resource) is being written to after it has been initialised.")
        
        if resource.flags.contains(.persistent) {
            if let textureUsage = resource.texture?.descriptor.usageHint {
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
            } else if let bufferUsage = resource.buffer?.descriptor.usageHint {
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
        
        let usage = ResourceUsage(type: usageType, stages: stages, activeRange: activeRange, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: firstCommandOffset, renderPass: encoder.passRecord)
        self.resourceUsages.append((Resource(resource), usage), allocator: .tagThreadView(resourceUsageAllocator))
        
        return self.resourceUsages.pointerToLastUsage
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    @inlinable
    public func resourceUsageNode<C : CommandEncoder>(`for` resource: _ArgumentBuffer, encoder: C, usageType: ResourceUsageType, stages: RenderStages, firstCommandOffset: Int) -> ResourceUsagePointer {
        assert(encoder.renderPass.writtenResources.isEmpty || encoder.renderPass.writtenResources.contains(where: { $0.handle == resource.handle }) || encoder.renderPass.readResources.contains(where: { $0.handle == resource.handle }), "Resource \(resource.handle) used but not declared.")
        
        assert(resource.isValid, "Resource \(resource) is invalid; it may be being used in a frame after it was created if it's a transient resource, or else may have been disposed if it's a persistent resource.")
        assert(resource._usesPersistentRegistry || resource.transientRegistryIndex == self.frameGraphTransientRegistryIndex, "Transient resource \(resource) is being used on a FrameGraph other than the one it was created on.")
        
        assert(resource.type != .argumentBuffer || !usageType.isWrite, "Read-write argument buffers are currently unsupported.")
        assert(!usageType.isWrite || !resource.flags.contains(.immutableOnceInitialised) || !resource.stateFlags.contains(.initialised), "immutableOnceInitialised resource \(resource) is being written to after it has been initialised.")
        
        if usageType.isRead {
            self.readResources.insert(Resource(resource))
        }
        if usageType.isWrite {
            self.writtenResources.insert(Resource(resource))
        }
        
        let usage = ResourceUsage(type: usageType, stages: stages, activeRange: .fullResource, inArgumentBuffer: false, firstCommandOffset: firstCommandOffset, renderPass: encoder.passRecord)
        self.resourceUsages.append((Resource(resource), usage), allocator: .tagThreadView(resourceUsageAllocator))
        
        return self.resourceUsages.pointerToLastUsage
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    @inlinable
    public func resourceUsageNode<C : CommandEncoder>(`for` resource: Buffer, bufferRange: Range<Int>, encoder: C, usageType: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool, firstCommandOffset: Int) -> ResourceUsagePointer {
        assert(encoder.renderPass.writtenResources.isEmpty || encoder.renderPass.writtenResources.contains(where: { $0.handle == resource.handle }) || encoder.renderPass.readResources.contains(where: { $0.handle == resource.handle }), "Resource \(resource) used but not declared.")
        
        assert(resource.isValid, "Resource \(resource) is invalid; it may be being used in a frame after it was created if it's a transient resource, or else may have been disposed if it's a persistent resource.")
        assert(resource._usesPersistentRegistry || resource.transientRegistryIndex == self.frameGraphTransientRegistryIndex, "Transient resource \(resource) is being used on a FrameGraph other than the one it was created on.")
        
        assert(!usageType.isWrite || !resource.flags.contains(.immutableOnceInitialised) || !resource.stateFlags.contains(.initialised), "immutableOnceInitialised resource \(resource) is being written to after it has been initialised.")
        
        if resource.flags.contains(.persistent) {
            let bufferUsage = resource.descriptor.usageHint
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
        
        if usageType.isRead {
            self.readResources.insert(Resource(resource))
        }
        if usageType.isWrite {
            self.writtenResources.insert(Resource(resource))
        }
        
        let usage = ResourceUsage(type: usageType, stages: stages, activeRange: .buffer(bufferRange), inArgumentBuffer: inArgumentBuffer, firstCommandOffset: firstCommandOffset, renderPass: encoder.passRecord)
        self.resourceUsages.append((Resource(resource), usage), allocator: .tagThreadView(resourceUsageAllocator))
        
        return self.resourceUsages.pointerToLastUsage
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    @inlinable
    public func resourceUsageNode<C : CommandEncoder>(`for` resource: Texture, arraySlice: Int?, level: Int?, encoder: C, usageType: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool, firstCommandOffset: Int) -> ResourceUsagePointer {
        assert(encoder.renderPass.writtenResources.isEmpty || encoder.renderPass.writtenResources.contains(where: { $0.handle == resource.handle }) || encoder.renderPass.readResources.contains(where: { $0.handle == resource.handle }), "Resource \(resource) used but not declared.")
        
        assert(resource.isValid, "Resource \(resource) is invalid; it may be being used in a frame after it was created if it's a transient resource, or else may have been disposed if it's a persistent resource.")
        assert(resource._usesPersistentRegistry || resource.transientRegistryIndex == self.frameGraphTransientRegistryIndex, "Transient resource \(resource) is being used on a FrameGraph other than the one it was created on.")
        
        assert(!usageType.isWrite || !resource.flags.contains(.immutableOnceInitialised) || !resource.stateFlags.contains(.initialised), "immutableOnceInitialised resource \(resource) is being written to after it has been initialised.")
        
        if resource.flags.contains(.persistent) {
            let textureUsage = resource.descriptor.usageHint
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
        }
        
        if usageType.isRead {
            self.readResources.insert(Resource(resource))
        }
        if usageType.isWrite {
            self.writtenResources.insert(Resource(resource))
        }
        
        var subresourceMask = TextureSubresourceMask()
        if let arraySlice = arraySlice, let level = level {
            subresourceMask.clear(descriptor: resource.descriptor, allocator: .tagThreadView(self.dataAllocator))
            subresourceMask[arraySlice: arraySlice, level: level, descriptor: resource.descriptor, allocator: .tagThreadView(self.dataAllocator)] = true
        } else {
            assert(arraySlice == nil && level == nil)
        }
        
        let usage = ResourceUsage(type: usageType, stages: stages, activeRange: .texture(subresourceMask), inArgumentBuffer: inArgumentBuffer, firstCommandOffset: firstCommandOffset, renderPass: encoder.passRecord)
        self.resourceUsages.append((Resource(resource), usage), allocator: .tagThreadView(resourceUsageAllocator))
        
        return self.resourceUsages.pointerToLastUsage
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    @inlinable
    public func addResourceUsage<C : CommandEncoder>(`for` resource: _ArgumentBuffer, commandIndex: Int, encoder: C, usageType: ResourceUsageType, stages: RenderStages) {
        let _ = self.resourceUsageNode(for: resource, encoder: encoder, usageType: usageType, stages: stages, firstCommandOffset: commandIndex)
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    @inlinable
    public func addResourceUsage<C : CommandEncoder>(`for` resource: Buffer, bufferRange: Range<Int>, commandIndex: Int, encoder: C, usageType: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool) {
        let _ = self.resourceUsageNode(for: resource, bufferRange: bufferRange, encoder: encoder, usageType: usageType, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: commandIndex)
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    @inlinable
    public func addResourceUsage<C : CommandEncoder>(`for` resource: Texture, arraySlice: Int?, level: Int?, commandIndex: Int, encoder: C, usageType: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool) {
        let _ = self.resourceUsageNode(for: resource, arraySlice: arraySlice, level: level, encoder: encoder, usageType: usageType, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: commandIndex)
    }
}
