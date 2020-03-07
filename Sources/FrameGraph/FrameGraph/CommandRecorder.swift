//
//  LazyFrameGraph.swift
//  FrameGraph
//
//  Created by Thomas Roughton on 16/12/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

import FrameGraphUtilities
import Foundation

#if canImport(MetalPerformanceShaders)
import MetalPerformanceShaders
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

public final class ComputePipelineDescriptorBox {
    public var pipelineDescriptor : ComputePipelineDescriptor
    public fileprivate(set) var threadGroupSizeIsMultipleOfThreadExecutionWidth = true
    
    @inlinable
    public init(_ pipelineDescriptor: ComputePipelineDescriptor) {
        self.pipelineDescriptor = pipelineDescriptor
    }
}

// We're skipping management functions here (fences, most resource synchronisation etc.) since they
// should be taken care of automatically by the frame graph/resource transitions.
//
// Payload pointees must be exclusively value types (or an unmanaged reference type).
// We're also only allowing a 64 bit payload, since FrameGraphCommand will be sized to fit
// its biggest member (so if you add a struct...)
//
public enum FrameGraphCommand {
    
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
}


public final class FrameGraphCommandRecorder {
    public let renderPassScratchAllocator : ThreadLocalTagAllocator
    public let commands : ExpandingBuffer<FrameGraphCommand> // Lifetime: FrameGraph compilation (copied to another array for the backend).
    public var dataAllocator : TagAllocator.ThreadView // Lifetime: FrameGraph execution.
    @usableFromInline
    let unmanagedReferences : ExpandingBuffer<Releasable> // Lifetime: FrameGraph execution.
    
    @inlinable
    init(renderPassScratchAllocator: ThreadLocalTagAllocator, frameGraphExecutionAllocator: TagAllocator.ThreadView, unmanagedReferences: ExpandingBuffer<Releasable>) {
        assert(_isPOD(FrameGraphCommand.self))
        self.commands = ExpandingBuffer(allocator: AllocatorType(frameGraphExecutionAllocator), initialCapacity: 64)
        self.renderPassScratchAllocator = renderPassScratchAllocator
        self.dataAllocator = frameGraphExecutionAllocator
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
        self.commands.append(command)
    }
    
    @inlinable
    public func record(_ command: FrameGraphCommand) {
        self.commands.append(command)
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
        self.commands.append(command)
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
    
}

public protocol CommandEncoder : class {
    var passRecord : RenderPassRecord { get }
    
    var commandRecorder : FrameGraphCommandRecorder { get }
    var startCommandIndex : Int { get }
    
    func endEncoding()
}

extension CommandEncoder {
    /// Returns the offset of the next command within this pass' command list.
    @inlinable
    public var nextCommandOffset : Int {
        return self.commandRecorder.nextCommandIndex - self.startCommandIndex
    }
    
    @inlinable
    public var renderPass : RenderPass {
        return self.passRecord.pass
    }
}

extension CommandEncoder {
    @inlinable
    public func pushDebugGroup(_ string: String) {
        commandRecorder.pushDebugGroup(string)
    }
    
    @inlinable
    public func popDebugGroup() {
        commandRecorder.record(.popDebugGroup)
    }
    
    @inlinable
    public func debugGroup<T>(_ groupName: String, perform: () throws -> T) rethrows -> T {
        self.pushDebugGroup(groupName)
        let result = try perform()
        self.popDebugGroup()
        return result
    }
    
    @inlinable
    public func insertDebugSignpost(_ string: String) {
        commandRecorder.insertDebugSignpost(string)
    }
}

/*
 
 ** Resource Binding Algorithm-of-sorts **
 
 When the user binds a resource for a key, record the association between that key and that resource.
 
 When the user submits a draw call, look at all key-resource pairs and bind them. Do this by retrieving the resource binding path from the backend, along with how the resource is used. Record the first usage of the resource;  the ‘first use command index’ is the first index for all of the bindings. Keep a handle to allow updating of the applicable command range. If a resource is not used, then it is not an active binding and its update handle is not retained.
 
 After the pipeline state is changed, we need to query all resources given their keys on the next draw call. If they are an active binding and the resource binding path has not changed and the usage type has not changed, then we do not need to make any changes; however, if any of the above change we need to end the applicable command range at the index of the last draw call and register a new resource binding path and update handle.
 
 We can bypass the per-draw-call checks iff the pipeline state has not changed and there have been no changes to bound resources.
 
 For buffers, we also need to track a 32-bit offset. If the offset changes but not the main resource binding path, then we submit a update-offset command instead rather than a ‘bind’ command. The update-offset command includes the ObjectIdentifier for the resource.
 
 When encoding has finished, update the applicable command range for all active bindings to continue through to the last draw call made within the encoder.
 
 
 A requirement for resource binding is that subsequently bound pipeline states are compatible with the pipeline state bound at the time of the first draw call.
 */

public class ResourceBindingEncoder : CommandEncoder {
    
    public struct BoundResource {
        public var resource : Resource
        public var bindingCommand : UnsafeMutableRawPointer?
        public var usageNode : ResourceUsageNodePtr?
        public var isInArgumentBuffer : Bool
        /// Whether the resource is assumed to be used in the same way for the entire time it's bound.
        public var consistentUsageAssumed : Bool
    }
    
    public let commandRecorder : FrameGraphCommandRecorder
    public let passRecord: RenderPassRecord
    public let startCommandIndex : Int
    
    @usableFromInline
    let resourceUsages : ResourceUsages
    
    public enum _ArgumentBufferType {
        case standalone
        case inArray(index: Int, bindingArgs: UnsafeMutablePointer<FrameGraphCommand.SetArgumentBufferArrayArgs>)
        
        @inlinable
        public var arrayIndex : Int {
            switch self {
            case .standalone:
                return 0
            case .inArray(let index, _):
                return index
            }
        }
    }
    
    @usableFromInline
    let pendingArgumentBuffersByKey : ExpandingBuffer<(FunctionArgumentKey, _ArgumentBuffer, type: _ArgumentBufferType, assumeConsistentUsage: Bool)>
    var pendingArgumentBufferByKeyCountLastUpdate = 0
    
    let pendingArgumentBuffers : ExpandingBuffer<(ResourceBindingPath, _ArgumentBuffer, type: _ArgumentBufferType, assumeConsistentUsage: Bool)>
    var pendingArgumentBufferCountLastUpdate = 0
    
    @usableFromInline
    let resourceBindingCommands : ExpandingBuffer<(FunctionArgumentKey, FrameGraphCommand)>
    var resourceBindingCommandCountLastUpdate = 0

    // The UnsafeMutableRawPointer points to the args parameterising the command.
    // It enables us to go back and change the command during recording (e.g. with a setBufferOffset after a setBuffer)
    @usableFromInline
    var boundResources : HashMap<ResourceBindingPath, BoundResource>
    
    // untrackedBoundResources is similar to boundResources, except we explicitly don't track changes in pipeline state;
    // it's assumed that the usage of the resource remains the same until the resource is unbound or the command encoder is
    // ended.
    @usableFromInline
    var untrackedBoundResources : HashMap<ResourceBindingPath, BoundResource>
    
    // The following methods and variables are helpers for updateResourceUsages.
    // They're contained on the object rather than as local variables to minimised allocations and retain-release traffic.
    
    @usableFromInline
    let usageNodesToUpdate : ExpandingBuffer<ResourceUsageNodePtr> // nodes to update the upper bound on to the last usage index.
    
    deinit {
        self.boundResources.deinit()
        self.untrackedBoundResources.deinit()
    }
    
    @usableFromInline
    var lastGPUCommandIndex = 0
    
    @usableFromInline
    var needsUpdateBindings = false
    @usableFromInline
    var pipelineStateChanged = false
    @usableFromInline
    var depthStencilStateChanged = false
    
    @usableFromInline
    var currentPipelineReflection : PipelineReflection! = nil
    
    init(commandRecorder: FrameGraphCommandRecorder, resourceUsages: ResourceUsages, passRecord: RenderPassRecord) {
        self.commandRecorder = commandRecorder
        self.resourceUsages = resourceUsages
        self.passRecord = passRecord
        self.startCommandIndex = self.commandRecorder.nextCommandIndex
        
        self.boundResources = HashMap(allocator: AllocatorType(commandRecorder.renderPassScratchAllocator))
        self.untrackedBoundResources = HashMap(allocator: AllocatorType(commandRecorder.renderPassScratchAllocator))
        self.pendingArgumentBuffersByKey = ExpandingBuffer(allocator: AllocatorType(commandRecorder.renderPassScratchAllocator))
        self.pendingArgumentBuffers = ExpandingBuffer(allocator: AllocatorType(commandRecorder.renderPassScratchAllocator))
        self.resourceBindingCommands = ExpandingBuffer(allocator: AllocatorType(commandRecorder.renderPassScratchAllocator))
        self.usageNodesToUpdate = ExpandingBuffer(allocator: AllocatorType(commandRecorder.renderPassScratchAllocator))
        
        self.pushDebugGroup(passRecord.pass.name)
    }
    
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, key: FunctionArgumentKey) {
        let args : FrameGraphCommand.SetBytesArgs = (.nil, commandRecorder.copyBytes(bytes, length: length), UInt32(length))
        
        let argData = commandRecorder.copyData(args)
        
        self.resourceBindingCommands.append(
            (key, .setBytes(argData))
        )
        
        self.needsUpdateBindings = true
    }
    
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, path: ResourceBindingPath) {
        let args : FrameGraphCommand.SetBytesArgs = (path, commandRecorder.copyBytes(bytes, length: length), UInt32(length))
        
        let argData = commandRecorder.copyData(args)
        
        commandRecorder.commands.append(
            .setBytes(argData)
        )
    }
    
    public func setBuffer(_ buffer: Buffer?, offset: Int, key: FunctionArgumentKey) {
        guard let buffer = buffer else { return }
        self.resourceUsages.registerResource(Resource(buffer))
        
        let args : FrameGraphCommand.SetBufferArgs = (.nil, buffer, UInt32(offset), false)
        
        self.resourceBindingCommands.append(
            (key, .setBuffer(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    public func setBufferOffset(_ offset: Int, key: FunctionArgumentKey) {
        let args : FrameGraphCommand.SetBufferOffsetArgs = (.nil, nil, UInt32(offset))
        
        self.resourceBindingCommands.append(
            (key, .setBufferOffset(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    public func setSampler(_ descriptor: SamplerDescriptor?, key: FunctionArgumentKey) {
        guard let descriptor = descriptor else { return }
        
        let args : FrameGraphCommand.SetSamplerStateArgs = (.nil, descriptor)
        
        self.resourceBindingCommands.append(
            (key, .setSamplerState(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    public func setTexture(_ texture: Texture?, key: FunctionArgumentKey) {
        guard let texture = texture else { return }
        self.resourceUsages.registerResource(Resource(texture))
        
        let args : FrameGraphCommand.SetTextureArgs = (.nil, texture)
        
        self.resourceBindingCommands.append(
            (key, .setTexture(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    public func setArguments<A : ArgumentBufferEncodable>(_ arguments: A, at setIndex: Int) {
        if A.self == NilSet.self {
            return
        }
        
        let bindingPath = RenderBackend.argumentBufferPath(at: setIndex, stages: A.activeStages)
        
        let argumentBuffer = _ArgumentBuffer()
        assert(argumentBuffer.bindings.isEmpty)
        arguments.encode(into: argumentBuffer, setIndex: setIndex)
        argumentBuffer.label = "Descriptor Set for \(String(reflecting: A.self))"
     
        if _isDebugAssertConfiguration() {
            for binding in argumentBuffer.bindings {
                switch binding.1 {
                case .buffer(let buffer, _):
                    assert(buffer.type == .buffer)
                case .texture(let texture):
                    assert(texture.type == .texture)
                default:
                    break
                }
            }
        }

        self.pendingArgumentBuffers.append((bindingPath, argumentBuffer, type: .standalone, assumeConsistentUsage: false))
        self.needsUpdateBindings = true
    }
    
    public func setArgumentBuffer<K>(_ argumentBuffer: ArgumentBuffer<K>?, at index: Int, stages: RenderStages) {
        guard let argumentBuffer = argumentBuffer else { return }
        let bindingPath = RenderBackend.argumentBufferPath(at: index, stages: stages)
        
        self.pendingArgumentBuffers.append((bindingPath, argumentBuffer.argumentBuffer, type: .standalone, assumeConsistentUsage: false))
        self.needsUpdateBindings = true
    }
    
    public func setArgumentBufferArray<K>(_ argumentBufferArray: ArgumentBufferArray<K>?, at index: Int, stages: RenderStages, assumeConsistentUsage: Bool = false) {
        guard let argumentBufferArray = argumentBufferArray?.argumentBufferArray else { return }
        let bindingPath = RenderBackend.argumentBufferPath(at: index, stages: stages)
        
        let args : FrameGraphCommand.SetArgumentBufferArrayArgs = (bindingPath, argumentBufferArray, false) // false meaning is not yet bound
        let argsPointer = commandRecorder.copyData(args)
        
        for (i, argumentBuffer) in argumentBufferArray._bindings.enumerated() {
            guard let argumentBuffer = argumentBuffer else { continue }
            let type : _ArgumentBufferType = .inArray(index: i, bindingArgs: UnsafeMutablePointer(mutating: argsPointer))
            self.pendingArgumentBuffers.append((bindingPath, argumentBuffer, type: type, assumeConsistentUsage: assumeConsistentUsage))
        }
        
        self.resourceUsages.registerResource(Resource(argumentBufferArray))
        
        self.needsUpdateBindings = true
    }
    
    public func setArgumentBuffer<K>(_ argumentBuffer: ArgumentBuffer<K>?, key: FunctionArgumentKey) {
        guard let argumentBuffer = argumentBuffer else { return }
        
        self.pendingArgumentBuffersByKey.append((key, argumentBuffer.argumentBuffer, type: .standalone, assumeConsistentUsage: false))
        self.needsUpdateBindings = true
    }
    
    public func setArgumentBufferArray<K>(_ argumentBufferArray: ArgumentBufferArray<K>?, key: FunctionArgumentKey, assumeConsistentUsage: Bool = false) {
        guard let argumentBufferArray = argumentBufferArray?.argumentBufferArray else { return }
        
        let args : FrameGraphCommand.SetArgumentBufferArrayArgs = (.nil, argumentBufferArray, false) // false meaning is not yet bound
        let argsPointer = commandRecorder.copyData(args)
        
        for (i, argumentBuffer) in argumentBufferArray._bindings.enumerated() {
            guard let argumentBuffer = argumentBuffer else { continue }
            
            let type : _ArgumentBufferType = .inArray(index: i, bindingArgs: UnsafeMutablePointer(mutating: argsPointer))
            self.pendingArgumentBuffersByKey.append((key, argumentBuffer, type: type, assumeConsistentUsage: assumeConsistentUsage))
        }
        
        // We add the command to the commands list here so that the binding key can be translated.
        self.resourceBindingCommands.append((key, FrameGraphCommand.setArgumentBufferArray(UnsafePointer(argsPointer))))
        
        self.resourceUsages.registerResource(Resource(argumentBufferArray))
        
        self.needsUpdateBindings = true
    }
    
    
    func updateUsageNodes(lastIndex: Int) {
        for usageNode in usageNodesToUpdate {
            usageNode.pointee.element.commandRangeInPass = Range(uncheckedBounds: (usageNode.pointee.element.commandRangeInPass.lowerBound, lastIndex + 1))
        }
        usageNodesToUpdate.removeAll()
    }
   
    public func updateResourceUsages(endingEncoding: Bool = false) {
        guard self.needsUpdateBindings || endingEncoding else {
            return
        }
        defer { self.needsUpdateBindings = false }
        
        self.updateResourceUsagesInternal(endingEncoding: endingEncoding)
    }
    
    func updateResourceUsagesInternal(endingEncoding: Bool) {
        defer { self.pipelineStateChanged = false }
        
        if endingEncoding {
            // We shouldn't bind anything if we're ending encoding; doing so could mean we bind invalid resources
            // and then are unable to materialise them within the backends' resource registries since their lifetime
            // has already expired.
            let endIndex = self.lastGPUCommandIndex + 1
            self.boundResources.forEach { (path, value) in
                if let usageNode = value.usageNode {
                    usageNode.pointee.element.commandRangeInPass = usageNode.pointee.element.commandRangeInPass.lowerBound..<endIndex
                }
            }
            self.untrackedBoundResources.forEach { (path, value) in
                if let usageNode = value.usageNode {
                    usageNode.pointee.element.commandRangeInPass = usageNode.pointee.element.commandRangeInPass.lowerBound..<endIndex
                }
            }
            return
        }
        
        guard let pipelineReflection = self.currentPipelineReflection else {
            fatalError("No render or compute pipeline is set for pass \(renderPass.name).")
        }
        
        // This function is declared within the method since that gives slightly better performance.
        func replacingBoundResourceNode(bindingPath: ResourceBindingPath, resultUntrackedIfUsed: Bool, perform: (_ oldNode: BoundResource?) -> BoundResource?) {
            let indexInBoundResources = self.boundResources.find(key: bindingPath)
            var indexInUntrackedBoundResources : Int? = nil
            var currentlyBound : BoundResource? = nil
            
            if let indexInBoundResources = indexInBoundResources {
                currentlyBound = self.boundResources.removeValue(at: indexInBoundResources)
            } else {
                indexInUntrackedBoundResources = self.untrackedBoundResources.find(key: bindingPath)
                if let indexInUntrackedBoundResources = indexInUntrackedBoundResources {
                    currentlyBound = self.untrackedBoundResources.removeValue(at: indexInUntrackedBoundResources)
                }
            }
            
            let newValue = perform(currentlyBound)
            
            if let newValue = newValue {
                if resultUntrackedIfUsed, newValue.usageNode != nil {
                    if let target = indexInUntrackedBoundResources {
                        self.untrackedBoundResources.insertAtIndex(target, key: bindingPath, value: newValue)
                    } else {
                        self.untrackedBoundResources.insertUnique(key: bindingPath, value: newValue)
                    }
                } else {
                    if let target = indexInBoundResources {
                        self.boundResources.insertAtIndex(target, key: bindingPath, value: newValue)
                    } else {
                        self.boundResources.insertUnique(key: bindingPath, value: newValue)
                    }
                }
            }
            
            if let currentBoundUsage = currentlyBound?.usageNode, newValue?.usageNode != currentBoundUsage {
                self.usageNodesToUpdate.append(currentBoundUsage) // The old resource is no longer bound, so we need to end the old usage.
            }
        }
        
        let firstCommandOffset = self.nextCommandOffset
        
        let resourceBindingCommandsStartCount = self.resourceBindingCommands.count
        
        // If the pipeline state hasn't changed, only try to bind new commands.
        let processingRange = (pipelineStateChanged ? 0 : self.resourceBindingCommandCountLastUpdate)..<resourceBindingCommandsStartCount
        
        for i in processingRange {
            let (key, command) = self.resourceBindingCommands[i]
            guard let bindingPath = key.computedBindingPath(pipelineReflection: pipelineReflection) else {
                self.resourceBindingCommands.append((key, command))
                continue
            }
            
            replacingBoundResourceNode(bindingPath: bindingPath, resultUntrackedIfUsed: false, perform: { currentlyBound in
                let argsPtr : UnsafeMutableRawPointer
                let identifier : Resource.Handle
                switch command {
                case .setSamplerState(let args):
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    self.commandRecorder.commands.append(command)
                    return nil
                    
                case .setArgumentBufferArray(let args):
                    // We'll actually add setArgumentBufferArray to the command
                    // stream later once its first argument buffer is bound.
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    return nil
                    
                case .setBytes(let args):
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    self.commandRecorder.commands.append(command)
                    return nil
                    
                case .setBufferOffset(let args):
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    self.commandRecorder.commands.append(command)
                    
                    guard let setBufferArgsRaw = currentlyBound?.bindingCommand else {
                        assertionFailure("No buffer bound when setBufferOffset was called for key \(key).")
                        return currentlyBound
                    }
                    let setBufferArgs = setBufferArgsRaw.assumingMemoryBound(to: FrameGraphCommand.SetBufferArgs.self)
                    
                    let handle = setBufferArgs.pointee.buffer
                    UnsafeMutablePointer(mutating: args).pointee.buffer = handle
                    setBufferArgs.pointee.hasDynamicOffset = true
                    
                    return currentlyBound
                    
                case .setBuffer(let args):
                    if let previousArgs = currentlyBound?.bindingCommand?.assumingMemoryBound(to: FrameGraphCommand.SetBufferArgs.self) {
                        if previousArgs.pointee.buffer == args.pointee.buffer { // Ignore the duplicate binding.
                            if !self.pipelineStateChanged, previousArgs.pointee.offset == args.pointee.offset {
                                return currentlyBound
                            } /* else {
                             // TODO: translate duplicate setBuffer calls into setBufferOffset.
                             }*/
                        }
                    }
                    
                    identifier = args.pointee.buffer.handle
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    argsPtr = UnsafeMutableRawPointer(mutating: args)
                    
                case .setTexture(let args):
                    if let previousArgs = currentlyBound?.bindingCommand?.assumingMemoryBound(to: FrameGraphCommand.SetTextureArgs.self) {
                        if !self.pipelineStateChanged, previousArgs.pointee.texture == args.pointee.texture { // Ignore the duplicate binding.
                            return currentlyBound
                        }
                    }
                    
                    identifier = args.pointee.texture.handle
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    argsPtr = UnsafeMutableRawPointer(mutating: args)
                    
                default:
                    preconditionFailure()
                }
                
                // Optimisation: if the pipeline state hasn't changed, these are the only resources we need to consider, so look up their reflection data immediately.
                if !self.pipelineStateChanged, let reflection = pipelineReflection.argumentReflection(at: bindingPath), reflection.isActive {
                    self.commandRecorder.commands.append(command)
                    let node = self.resourceUsages.resourceUsageNode(for: identifier, encoder: self, usageType: reflection.usageType, stages: reflection.stages, inArgumentBuffer: false, firstCommandOffset: firstCommandOffset)
                    return BoundResource(resource: Resource(handle: identifier), bindingCommand: argsPtr, usageNode: node, isInArgumentBuffer: false, consistentUsageAssumed: false)
                } else {
                    return BoundResource(resource: Resource(handle: identifier), bindingCommand: argsPtr, usageNode: nil, isInArgumentBuffer: false, consistentUsageAssumed: false)
                }
            })
        }
        
        self.resourceBindingCommands.removeRange(processingRange)
        
        let pendingArgumentBuffersByKeyStartCount = self.pendingArgumentBuffersByKey.count
        let argumentBufferByKeyProcessingRange = (pipelineStateChanged ? 0 : self.pendingArgumentBufferByKeyCountLastUpdate)..<pendingArgumentBuffersByKeyStartCount
        // If the pipeline state hasn't changed, only try to bind new argument buffers.
        for i in argumentBufferByKeyProcessingRange {
            let (key, argumentBuffer, argBufferType, assumeConsistentUsage) = self.pendingArgumentBuffersByKey[i]
            
            let arrayIndex = argBufferType.arrayIndex
            
            let argumentBufferPath : ResourceBindingPath
            if let path = key.bindingPath(arrayIndex: arrayIndex, argumentBufferPath: nil) {
                guard pipelineReflection.bindingIsActive(at: path) else {
                    self.pendingArgumentBuffersByKey.append((key, argumentBuffer, argBufferType, assumeConsistentUsage))
                    continue
                }
                argumentBufferPath = path
            } else if let path = pipelineReflection.bindingPath(argumentBuffer: argumentBuffer, argumentName: key.stringValue, arrayIndex: arrayIndex) {
                argumentBufferPath = path
            } else {
                self.pendingArgumentBuffersByKey.append((key, argumentBuffer, argBufferType, assumeConsistentUsage))
                continue
            }
            
            self.pendingArgumentBuffers.append((argumentBufferPath, argumentBuffer, argBufferType, assumeConsistentUsage))
        }
        
        self.pendingArgumentBuffersByKey.removeRange(argumentBufferByKeyProcessingRange)
        
        let pendingArgumentBuffersStartCount = self.pendingArgumentBuffers.count
        let argumentBufferProcessingRange = (pipelineStateChanged ? 0 : self.pendingArgumentBufferCountLastUpdate)..<pendingArgumentBuffersStartCount
        // If the pipeline state hasn't changed, only try to bind new argument buffers.
        for i in argumentBufferProcessingRange {
            let (argumentBufferPathTemp, argumentBuffer, argBufferType, assumeConsistentUsage) = self.pendingArgumentBuffers[i]
            let argumentBufferPath = pipelineReflection.remapArgumentBufferPathForActiveStages(argumentBufferPathTemp)
            
            guard pipelineReflection.bindingIsActive(at: argumentBufferPath) else {
                self.pendingArgumentBuffers.append((argumentBufferPath, argumentBuffer, argBufferType, assumeConsistentUsage))
                continue
            }
            
            self.resourceUsages.registerResource(Resource(argumentBuffer))
            
            replacingBoundResourceNode(bindingPath: argumentBufferPath, resultUntrackedIfUsed: assumeConsistentUsage, perform: { currentlyBound in

                let argsPtr : UnsafeMutableRawPointer
                
                switch argBufferType {
                case .standalone:
                    argsPtr = UnsafeMutableRawPointer(mutating: commandRecorder.copyData((argumentBufferPath, argumentBuffer) as FrameGraphCommand.SetArgumentBufferArgs))
                case .inArray(_, let bindingArgs):
                    argsPtr = UnsafeMutableRawPointer(mutating: bindingArgs)
                }
                
                // Optimisation: if the pipeline state hasn't changed, these are the only resources we need to consider, so look up their reflection data immediately.
                if !self.pipelineStateChanged, let reflection = pipelineReflection.argumentReflection(at: argumentBufferPath), reflection.isActive {
                    argumentBuffer.encoder = pipelineReflection.argumentBufferEncoder(at: argumentBufferPath)!
//                    print("Encoder for \(argumentBuffer.label ?? "unnamed arg buffer") is \(argumentBuffer.encoder!)")
                    
                    switch argBufferType {
                    case .standalone:
                        self.commandRecorder.commands.append(.setArgumentBuffer(argsPtr.assumingMemoryBound(to: FrameGraphCommand.SetArgumentBufferArgs.self)))
                    case .inArray(_, let bindingArgs):
                        if !bindingArgs.pointee.isBound {
                            self.commandRecorder.commands.append(.setArgumentBufferArray(argsPtr.assumingMemoryBound(to: FrameGraphCommand.SetArgumentBufferArrayArgs.self)))
                            bindingArgs.pointee.isBound = true
                        }
                        assert(argsPtr.assumingMemoryBound(to: FrameGraphCommand.SetArgumentBufferArrayArgs.self).pointee.argumentBuffer == argumentBuffer.sourceArray)
                    }
                    
                    let node = self.resourceUsages.resourceUsageNode(for: argumentBuffer.handle, encoder: self, usageType: reflection.usageType, stages: reflection.stages, inArgumentBuffer: false, firstCommandOffset: firstCommandOffset)
                    return BoundResource(resource: Resource(argumentBuffer), bindingCommand: argsPtr, usageNode: node, isInArgumentBuffer: false, consistentUsageAssumed: false)
                } else {
                    return BoundResource(resource: Resource(argumentBuffer), bindingCommand: argsPtr, usageNode: nil, isInArgumentBuffer: false, consistentUsageAssumed: false)
                }
            })
            
            
            argumentBuffer.translateEnqueuedBindings { (key, arrayIndex, resource) in
                
                let renderAPIResource : Resource?
                switch resource {
                case .buffer(let buffer, _):
                    renderAPIResource = Resource(buffer)
                case .texture(let texture):
                    renderAPIResource = Resource(texture)
                default:
                    renderAPIResource = nil
                }
                
                guard let bindingPath = key.bindingPath(argumentBufferPath: argumentBufferPath, arrayIndex: arrayIndex, pipelineReflection: pipelineReflection) else {
                    if let identifier = renderAPIResource?.handle {
                        let _ = self.resourceUsages.resourceUsageNode(for: identifier, encoder: self, usageType: .unusedArgumentBuffer, stages: .cpuBeforeRender, inArgumentBuffer: true, firstCommandOffset: firstCommandOffset)
                    }
                    
                    return nil
                }
                
                return bindingPath
            }
            
            for (bindingPath, resource) in argumentBuffer.bindings {
                let bindingPath = pipelineReflection.bindingPath(pathInOriginalArgumentBuffer: bindingPath, newArgumentBufferPath: argumentBufferPath)
                
                let renderAPIResource : Resource?
                switch resource {
                case .buffer(let buffer, _):
                    renderAPIResource = Resource(buffer)
                case .texture(let texture):
                    renderAPIResource = Resource(texture)
                default:
                    renderAPIResource = nil
                }
                
                let identifier : Resource.Handle
                if let renderAPIResource = renderAPIResource {
                    identifier = renderAPIResource.handle
                    self.resourceUsages.registerResource(renderAPIResource)
                } else {
                    if let existingUsage = self.boundResources.removeValue(forKey: bindingPath)?.usageNode {
                        self.usageNodesToUpdate.append(existingUsage)
                    }
                    if let existingUsage = self.untrackedBoundResources.removeValue(forKey: bindingPath)?.usageNode {
                        self.usageNodesToUpdate.append(existingUsage)
                    }
                    continue
                }
                
                // FIXME: it may be better to manually inline `replacingBoundResourceNode`. There is a slight performance deficit (around 1.5ms given an average frame time of 18-21ms) when the closure is called directly.
                
                replacingBoundResourceNode(bindingPath: bindingPath, resultUntrackedIfUsed: assumeConsistentUsage, perform: { currentlyBound in
                    // Optimisation: if the pipeline state hasn't changed, these are the only resources we need to consider, so look up their reflection data immediately.
                    if !self.pipelineStateChanged, let reflection = pipelineReflection.argumentReflection(at: bindingPath), reflection.isActive {
                        let node = self.resourceUsages.resourceUsageNode(for: identifier, encoder: self, usageType: reflection.usageType, stages: reflection.stages, inArgumentBuffer: true, firstCommandOffset: firstCommandOffset)
                        return BoundResource(resource: Resource(handle: identifier), bindingCommand: nil, usageNode: node, isInArgumentBuffer: true, consistentUsageAssumed: assumeConsistentUsage)
                    } else {
                        return BoundResource(resource: Resource(handle: identifier), bindingCommand: nil, usageNode: nil, isInArgumentBuffer: true, consistentUsageAssumed: assumeConsistentUsage)
                    }
                })
            }
        }
        
        self.pendingArgumentBuffers.removeRange(argumentBufferProcessingRange)
        
        if self.pipelineStateChanged {
            // Only update tracked bound resources, not any members of untrackedBoundResources
            // We should also bind any resources that haven't been yet bound – if the pipeline state changed, we may have skipped binding earlier
            // and intended to have it done here instead.
            
            self.boundResources.forEachMutating { bindingPath, /* inout */ boundResource, /* inout */ deleteEntry in
                if let reflection = pipelineReflection.argumentReflection(at: bindingPath), reflection.isActive {
                    // Mark the resource as used if it currently isn't
                    assert(reflection.type == boundResource.resource.type || (reflection.type == .buffer && boundResource.resource.type == .argumentBuffer))
                        
                    // If the command to bind the resource hasn't yet been inserted into the command stream, insert it now.
                    if boundResource.usageNode == nil, let bindingCommandArgs = boundResource.bindingCommand {
                        switch boundResource.resource.type {
                        case .texture:
                            self.commandRecorder.commands.append(.setTexture(bindingCommandArgs.assumingMemoryBound(to: FrameGraphCommand.SetTextureArgs.self)))
                        case .buffer:
                            self.commandRecorder.commands.append(.setBuffer(bindingCommandArgs.assumingMemoryBound(to: FrameGraphCommand.SetBufferArgs.self)))
                        case .argumentBuffer:
                            let argumentBuffer = boundResource.resource.argumentBuffer!
                            argumentBuffer.encoder = pipelineReflection.argumentBufferEncoder(at: bindingPath)!
//                            print("Encoder for \(argumentBuffer.label ?? "unnamed arg buffer") is \(argumentBuffer.encoder!)")
                            
                            // The command might be either a setArgumentBuffer or setArgumentBufferArray command.
                            // Check to see whether the resource is an _ArgumentBuffer or _ArgumentBufferArray to distinguish.
                            let setArgumentBufferArgs = bindingCommandArgs.assumingMemoryBound(to: FrameGraphCommand.SetArgumentBufferArgs.self)
                            
                            if Resource(setArgumentBufferArgs.pointee.argumentBuffer).type == .argumentBufferArray {
                                let arrayArguments = bindingCommandArgs.assumingMemoryBound(to: FrameGraphCommand.SetArgumentBufferArrayArgs.self)
                                if !arrayArguments.pointee.isBound {
                                    self.commandRecorder.commands.append(.setArgumentBufferArray(arrayArguments))
                                    arrayArguments.pointee.isBound = true
                                }
                                assert(arrayArguments.pointee.argumentBuffer == argumentBuffer.sourceArray)
                            } else {
                                let setArgumentBufferArgs = bindingCommandArgs.assumingMemoryBound(to: FrameGraphCommand.SetArgumentBufferArgs.self)
                                self.commandRecorder.commands.append(.setArgumentBuffer(setArgumentBufferArgs))
                            }
                            
                        default:
                            preconditionFailure()
                        }
                    }
                    
                    let node = self.resourceUsages.resourceUsageNode(for: boundResource.resource.handle, encoder: self, usageType: reflection.usageType, stages: reflection.stages, inArgumentBuffer: boundResource.isInArgumentBuffer, firstCommandOffset: firstCommandOffset)
                    boundResource.usageNode = node
                    
                    assert(!boundResource.resource.usages.isEmpty)
                    
                    if boundResource.consistentUsageAssumed {
                        deleteEntry = true // Delete the entry from this HashMap
                        self.untrackedBoundResources.insertUnique(key: bindingPath, value: boundResource)
                    }
                    
                } else {
                    // The resource is currently unused; end its usage.
                    if boundResource.isInArgumentBuffer {
                        let _ = self.resourceUsages.resourceUsageNode(for: boundResource.resource.handle, encoder: self, usageType: .unusedArgumentBuffer, stages: .cpuBeforeRender, inArgumentBuffer: true, firstCommandOffset: firstCommandOffset)
                    } else if let currentUsage = boundResource.usageNode {
                        // The resource is currently unused; end its usage.
                        self.usageNodesToUpdate.append(currentUsage)
                        boundResource.usageNode = nil
                    }
                }
            }
        }
        
        updateUsageNodes(lastIndex: self.lastGPUCommandIndex)
        
        self.resourceBindingCommandCountLastUpdate = self.resourceBindingCommands.count
        self.pendingArgumentBufferByKeyCountLastUpdate = self.pendingArgumentBuffersByKey.count
        self.pendingArgumentBufferCountLastUpdate = self.pendingArgumentBuffers.count
    }
    
    public func resetAllBindings() {
        self.resourceBindingCommandCountLastUpdate = 0
        self.pendingArgumentBufferByKeyCountLastUpdate = 0
        self.pendingArgumentBufferCountLastUpdate = 0
        
        self.resourceBindingCommands.removeAll()
        self.pendingArgumentBuffers.removeAll()
        self.pendingArgumentBuffersByKey.removeAll()
        
        let endIndex = self.lastGPUCommandIndex + 1
        
        self.boundResources.removeAll(iterating: { (path, value) in
            if let usageNode = value.usageNode {
                usageNode.pointee.element.commandRangeInPass = usageNode.pointee.element.commandRangeInPass.lowerBound..<endIndex
            }
        })
        
        self.untrackedBoundResources.removeAll(iterating: { (path, value) in
            if let usageNode = value.usageNode {
                usageNode.pointee.element.commandRangeInPass = usageNode.pointee.element.commandRangeInPass.lowerBound..<endIndex
            }
        })
    }
    
    public func endEncoding() {
        self.updateResourceUsages(endingEncoding: true)
        self.popDebugGroup() // Pass Name
    }
}

extension ResourceBindingEncoder {
    
    @inlinable
    public func setValue<T : ResourceProtocol>(_ value: T, key: FunctionArgumentKey) {
        preconditionFailure("setValue should not be used with resources; use setBuffer, setTexture, or setArgumentBuffer instead.")
    }
    
    @inlinable
    public func setValue<T>(_ value: T, key: FunctionArgumentKey) {
        assert(!(T.self is AnyObject.Type), "setValue should only be used with value types.")
        
        var value = value
        withUnsafeBytes(of: &value) { bytes in
            self.setBytes(bytes.baseAddress!, length: bytes.count, key: key)
        }
    }
}

public protocol AnyRenderCommandEncoder {
    func setArgumentBuffer<K>(_ argumentBuffer: ArgumentBuffer<K>?, at index: Int, stages: RenderStages)
    
    func setArgumentBufferArray<K>(_ argumentBufferArray: ArgumentBufferArray<K>?, at index: Int, stages: RenderStages, assumeConsistentUsage: Bool)
    
    func setVertexBuffer(_ buffer: Buffer?, offset: Int, index: Int)
    
    func setVertexBufferOffset(_ offset: Int, index: Int)
    
    func setViewport(_ viewport: Viewport)
    
    func setFrontFacing(_ frontFacingWinding: Winding)
    
    func setCullMode(_ cullMode: CullMode)
    
    func setTriangleFillMode(_ fillMode: TriangleFillMode)

    func setScissorRect(_ rect: ScissorRect)
    
    func setDepthClipMode(_ depthClipMode: DepthClipMode)
    
    func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float)
    
    func setStencilReferenceValue(_ referenceValue: UInt32)
    
    func setStencilReferenceValues(front frontReferenceValue: UInt32, back backReferenceValue: UInt32)
    
    func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int, baseInstance: Int)
    
    func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int, baseVertex: Int, baseInstance: Int)
}

public final class RenderCommandEncoder : ResourceBindingEncoder, AnyRenderCommandEncoder {
    
    @usableFromInline
    enum Attachment : Hashable, CustomHashable {
        case color(Int)
        case depth
        case stencil
        
        public var customHashValue: Int {
            switch self {
            case .depth:
                return 1 << 0
            case .stencil:
                return 1 << 1
            case .color(let index):
                return 1 << 2 &+ index
            }
        }
    }
    
    let drawRenderPass : DrawRenderPass
    
    @usableFromInline
    var boundVertexBuffers = [ResourceUsageNodePtr?](repeating: nil, count: 8)
    @usableFromInline
    var renderTargetAttachmentUsages : HashMap<Attachment, ResourceUsageNodePtr>
    
    var renderPipelineDescriptor : RenderPipelineDescriptor? = nil
    var depthStencilDescriptor : DepthStencilDescriptor? = nil
    
    @usableFromInline
    var gpuCommandsStartIndexColor : Int? = nil
    @usableFromInline
    var gpuCommandsStartIndexDepthStencil : Int? = nil

    init(commandRecorder: FrameGraphCommandRecorder, resourceUsages: ResourceUsages, renderPass: DrawRenderPass, passRecord: RenderPassRecord) {
        self.drawRenderPass = renderPass
        self.renderTargetAttachmentUsages = HashMap(allocator: AllocatorType(commandRecorder.renderPassScratchAllocator))
        
        super.init(commandRecorder: commandRecorder, resourceUsages: resourceUsages, passRecord: passRecord)
        
        assert(passRecord.pass === renderPass)
        
        var needsClearCommand = false
        
        for (i, attachment) in renderPass.renderTargetDescriptor.colorAttachments.enumerated() {
            guard let attachment = attachment else { continue }
            self.resourceUsages.registerResource(Resource(attachment.texture))
            
            needsClearCommand = needsClearCommand || attachment.wantsClear
            let usageNode = self.resourceUsages.resourceUsageNode(for: attachment.texture.handle, encoder: self, usageType: attachment.wantsClear ? .writeOnlyRenderTarget : .unusedRenderTarget, stages: .fragment, inArgumentBuffer: false, firstCommandOffset: 0)
            self.renderTargetAttachmentUsages[.color(i)] = usageNode
        }
        
        if let depthAttachment = renderPass.renderTargetDescriptor.depthAttachment {
            self.resourceUsages.registerResource(Resource(depthAttachment.texture))
            
            needsClearCommand = needsClearCommand || depthAttachment.wantsClear
            let usageNode = self.resourceUsages.resourceUsageNode(for: depthAttachment.texture.handle, encoder: self, usageType: depthAttachment.wantsClear ? .writeOnlyRenderTarget : .unusedRenderTarget, stages: .vertex, inArgumentBuffer: false, firstCommandOffset: 0)
            self.renderTargetAttachmentUsages[.depth] = usageNode
        }
        
        if let stencilAttachment = renderPass.renderTargetDescriptor.stencilAttachment {
            self.resourceUsages.registerResource(Resource(stencilAttachment.texture))
            
            needsClearCommand = needsClearCommand || stencilAttachment.wantsClear
            let usageNode = self.resourceUsages.resourceUsageNode(for: stencilAttachment.texture.handle, encoder: self, usageType: stencilAttachment.wantsClear ? .writeOnlyRenderTarget : .unusedRenderTarget, stages: .vertex, inArgumentBuffer: false, firstCommandOffset: 0)
            self.renderTargetAttachmentUsages[.stencil] = usageNode
        }
        
        if needsClearCommand {
            // Insert a dummy command into the stream.
            // This is necessary since clearing a render target has effects that can be depended upon by later passes,
            // even when there are no other commands for the encoder.
            // Not having any commands breaks the fence/hazard management in the backends, so insert one here.
            self.commandRecorder.record(.clearRenderTargets)
        }
    }
    
    deinit {
        self.renderTargetAttachmentUsages.deinit()
    }
    
    @usableFromInline
    func updateColorAttachmentUsages(endingEncoding: Bool) {
        guard let gpuCommandsStartIndex = self.gpuCommandsStartIndexColor else {
            return
        }
        self.gpuCommandsStartIndexColor = nil
        
        guard let renderPipelineDescriptor = self.renderPipelineDescriptor else {
            assertionFailure("No render pipeline descriptor bound.")
            return
        }
        
        for (i, attachment) in drawRenderPass.renderTargetDescriptor.colorAttachments.enumerated() {
            guard let attachment = attachment else { continue }
            
            if endingEncoding, let resolveTexture = attachment.resolveTexture {
                self.resourceUsages.registerResource(Resource(resolveTexture))
                let _ = self.resourceUsages.resourceUsageNode(for: resolveTexture.handle, encoder: self, usageType: .writeOnlyRenderTarget, stages: .fragment, inArgumentBuffer: false, firstCommandOffset: self.lastGPUCommandIndex)
            }
        
            guard renderPipelineDescriptor.writeMasks[i, default: []] != [] else {
                continue
            }
            
            let type : ResourceUsageType = renderPipelineDescriptor.blendStates[i] != nil ? .readWriteRenderTarget : .writeOnlyRenderTarget
            
            if let usageNode = self.renderTargetAttachmentUsages[.color(i)] {
                switch (type, usageNode.pointee.element.type) {
                case (.readWriteRenderTarget, _):
                    usageNode.pointee.element.type = .readWriteRenderTarget
                case (_, .unusedRenderTarget):
                    usageNode.pointee.element.type = type
                default:
                    break // No change necessary.
                }
                usageNode.pointee.element.commandRangeInPass = Range(usageNode.pointee.element.commandRangeInPass.lowerBound...self.lastGPUCommandIndex) // extend the usage's timeline
                continue
            }
            
            let usageNode = self.resourceUsages.resourceUsageNode(for: attachment.texture.handle, encoder: self, usageType: type, stages: .fragment, inArgumentBuffer: false, firstCommandOffset: gpuCommandsStartIndex)
            usageNode.pointee.element.commandRangeInPass = Range(gpuCommandsStartIndex...self.lastGPUCommandIndex)
            self.renderTargetAttachmentUsages[.color(i)] = usageNode
        }
    }
    
    @usableFromInline
    func updateDepthStencilAttachmentUsages(endingEncoding: Bool) {
        guard let gpuCommandsStartIndex = self.gpuCommandsStartIndexDepthStencil else {
            return
        }
        self.gpuCommandsStartIndexDepthStencil = nil
        
        guard let depthStencilDescriptor = self.depthStencilDescriptor else {
            return // No depth writes enabled, depth test always passes, no stencil tests.
        }
        
        depthCheck: if let depthAttachment = drawRenderPass.renderTargetDescriptor.depthAttachment {
            let type : ResourceUsageType
            switch (depthStencilDescriptor.depthCompareFunction, depthStencilDescriptor.isDepthWriteEnabled) {
            case (.always, false):
                break depthCheck
            case (.always, true):
                type = .writeOnlyRenderTarget
            default:
                type = .readWriteRenderTarget // TODO: should we have a special readOnlyRenderTarget for e.g. depth writes disabled but depth comparison on?
            }
            
            if let usageNode = self.renderTargetAttachmentUsages[.depth] {
                switch (type, usageNode.pointee.element.type) {
                case (.readWriteRenderTarget, _):
                    usageNode.pointee.element.type = .readWriteRenderTarget
                case (_, .unusedRenderTarget):
                    usageNode.pointee.element.type = .writeOnlyRenderTarget
                default:
                    break // No change necessary.
                }
                usageNode.pointee.element.commandRangeInPass = Range(usageNode.pointee.element.commandRangeInPass.lowerBound...self.lastGPUCommandIndex) // extend the usage's timeline
                break depthCheck
            }
            
            let usageNode = self.resourceUsages.resourceUsageNode(for: depthAttachment.texture.handle, encoder: self, usageType: type, stages: .vertex, inArgumentBuffer: false, firstCommandOffset: gpuCommandsStartIndex)
            usageNode.pointee.element.commandRangeInPass = Range(gpuCommandsStartIndex...self.lastGPUCommandIndex)
            self.renderTargetAttachmentUsages[.depth] = usageNode
            
            if endingEncoding, let resolveTexture = depthAttachment.resolveTexture {
                self.resourceUsages.registerResource(Resource(resolveTexture))
                let _ = self.resourceUsages.resourceUsageNode(for: resolveTexture.handle, encoder: self, usageType: .writeOnlyRenderTarget, stages: .fragment, inArgumentBuffer: false, firstCommandOffset: self.lastGPUCommandIndex)
            }
        }
        
        stencilCheck: if let stencilAttachment = drawRenderPass.renderTargetDescriptor.stencilAttachment {
            let isRead = depthStencilDescriptor.backFaceStencil.stencilCompareFunction != .always || depthStencilDescriptor.frontFaceStencil.stencilCompareFunction != .always
            let isWrite =   depthStencilDescriptor.backFaceStencil.stencilFailureOperation != .keep ||
                            depthStencilDescriptor.backFaceStencil.depthFailureOperation != .keep ||
                            depthStencilDescriptor.backFaceStencil.depthStencilPassOperation != .keep ||
                            depthStencilDescriptor.frontFaceStencil.stencilFailureOperation != .keep ||
                            depthStencilDescriptor.frontFaceStencil.depthFailureOperation != .keep ||
                            depthStencilDescriptor.frontFaceStencil.depthStencilPassOperation != .keep
            
            guard isRead || isWrite else { break stencilCheck }
            
            let type : ResourceUsageType = isRead ? .readWriteRenderTarget : .writeOnlyRenderTarget
            
            if let usageNode = self.renderTargetAttachmentUsages[.stencil] {
                switch (type, usageNode.pointee.element.type) {
                case (.readWriteRenderTarget, _):
                    usageNode.pointee.element.type = .readWriteRenderTarget
                case (_, .unusedRenderTarget):
                    usageNode.pointee.element.type = .writeOnlyRenderTarget
                default:
                    break // No change necessary.
                }
                usageNode.pointee.element.commandRangeInPass = Range(usageNode.pointee.element.commandRangeInPass.lowerBound...self.lastGPUCommandIndex) // extend the usage's timeline
                break stencilCheck
            }
            
            let usageNode = self.resourceUsages.resourceUsageNode(for: stencilAttachment.texture.handle, encoder: self, usageType: type, stages: .vertex, inArgumentBuffer: false, firstCommandOffset: gpuCommandsStartIndex)
            usageNode.pointee.element.commandRangeInPass = Range(gpuCommandsStartIndex...self.lastGPUCommandIndex)
            self.renderTargetAttachmentUsages[.stencil] = usageNode
            
            if endingEncoding, let resolveTexture = stencilAttachment.resolveTexture {
                self.resourceUsages.registerResource(Resource(resolveTexture))
                let _ = self.resourceUsages.resourceUsageNode(for: resolveTexture.handle, encoder: self, usageType: .writeOnlyRenderTarget, stages: .fragment, inArgumentBuffer: false, firstCommandOffset: self.lastGPUCommandIndex)
            }
        }
    }
    
    public var label : String = "" {
        didSet {
            commandRecorder.setLabel(label)
        }
    }
    
    public func setRenderPipelineDescriptor(_ descriptor: RenderPipelineDescriptor, retainExistingBindings: Bool = true) {
        if !retainExistingBindings {
            self.resetAllBindings()
        }
        
        self.renderPipelineDescriptor = descriptor
        self.currentPipelineReflection = RenderBackend.renderPipelineReflection(descriptor: descriptor, renderTarget: self.drawRenderPass.renderTargetDescriptor)
        
        self.pipelineStateChanged = true
        self.needsUpdateBindings = true
        
        self.updateColorAttachmentUsages(endingEncoding: false)
    }
    
    public func setVertexBuffer(_ buffer: Buffer?, offset: Int, index: Int) {
        if let currentBinding = self.boundVertexBuffers[index] {
            let lowerBound = currentBinding.pointee.element.commandRangeInPass.lowerBound
            // In normal execution, the last GPU command index should always be at least lowerBound.
            // However, if we don't have a valid pipeline state, it's possible that no GPU commands get executed;
            // in that case, we use max(lowerBound, self.lastGPUCommandIndex) to prevent the Swift stdlib from asserting.
            currentBinding.pointee.element.commandRangeInPass = Range(lowerBound...max(lowerBound, self.lastGPUCommandIndex))
        }
        
        guard let buffer = buffer else { return }
        
        self.resourceUsages.registerResource(Resource(buffer))
        let newUsageNode = self.resourceUsages.resourceUsageNode(for: buffer.handle, encoder: self, usageType: .vertexBuffer, stages: .vertex, inArgumentBuffer: false, firstCommandOffset: self.nextCommandOffset)
        self.boundVertexBuffers[index] = newUsageNode
        
        commandRecorder.record(FrameGraphCommand.setVertexBuffer, (buffer, UInt32(offset), UInt32(index)))
    }
    
    public func setVertexBufferOffset(_ offset: Int, index: Int) {
        commandRecorder.record(FrameGraphCommand.setVertexBufferOffset(offset: UInt32(offset), index: UInt32(index)))
    }

    public func setViewport(_ viewport: Viewport) {
        commandRecorder.record(FrameGraphCommand.setViewport, viewport)
    }
    
    public func setFrontFacing(_ frontFacingWinding: Winding) {
        commandRecorder.record(.setFrontFacing(frontFacingWinding))
    }
    
    public func setCullMode(_ cullMode: CullMode) {
        commandRecorder.record(.setCullMode(cullMode))
    }
    
    public func setTriangleFillMode(_ fillMode: TriangleFillMode) {
        commandRecorder.record(.setTriangleFillMode(fillMode))
    }
    
    public func setDepthStencilDescriptor(_ descriptor: DepthStencilDescriptor?) {
        guard self.drawRenderPass.renderTargetDescriptor.depthAttachment != nil ||
            self.drawRenderPass.renderTargetDescriptor.stencilAttachment != nil else {
                return
        }
        
        let descriptor = descriptor ?? DepthStencilDescriptor()
        
        self.depthStencilDescriptor = descriptor
        self.depthStencilStateChanged = true
        
        self.updateDepthStencilAttachmentUsages(endingEncoding: false)
    }
    
//    @inlinable
    public func setScissorRect(_ rect: ScissorRect) {
        commandRecorder.record(FrameGraphCommand.setScissorRect, rect)
    }
    
    public func setDepthClipMode(_ depthClipMode: DepthClipMode) {
        commandRecorder.record(.setDepthClipMode(depthClipMode))
    }
    
    public func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float) {
        commandRecorder.record(FrameGraphCommand.setDepthBias, (depthBias, slopeScale, clamp))
    }
    
    public func setStencilReferenceValue(_ referenceValue: UInt32) {
        commandRecorder.record(.setStencilReferenceValue(referenceValue))
    }
    
    public func setStencilReferenceValues(front frontReferenceValue: UInt32, back backReferenceValue: UInt32) {
        commandRecorder.record(.setStencilReferenceValues(front: frontReferenceValue, back: backReferenceValue))
    }
    
    public func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int = 1, baseInstance: Int = 0) {
        assert(instanceCount > 0, "instanceCount(\(instanceCount)) must be non-zero.")

        guard self.currentPipelineReflection != nil else {
            assert(self.renderPipelineDescriptor != nil, "No render or compute pipeline is set for pass \(renderPass.name).")
            return
        }

        self.updateResourceUsages()
        self.lastGPUCommandIndex = self.nextCommandOffset
        
        self.gpuCommandsStartIndexColor = self.gpuCommandsStartIndexColor ?? self.nextCommandOffset
        self.gpuCommandsStartIndexDepthStencil = self.gpuCommandsStartIndexDepthStencil ?? self.nextCommandOffset
        
        commandRecorder.record(FrameGraphCommand.drawPrimitives, (primitiveType, UInt32(vertexStart), UInt32(vertexCount), UInt32(instanceCount), UInt32(baseInstance)))
    }
    
    public func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int = 1, baseVertex: Int = 0, baseInstance: Int = 0) {
        assert(instanceCount > 0, "instanceCount(\(instanceCount)) must be non-zero.")
        
        guard self.currentPipelineReflection != nil else {
            assert(self.renderPipelineDescriptor != nil, "No render or compute pipeline is set for pass \(renderPass.name).")
            return
        }

        self.updateResourceUsages()
        self.lastGPUCommandIndex = self.nextCommandOffset
        
        self.gpuCommandsStartIndexColor = self.gpuCommandsStartIndexColor ?? self.nextCommandOffset
        self.gpuCommandsStartIndexDepthStencil = self.gpuCommandsStartIndexDepthStencil ?? self.nextCommandOffset
        self.resourceUsages.addResourceUsage(for: indexBuffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .indexBuffer, stages: .vertex, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.drawIndexedPrimitives, (primitiveType, UInt32(indexCount), indexType, indexBuffer, UInt32(indexBufferOffset), UInt32(instanceCount), Int32(baseVertex), UInt32(baseInstance)))
    }
    
    public override func updateResourceUsages(endingEncoding: Bool = false) {
        if !endingEncoding {
            // Set the depth-stencil and pipeline states here to filter out unused states.
            if self.depthStencilStateChanged {
                let box = Unmanaged.passRetained(ReferenceBox(self.depthStencilDescriptor!))
                commandRecorder.unmanagedReferences.append(box)
                commandRecorder.record(FrameGraphCommand.setDepthStencilDescriptor(box))
                self.depthStencilStateChanged = false
            }
            
            if self.pipelineStateChanged {
                let box = Unmanaged.passRetained(ReferenceBox(self.renderPipelineDescriptor!))
                commandRecorder.unmanagedReferences.append(box)
                commandRecorder.record(FrameGraphCommand.setRenderPipelineDescriptor(box))
                // self.pipelineStateChanged = false // set by super.updateResourceUsages
            }
        }
        
        super.updateResourceUsages(endingEncoding: endingEncoding)
        
        if endingEncoding {
            for usageNode in self.boundVertexBuffers {
                guard let usageNode = usageNode else { continue }
                if self.lastGPUCommandIndex > usageNode.pointee.element.commandRangeInPass.lowerBound {
                    usageNode.pointee.element.commandRangeInPass = Range(usageNode.pointee.element.commandRangeInPass.lowerBound...self.lastGPUCommandIndex)
                }
            }
            
            self.updateColorAttachmentUsages(endingEncoding: endingEncoding)
            self.updateDepthStencilAttachmentUsages(endingEncoding: endingEncoding)
        }
    }
}


public final class ComputeCommandEncoder : ResourceBindingEncoder {
    
    let computeRenderPass : ComputeRenderPass
    
    private var currentComputePipeline : ComputePipelineDescriptorBox? = nil
    private var currentThreadExecutionWidth : Int = 0
    
    init(commandRecorder: FrameGraphCommandRecorder, resourceUsages: ResourceUsages, renderPass: ComputeRenderPass, passRecord: RenderPassRecord) {
        self.computeRenderPass = renderPass
        super.init(commandRecorder: commandRecorder, resourceUsages: resourceUsages, passRecord: passRecord)
        
        assert(passRecord.pass === renderPass)
    }
    
    public var label : String = "" {
        didSet {
            commandRecorder.setLabel(label)
        }
    }
    
    public func setComputePipelineDescriptor(_ descriptor: ComputePipelineDescriptor, retainExistingBindings: Bool = true) {
        if !retainExistingBindings {
            self.resetAllBindings()
        }
        
        self.currentPipelineReflection = RenderBackend.computePipelineReflection(descriptor: descriptor)
        
        self.pipelineStateChanged = true
        self.needsUpdateBindings = true
        
        self.currentThreadExecutionWidth = RenderBackend.threadExecutionWidth

        let pipelineBox = ComputePipelineDescriptorBox(descriptor)
        self.currentComputePipeline = pipelineBox
        
        let box = Unmanaged.passRetained(pipelineBox)
        commandRecorder.unmanagedReferences.append(box)
        commandRecorder.record(.setComputePipelineDescriptor(box))
    }
    
    public func setStageInRegion(_ region: Region) {
        commandRecorder.record(FrameGraphCommand.setStageInRegion, region)
    }
    
    public func setThreadgroupMemoryLength(_ length: Int, index: Int) {
        commandRecorder.record(.setThreadgroupMemoryLength(length: UInt32(length), index: UInt32(index)))
    }
    
    @usableFromInline
    func updateThreadgroupExecutionWidth(threadsPerThreadgroup: Size) {
        let threads = threadsPerThreadgroup.width * threadsPerThreadgroup.height * threadsPerThreadgroup.depth
        let isMultiple = threads % self.currentThreadExecutionWidth == 0
        self.currentComputePipeline!.threadGroupSizeIsMultipleOfThreadExecutionWidth = self.currentComputePipeline!.threadGroupSizeIsMultipleOfThreadExecutionWidth && isMultiple
    }

    public func dispatchThreads(_ threadsPerGrid: Size, threadsPerThreadgroup: Size) {
        guard self.currentPipelineReflection != nil else {
            assert(self.currentComputePipeline != nil, "No compute pipeline is set for pass \(renderPass.name).")
            return
        }

        self.updateThreadgroupExecutionWidth(threadsPerThreadgroup: threadsPerThreadgroup)
        self.updateResourceUsages()
        self.lastGPUCommandIndex = self.nextCommandOffset
        
        commandRecorder.record(FrameGraphCommand.dispatchThreads, (threadsPerGrid, threadsPerThreadgroup))
    }
    
    public func dispatchThreadgroups(_ threadgroupsPerGrid: Size, threadsPerThreadgroup: Size) {
        guard self.currentPipelineReflection != nil else {
            assert(self.currentComputePipeline != nil, "No compute pipeline is set for pass \(renderPass.name).")
            return
        }

        self.updateThreadgroupExecutionWidth(threadsPerThreadgroup: threadsPerThreadgroup)
        self.updateResourceUsages()
        self.lastGPUCommandIndex = self.nextCommandOffset
        
        commandRecorder.record(FrameGraphCommand.dispatchThreadgroups, (threadgroupsPerGrid, threadsPerThreadgroup))
    }
    
    public func dispatchThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size) {
        guard self.currentPipelineReflection != nil else {
            assert(self.currentComputePipeline != nil, "No compute pipeline is set for pass \(renderPass.name).")
            return
        }

        self.updateThreadgroupExecutionWidth(threadsPerThreadgroup: threadsPerThreadgroup)
        self.updateResourceUsages()
        self.lastGPUCommandIndex = self.nextCommandOffset
        
        self.resourceUsages.addResourceUsage(for: indirectBuffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .indirectBuffer, stages: .compute, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.dispatchThreadgroupsIndirect, (indirectBuffer, UInt32(indirectBufferOffset), threadsPerThreadgroup))
    }
}

public final class BlitCommandEncoder : CommandEncoder {

    public let commandRecorder : FrameGraphCommandRecorder
    public let passRecord: RenderPassRecord
    public let startCommandIndex: Int
    public let resourceUsages : ResourceUsages
    let blitRenderPass : BlitRenderPass
    
    init(commandRecorder: FrameGraphCommandRecorder, resourceUsages: ResourceUsages, renderPass: BlitRenderPass, passRecord: RenderPassRecord) {
        self.commandRecorder = commandRecorder
        self.resourceUsages = resourceUsages
        self.blitRenderPass = renderPass
        self.passRecord = passRecord
        self.startCommandIndex = self.commandRecorder.nextCommandIndex
        
        assert(passRecord.pass === renderPass)
        
        self.pushDebugGroup(passRecord.pass.name)
    }
    
    public func endEncoding() {
        self.popDebugGroup() // Pass Name
    }
    
    public var label : String = "" {
        didSet {
            commandRecorder.setLabel(label)
        }
    }
    
    public func copy(from sourceBuffer: Buffer, sourceOffset: Int, sourceBytesPerRow: Int, sourceBytesPerImage: Int, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin, options: BlitOption = []) {
        let commandOffset = self.nextCommandOffset
        
        resourceUsages.addResourceUsage(for: sourceBuffer, commandIndex: commandOffset, encoder: self, usageType: .blitSource, stages: .blit, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: destinationTexture, commandIndex: commandOffset, encoder: self, usageType: .blitDestination, stages: .blit, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.copyBufferToTexture, (sourceBuffer, UInt32(sourceOffset), UInt32(sourceBytesPerRow), UInt32(sourceBytesPerImage), sourceSize, destinationTexture, UInt32(destinationSlice), UInt32(destinationLevel), destinationOrigin, options))
    }
    
    public func copy(from sourceBuffer: Buffer, sourceOffset: Int, to destinationBuffer: Buffer, destinationOffset: Int, size: Int) {
        let commandOffset = self.nextCommandOffset
        
        resourceUsages.addResourceUsage(for: sourceBuffer, commandIndex: commandOffset, encoder: self, usageType: .blitSource, stages: .blit, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: destinationBuffer, commandIndex: commandOffset, encoder: self, usageType: .blitDestination, stages: .blit, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.copyBufferToBuffer, (sourceBuffer, UInt32(sourceOffset), destinationBuffer, UInt32(destinationOffset), UInt32(size)))
    }
    
    public func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationBuffer: Buffer, destinationOffset: Int, destinationBytesPerRow: Int, destinationBytesPerImage: Int, options: BlitOption = []) {
        let commandOffset = self.nextCommandOffset
        
        resourceUsages.addResourceUsage(for: sourceTexture, commandIndex: commandOffset, encoder: self, usageType: .blitSource, stages: .blit, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: destinationBuffer, commandIndex: commandOffset, encoder: self, usageType: .blitDestination, stages: .blit, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.copyTextureToBuffer, (sourceTexture, UInt32(sourceSlice), UInt32(sourceLevel), sourceOrigin, sourceSize, destinationBuffer, UInt32(destinationOffset), UInt32(destinationBytesPerRow), UInt32(destinationBytesPerImage), options))
    }
    
    public func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin) {
        let commandOffset = self.nextCommandOffset
        
        resourceUsages.addResourceUsage(for: sourceTexture, commandIndex: commandOffset, encoder: self, usageType: .blitSource, stages: .blit, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: destinationTexture, commandIndex: commandOffset, encoder: self, usageType: .blitDestination, stages: .blit, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.copyTextureToTexture, (sourceTexture, UInt32(sourceSlice), UInt32(sourceLevel), sourceOrigin, sourceSize, destinationTexture, UInt32(destinationSlice), UInt32(destinationLevel), destinationOrigin))
    }
    
    public func fill(buffer: Buffer, range: Range<Int>, value: UInt8) {
        resourceUsages.addResourceUsage(for: buffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitDestination, stages: .blit, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.fillBuffer, (buffer, range, value))
    }
    
    public func generateMipmaps(for texture: Texture) {
        resourceUsages.addResourceUsage(for: texture, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitSynchronisation, stages: .blit, inArgumentBuffer: false)
        
        commandRecorder.record(.generateMipmaps(texture))
    }
    
    public func synchronize(buffer: Buffer) {
        resourceUsages.addResourceUsage(for: buffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitSynchronisation, stages: .blit, inArgumentBuffer: false)
        
        commandRecorder.record(.synchroniseBuffer(buffer))
    }
    
    public func synchronize(texture: Texture) {
        resourceUsages.addResourceUsage(for: texture, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitSynchronisation, stages: .blit, inArgumentBuffer: false)
        commandRecorder.record(.synchroniseTexture(texture))
    }
    
    public func synchronize(texture: Texture, slice: Int, level: Int) {
        resourceUsages.addResourceUsage(for: texture, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitSynchronisation, stages: .blit, inArgumentBuffer: false)
        commandRecorder.record(FrameGraphCommand.synchroniseTextureSlice, (texture, UInt32(slice), UInt32(level)))
    }
}

public final class ExternalCommandEncoder : CommandEncoder {
    
    public let commandRecorder : FrameGraphCommandRecorder
    public let passRecord: RenderPassRecord
    public let startCommandIndex: Int
    public let resourceUsages : ResourceUsages
    let externalRenderPass : ExternalRenderPass
    
    init(commandRecorder: FrameGraphCommandRecorder, resourceUsages: ResourceUsages, renderPass: ExternalRenderPass, passRecord: RenderPassRecord) {
        self.commandRecorder = commandRecorder
        self.resourceUsages = resourceUsages
        self.externalRenderPass = renderPass
        self.passRecord = passRecord
        self.startCommandIndex = self.commandRecorder.nextCommandIndex
        
        assert(passRecord.pass === renderPass)
        
        self.pushDebugGroup(passRecord.pass.name)
    }
    
    public func endEncoding() {
        self.popDebugGroup() // Pass Name
    }
    
    public var label : String = "" {
        didSet {
            commandRecorder.setLabel(label)
        }
    }
    
    #if canImport(MetalPerformanceShaders)
    
    @available(OSX 10.14, *)
    public func encodeRayIntersection(intersector: MPSRayIntersector, intersectionType: MPSIntersectionType, rayBuffer: Buffer, rayBufferOffset: Int, intersectionBuffer: Buffer, intersectionBufferOffset: Int, rayCount: Int, accelerationStructure: MPSAccelerationStructure) {
        
        let intersector = Unmanaged.passRetained(intersector)
        self.commandRecorder.unmanagedReferences.append(intersector)
        
        let accelerationStructure = Unmanaged.passRetained(accelerationStructure)
        self.commandRecorder.unmanagedReferences.append(accelerationStructure)
        
        resourceUsages.addResourceUsage(for: rayBuffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .read, stages: .compute, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: intersectionBuffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .write, stages: .compute, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.encodeRayIntersection, (intersector, intersectionType, rayBuffer, rayBufferOffset, intersectionBuffer, intersectionBufferOffset, rayCount, accelerationStructure))
    }
    
    @available(OSX 10.14, *)
    public func encodeRayIntersection(intersector: MPSRayIntersector, intersectionType: MPSIntersectionType, rayBuffer: Buffer, rayBufferOffset: Int, intersectionBuffer: Buffer, intersectionBufferOffset: Int, rayCountBuffer: Buffer, rayCountBufferOffset: Int, accelerationStructure: MPSAccelerationStructure) {
        
        let intersector = Unmanaged.passRetained(intersector)
        self.commandRecorder.unmanagedReferences.append(intersector)
        
        let accelerationStructure = Unmanaged.passRetained(accelerationStructure)
        self.commandRecorder.unmanagedReferences.append(accelerationStructure)
        
        resourceUsages.addResourceUsage(for: rayBuffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .read, stages: .compute, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: intersectionBuffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .write, stages: .compute, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: rayCountBuffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .read, stages: .compute, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.encodeRayIntersectionRayCountBuffer, (intersector, intersectionType, rayBuffer, rayBufferOffset, intersectionBuffer, intersectionBufferOffset, rayCountBuffer, rayCountBufferOffset, accelerationStructure))
    }
    
    #endif
}
