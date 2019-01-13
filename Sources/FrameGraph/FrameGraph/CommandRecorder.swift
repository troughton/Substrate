//
//  LazyFrameGraph.swift
//  FrameGraph
//
//  Created by Thomas Roughton on 16/12/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

import Utilities
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
    
    public typealias SetBufferArgs = (bindingPath: ResourceBindingPath, handle: Buffer.Handle, offset: UInt32, hasDynamicOffset: Bool)
    case setBuffer(UnsafePointer<SetBufferArgs>)
    
    public typealias SetBufferOffsetArgs = (bindingPath: ResourceBindingPath, handle: Buffer.Handle?, offset: UInt32)
    case setBufferOffset(UnsafePointer<SetBufferOffsetArgs>)
    
    public typealias SetTextureArgs = (bindingPath: ResourceBindingPath, handle: Texture.Handle)
    case setTexture(UnsafePointer<SetTextureArgs>)
    
    public typealias SetSamplerStateArgs = (bindingPath: ResourceBindingPath, descriptor: SamplerDescriptor)
    case setSamplerState(UnsafePointer<SetSamplerStateArgs>)
    
    public typealias SetArgumentBufferArgs = (bindingPath: ResourceBindingPath, argumentBuffer: ArgumentBuffer)
    case setArgumentBuffer(UnsafePointer<SetArgumentBufferArgs>)
    
    public typealias SetArgumentBufferArrayArgs = (bindingPath: ResourceBindingPath, argumentBuffer: ArgumentBufferArray, isBound: Bool)
    case setArgumentBufferArray(UnsafePointer<SetArgumentBufferArrayArgs>)
    
    // Render
    
    case clearRenderTargets
    
    public typealias SetVertexBufferArgs = (handle: Buffer.Handle?, offset: UInt32, index: UInt32)
    case setVertexBuffer(UnsafePointer<SetVertexBufferArgs>)
    
    case setVertexBufferOffset(offset: UInt32, index: UInt32)
    
    case setRenderPipelineDescriptor(Unmanaged<ReferenceBox<RenderPipelineDescriptor>>)
    
    public typealias DrawPrimitivesArgs = (primitiveType: PrimitiveType, vertexStart: UInt32, vertexCount: UInt32, instanceCount: UInt32, baseInstance: UInt32)
    case drawPrimitives(UnsafePointer<DrawPrimitivesArgs>)
    
    public typealias DrawIndexedPrimitivesArgs = (primitiveType: PrimitiveType, indexCount: UInt32, indexType: IndexType, indexBuffer: Buffer.Handle, indexBufferOffset: UInt32, instanceCount: UInt32, baseVertex: Int32, baseInstance: UInt32)
    case drawIndexedPrimitives(UnsafePointer<DrawIndexedPrimitivesArgs>)
    
    case setViewport(UnsafePointer<Viewport>)
    
    case setFrontFacing(Winding)
    
    case setCullMode(CullMode)
    
    case setTriangleFillMode(TriangleFillMode)
    
    case setDepthStencilDescriptor(Unmanaged<ReferenceBox<DepthStencilDescriptor?>>)
    
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
    
    public typealias DispatchThreadgroupsIndirectArgs = (indirectBuffer: Buffer.Handle, indirectBufferOffset: UInt32, threadsPerThreadgroup: Size)
    case dispatchThreadgroupsIndirect(UnsafePointer<DispatchThreadgroupsIndirectArgs>)
    
    case setComputePipelineDescriptor(Unmanaged<ComputePipelineDescriptorBox>)
    
    case setStageInRegion(UnsafePointer<Region>)
    
    case setThreadgroupMemoryLength(length: UInt32, index: UInt32)
    
    
    // Blit
    
    public typealias CopyBufferToTextureArgs = (sourceBuffer: Buffer.Handle, sourceOffset: UInt32, sourceBytesPerRow: UInt32, sourceBytesPerImage: UInt32, sourceSize: Size, destinationTexture: Texture.Handle, destinationSlice: UInt32, destinationLevel: UInt32, destinationOrigin: Origin, options: BlitOption)
    case copyBufferToTexture(UnsafePointer<CopyBufferToTextureArgs>)
    
    public typealias CopyBufferToBufferArgs = (sourceBuffer: Buffer.Handle, sourceOffset: UInt32, destinationBuffer: Buffer.Handle, destinationOffset: UInt32, size: UInt32)
    case copyBufferToBuffer(UnsafePointer<CopyBufferToBufferArgs>)
    
    public typealias CopyTextureToBufferArgs = (sourceTexture: Texture.Handle, sourceSlice: UInt32, sourceLevel: UInt32, sourceOrigin: Origin, sourceSize: Size, destinationBuffer: Buffer.Handle, destinationOffset: UInt32, destinationBytesPerRow: UInt32, destinationBytesPerImage: UInt32, options: BlitOption)
    case copyTextureToBuffer(UnsafePointer<CopyTextureToBufferArgs>)
    
    public typealias CopyTextureToTextureArgs = (sourceTexture: Texture.Handle, sourceSlice: UInt32, sourceLevel: UInt32, sourceOrigin: Origin, sourceSize: Size, destinationTexture: Texture.Handle, destinationSlice: UInt32, destinationLevel: UInt32, destinationOrigin: Origin)
    case copyTextureToTexture(UnsafePointer<CopyTextureToTextureArgs>)
    
    public typealias FillBufferArgs = (buffer: Buffer.Handle, range: Range<Int>, value: UInt8)
    case fillBuffer(UnsafePointer<FillBufferArgs>)
    
    case generateMipmaps(Texture.Handle)
    
    case synchroniseTexture(Texture.Handle)
    
    public typealias SynchroniseTextureArgs = (texture: Texture.Handle, slice: UInt32, level: UInt32)
    case synchroniseTextureSlice(UnsafePointer<SynchroniseTextureArgs>)
    
    case synchroniseBuffer(Buffer.Handle)
    
    // External:
    
    #if canImport(MetalPerformanceShaders)
    
    @available(OSX 10.14, *)
    public typealias EncodeRayIntersectionArgs = (intersector: Unmanaged<MPSRayIntersector>, intersectionType: MPSIntersectionType, rayBuffer: Buffer.Handle, rayBufferOffset: Int, intersectionBuffer: Buffer.Handle, intersectionBufferOffset: Int, rayCount: Int, accelerationStructure: Unmanaged<MPSAccelerationStructure>)
    @available(OSX 10.14, *)
    case encodeRayIntersection(UnsafePointer<EncodeRayIntersectionArgs>)
    
    @available(OSX 10.14, *)
    public typealias EncodeRayIntersectionRayCountBufferArgs = (intersector: Unmanaged<MPSRayIntersector>, intersectionType: MPSIntersectionType, rayBuffer: Buffer.Handle, rayBufferOffset: Int, intersectionBuffer: Buffer.Handle, intersectionBufferOffset: Int, rayCountBuffer: Buffer.Handle, rayCountBufferOffset: Int, accelerationStructure: Unmanaged<MPSAccelerationStructure>)
    @available(OSX 10.14, *)
    case encodeRayIntersectionRayCountBuffer(UnsafePointer<EncodeRayIntersectionRayCountBufferArgs>)
    
    #endif
}


@_fixed_layout
public final class FrameGraphCommandRecorder {
    public let commmandEncoderTemporaryArena = MemoryArena()
    public let commands = ExpandingBuffer<FrameGraphCommand>()
    public let dataArena = MemoryArena()
    @usableFromInline
    let unmanagedReferences = ExpandingBuffer<Releasable>()
    
    @inlinable
    init() {
        
    }
    
    @inlinable
    public var nextCommandIndex : Int {
        return self.commands.count
    }
    
    public func reset() {
        commands.removeAll()
        dataArena.reset()
        
        for reference in unmanagedReferences {
            reference.release()
        }
        self.unmanagedReferences.removeAll()
        
        self.commmandEncoderTemporaryArena.reset()
    }
    
    @inlinable
    public func copyData<T>(_ data: T) -> UnsafePointer<T> {
        let result = self.dataArena.allocate() as UnsafeMutablePointer<T>
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
            let destination : UnsafeMutablePointer<CChar> = self.dataArena.allocate(count: numChars + 1)
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
        let newBytes = self.dataArena.allocate(bytes: length, alignedTo: 16)
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
    var unmanagedPassRecord : Unmanaged<RenderPassRecord> { get }
    
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
    
    @inlinable
    public var unmanagedPassRecord : Unmanaged<RenderPassRecord> {
        return Unmanaged.passUnretained(self.passRecord)
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

struct ResourceBinding {
    enum ResourceBindingType {
        case bytes(UnsafeRawPointer, length: Int)
        case buffer(ObjectIdentifier, offset: Int)
        case texture(ObjectIdentifier)
        case sampler(UnsafePointer<SamplerDescriptor>)
    }
    
    var type : ResourceBindingType
    var stage : RenderStages
}

struct BoundResource {
    var usageNode : ResourceUsageNodePtr
    var resource : ObjectIdentifier
    var bufferOffset : Int
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

@_fixed_layout
public class ResourceBindingEncoder : CommandEncoder {
    
    @_fixed_layout
    public struct BoundResource : Equatable {
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
    
    public enum ArgumentBufferType {
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
    let pendingArgumentBuffers : ExpandingBuffer<(FunctionArgumentKey, ArgumentBuffer, type: ArgumentBufferType, assumeConsistentUsage: Bool)>
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
    }
    
    @usableFromInline
    var lastGPUCommandIndex = 0
    
    @usableFromInline
    var needsUpdateBindings = false
    @usableFromInline
    var pipelineStateChanged = false
    
    @usableFromInline
    var currentPipelineReflection : PipelineReflection! = nil
    
    init(commandRecorder: FrameGraphCommandRecorder, resourceUsages: ResourceUsages, passRecord: RenderPassRecord) {
        self.commandRecorder = commandRecorder
        self.resourceUsages = resourceUsages
        self.passRecord = passRecord
        self.startCommandIndex = self.commandRecorder.nextCommandIndex
        
        let arena = Unmanaged.passUnretained(commandRecorder.commmandEncoderTemporaryArena)
        self.boundResources = HashMap(allocator: .custom(arena))
        self.untrackedBoundResources = HashMap(allocator: .custom(arena))
        self.pendingArgumentBuffers = ExpandingBuffer(allocator: .custom(arena))
        self.resourceBindingCommands = ExpandingBuffer(allocator: .custom(arena))
        self.usageNodesToUpdate = ExpandingBuffer(allocator: .custom(arena))
        
        self.pushDebugGroup(passRecord.pass.name)
    }
    
    @inlinable
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, key: FunctionArgumentKey) {
        let args : FrameGraphCommand.SetBytesArgs = (.nil, commandRecorder.copyBytes(bytes, length: length), UInt32(length))
        
        self.resourceBindingCommands.append(
            (key, .setBytes(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    @inlinable
    public func setBuffer(_ buffer: Buffer?, offset: Int, key: FunctionArgumentKey) {
        guard let buffer = buffer else { return }
        self.resourceUsages.registerResource(Resource(buffer))
        
        let args : FrameGraphCommand.SetBufferArgs = (.nil, buffer.handle, UInt32(offset), false)
        
        self.resourceBindingCommands.append(
            (key, .setBuffer(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    @inlinable
    public func setBufferOffset(_ offset: Int, key: FunctionArgumentKey) {
        let args : FrameGraphCommand.SetBufferOffsetArgs = (.nil, nil, UInt32(offset))
        
        self.resourceBindingCommands.append(
            (key, .setBufferOffset(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    @inlinable
    public func setSampler(_ descriptor: SamplerDescriptor?, key: FunctionArgumentKey) {
        guard let descriptor = descriptor else { return }
        
        let args : FrameGraphCommand.SetSamplerStateArgs = (.nil, descriptor)
        
        self.resourceBindingCommands.append(
            (key, .setSamplerState(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    @inlinable
    public func setTexture(_ texture: Texture?, key: FunctionArgumentKey) {
        guard let texture = texture else { return }
        self.resourceUsages.registerResource(Resource(texture))
        
        let args : FrameGraphCommand.SetTextureArgs = (.nil, texture.handle)
        
        self.resourceBindingCommands.append(
            (key, .setTexture(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    @inlinable
    public func setArgumentBuffer(_ argumentBuffer: ArgumentBuffer?, key: FunctionArgumentKey) {
        guard let argumentBuffer = argumentBuffer else { return }
        
        self.pendingArgumentBuffers.append((key, argumentBuffer, type: .standalone, assumeConsistentUsage: false))
        self.needsUpdateBindings = true
    }
    
    @inlinable
    public func setArgumentBuffer<K>(_ argumentBuffer: TypedArgumentBuffer<K>?, key: FunctionArgumentKey) {
        self.setArgumentBuffer(argumentBuffer?.argumentBuffer, key: key)
    }
    
    @inlinable
    public func setArgumentBufferArray(_ argumentBufferArray: ArgumentBufferArray?, key: FunctionArgumentKey, assumeConsistentUsage: Bool = false) {
        guard let argumentBufferArray = argumentBufferArray else { return }
        
        let args : FrameGraphCommand.SetArgumentBufferArrayArgs = (.nil, argumentBufferArray, false) // false meaning is not yet bound
        let argsPointer = commandRecorder.copyData(args)
        
        for (i, argumentBuffer) in argumentBufferArray.bindings.enumerated() {
            guard let argumentBuffer = argumentBuffer else { continue }
            let type : ArgumentBufferType = .inArray(index: i, bindingArgs: UnsafeMutablePointer(mutating: argsPointer))
            self.pendingArgumentBuffers.append((key, argumentBuffer, type: type, assumeConsistentUsage: assumeConsistentUsage))
        }
        
        // We add the command to the commands list here so that the binding key can be translated.
        self.resourceBindingCommands.append((key, FrameGraphCommand.setArgumentBufferArray(UnsafePointer(argsPointer))))
        
        self.resourceUsages.registerResource(Resource(argumentBufferArray))
        
        self.needsUpdateBindings = true
    }
    
    
    @usableFromInline
    func updateUsageNodes(lastIndex: Int) {
        for usageNode in usageNodesToUpdate {
            usageNode.pointee.element.commandRangeInPass = Range(uncheckedBounds: (usageNode.pointee.element.commandRangeInPass.lowerBound, lastIndex + 1))
        }
        usageNodesToUpdate.removeAll()
    }
   
    @inlinable
    public func updateResourceUsages(endingEncoding: Bool = false) {
        guard self.needsUpdateBindings || endingEncoding else {
            return
        }
        defer { self.needsUpdateBindings = false }
        
        self.updateResourceUsagesInternal(endingEncoding: endingEncoding)
    }
    
    @usableFromInline
    func updateResourceUsagesInternal(endingEncoding: Bool) {
        let lastUsageIsNextCommand = self.lastGPUCommandIndex == self.nextCommandOffset // If it's the next command, we need to extend the usage out.
        
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
        
        let resourceBindingCommandsStartCount = self.resourceBindingCommands.count //
        
        // If the pipeline state hasn't changed, only try to bind new commands.
        for i in (pipelineStateChanged ? 0 : self.resourceBindingCommandCountLastUpdate)..<resourceBindingCommandsStartCount {
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
                    
                    let handle = setBufferArgs.pointee.handle
                    UnsafeMutablePointer(mutating: args).pointee.handle = handle
                    setBufferArgs.pointee.hasDynamicOffset = true
                    
                    return currentlyBound
                    
                case .setBuffer(let args):
                    if let previousArgs = currentlyBound?.bindingCommand?.assumingMemoryBound(to: FrameGraphCommand.SetBufferArgs.self) {
                        if previousArgs.pointee.handle == args.pointee.handle { // Ignore the duplicate binding.
                            if !self.pipelineStateChanged, previousArgs.pointee.offset == args.pointee.offset {
                                return currentlyBound
                            } /* else {
                             // TODO: translate duplicate setBuffer calls into setBufferOffset.
                             }*/
                        }
                    }
                    
                    identifier = args.pointee.handle
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    argsPtr = UnsafeMutableRawPointer(mutating: args)
                    
                case .setTexture(let args):
                    if let previousArgs = currentlyBound?.bindingCommand?.assumingMemoryBound(to: FrameGraphCommand.SetTextureArgs.self) {
                        if !self.pipelineStateChanged, previousArgs.pointee.handle == args.pointee.handle { // Ignore the duplicate binding.
                            return currentlyBound
                        }
                    }
                    
                    identifier = args.pointee.handle
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    argsPtr = UnsafeMutableRawPointer(mutating: args)
                    
                default:
                    preconditionFailure()
                }
                
                // Optimisation: if the pipeline state hasn't changed, these are the only resources we need to consider, so lookup their reflection data immediately.
                if !self.pipelineStateChanged, let reflection = pipelineReflection.argumentReflection(at: bindingPath), (reflection.isActive || FrameGraph.debugMode) {
                    self.commandRecorder.commands.append(command)
                    let node = self.resourceUsages.resourceUsageNode(for: identifier, encoder: self, usageType: reflection.usageType, stages: reflection.stages, inArgumentBuffer: false, firstCommandOffset: firstCommandOffset)
                    return BoundResource(resource: Resource(existingHandle: identifier), bindingCommand: argsPtr, usageNode: node, isInArgumentBuffer: false, consistentUsageAssumed: false)
                } else {
                    return BoundResource(resource: Resource(existingHandle: identifier), bindingCommand: argsPtr, usageNode: nil, isInArgumentBuffer: false, consistentUsageAssumed: false)
                }
            })
        }
        
        self.resourceBindingCommands.removePrefix(count: resourceBindingCommandsStartCount)
        
        let pendingArgumentBuffersStartCount = self.pendingArgumentBuffers.count
        // If the pipeline state hasn't changed, only try to bind new argument buffers.
        for i in (pipelineStateChanged ? 0 : self.pendingArgumentBufferCountLastUpdate)..<pendingArgumentBuffersStartCount {
            let (key, argumentBuffer, argBufferType, assumeConsistentUsage) = self.pendingArgumentBuffers[i]
            
            let arrayIndex = argBufferType.arrayIndex
            
            let argumentBufferPath : ResourceBindingPath
            
            if let path = key.bindingPath(arrayIndex: arrayIndex, argumentBufferPath: nil) {
                guard pipelineReflection.bindingIsActive(at: path) else {
                    self.pendingArgumentBuffers.append((key, argumentBuffer, argBufferType, assumeConsistentUsage))
                    continue
                }
                argumentBufferPath = path
            } else if let path = pipelineReflection.bindingPath(argumentBuffer: argumentBuffer, argumentName: key.stringValue, arrayIndex: argBufferType.arrayIndex) {
                argumentBufferPath = path
            } else {
                self.pendingArgumentBuffers.append((key, argumentBuffer, argBufferType, assumeConsistentUsage))
                continue
            }
            
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
                
                if let renderAPIResource = renderAPIResource {
                    self.resourceUsages.registerResource(renderAPIResource)
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
                } else {
                    if let existingUsage = self.boundResources.removeValue(forKey: bindingPath)?.usageNode {
                        self.usageNodesToUpdate.append(existingUsage)
                    }
                    if let existingUsage = self.untrackedBoundResources.removeValue(forKey: bindingPath)?.usageNode {
                        self.usageNodesToUpdate.append(existingUsage)
                    }
                    continue
                }
                
                // Below: manually inlined version of `replacingBoundResourceNode`. There is a slight performance deficit (around 1.5ms given an average frame time of 18-21ms) when the closure is called directly.
                
//                replacingBoundResourceNode(bindingPath: bindingPath, resultUntrackedIfUsed: assumeConsistentUsage, perform: { currentlyBound in
//                    // Optimisation: if the pipeline state hasn't changed, these are the only resources we need to consider, so look up their reflection data immediately.
//                    if !self.pipelineStateChanged, let reflection = pipelineReflection.argumentReflection(at: bindingPath), (reflection.isActive || FrameGraph.debugMode) {
//                        let node = self.resourceUsages.resourceUsageNode(for: identifier, encoder: self, usageType: reflection.usageType, stages: reflection.stages, inArgumentBuffer: true, firstCommandOffset: firstCommandOffset)
//                        return BoundResource(resource: Resource(existingHandle: identifier), bindingCommand: nil, usageNode: node, isInArgumentBuffer: true, consistentUsageAssumed: assumeConsistentUsage)
//                    } else {
//                        return BoundResource(resource: Resource(existingHandle: identifier), bindingCommand: nil, usageNode: nil, isInArgumentBuffer: true, consistentUsageAssumed: assumeConsistentUsage)
//                    }
//                })
                
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
                
                let newValue : BoundResource
                
                // Optimisation: if the pipeline state hasn't changed, these are the only resources we need to consider, so look up their reflection data immediately.
                if !self.pipelineStateChanged, let reflection = pipelineReflection.argumentReflection(at: bindingPath), (reflection.isActive || FrameGraph.debugMode) {
                    let node = self.resourceUsages.resourceUsageNode(for: identifier, encoder: self, usageType: reflection.usageType, stages: reflection.stages, inArgumentBuffer: true, firstCommandOffset: firstCommandOffset)
                    newValue = BoundResource(resource: Resource(existingHandle: identifier), bindingCommand: nil, usageNode: node, isInArgumentBuffer: true, consistentUsageAssumed: assumeConsistentUsage)
                } else {
                    newValue = BoundResource(resource: Resource(existingHandle: identifier), bindingCommand: nil, usageNode: nil, isInArgumentBuffer: true, consistentUsageAssumed: assumeConsistentUsage)
                }
                
                if assumeConsistentUsage, newValue.usageNode != nil {
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
                
                if let currentBoundUsage = currentlyBound?.usageNode, newValue.usageNode != currentBoundUsage {
                    self.usageNodesToUpdate.append(currentBoundUsage) // The old resource is no longer bound, so we need to end the old usage.
                }
            }
            
            switch argBufferType {
            case .standalone:
                commandRecorder.record(FrameGraphCommand.setArgumentBuffer, (argumentBufferPath, argumentBuffer))
            case .inArray(_, let bindingArgs):
                if !bindingArgs.pointee.isBound {
                    commandRecorder.record(FrameGraphCommand.setArgumentBufferArray(UnsafePointer(bindingArgs)))
                    bindingArgs.pointee.isBound = true
                }
            }
        }
        
        self.pendingArgumentBuffers.removePrefix(count: pendingArgumentBuffersStartCount)
        
        if self.pipelineStateChanged {
            // Only update tracked bound resources, not any members of untrackedBoundResources
            
            self.boundResources.forEachMutating { bindingPath, boundResource, deleteEntry in // boundResource is an inout parameter.
                if let reflection = pipelineReflection.argumentReflection(at: bindingPath), (reflection.isActive || FrameGraph.debugMode) {
                    // Mark the resource as used if it currently isn't
                        
                    // If the command to bind the resource hasn't yet been inserted into the command stream, insert it now.
                    if boundResource.usageNode == nil, let bindingCommandArgs = boundResource.bindingCommand {
                        switch boundResource.resource.type {
                        case .texture:
                            self.commandRecorder.commands.append(.setTexture(bindingCommandArgs.assumingMemoryBound(to: FrameGraphCommand.SetTextureArgs.self)))
                        case .buffer:
                            self.commandRecorder.commands.append(.setBuffer(bindingCommandArgs.assumingMemoryBound(to: FrameGraphCommand.SetBufferArgs.self)))
                        default:
                            preconditionFailure()
                        }
                    }
                    
                    let node = self.resourceUsages.resourceUsageNode(for: boundResource.resource.handle, encoder: self, usageType: reflection.usageType, stages: reflection.stages, inArgumentBuffer: boundResource.isInArgumentBuffer, firstCommandOffset: firstCommandOffset)
                    boundResource.usageNode = node
                    
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

        self.lastGPUCommandIndex = lastUsageIsNextCommand ? self.nextCommandOffset : self.lastGPUCommandIndex
        updateUsageNodes(lastIndex: self.lastGPUCommandIndex)
        
        self.resourceBindingCommandCountLastUpdate = self.resourceBindingCommands.count
        self.pendingArgumentBufferCountLastUpdate = self.pendingArgumentBuffers.count
    }
    
    public func resetAllBindings() {
        self.resourceBindingCommandCountLastUpdate = 0
        self.pendingArgumentBufferCountLastUpdate = 0
        
        self.resourceBindingCommands.removeAll()
        self.pendingArgumentBuffers.removeAll()
        
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
        
        if FrameGraph.debugMode {
            if let pipelineReflection = self.currentPipelineReflection {
                for (key, _) in self.resourceBindingCommands where key.computedBindingPath(pipelineReflection: pipelineReflection) == nil {
                    print("FrameGraph Warning (\(self.renderPass.name)): Ignored bindings for resource with key \(key.stringValue) which does not exist in the specialised shader code.")
                }
                
                for (key, argumentBuffer, argBufferType, _) in self.pendingArgumentBuffers where (key.bindingPath(arrayIndex: argBufferType.arrayIndex, argumentBufferPath: nil) ?? pipelineReflection.bindingPath(argumentBuffer: argumentBuffer, argumentName: key.stringValue, arrayIndex: argBufferType.arrayIndex)) == nil {
                    print("FrameGraph Warning (\(self.renderPass.name)): Ignored bindings for argument buffer with key \(key.stringValue) which does not exist in the specialised shader code.")
                }
            }
        }
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
    
    @inlinable
    public func setArguments<A : Encodable>(_ arguments: A) {
        let encoder = FunctionArgumentEncoder(commandEncoder: self)
        try! encoder.encode(arguments)
    }
    
}

@_fixed_layout
public final class RenderCommandEncoder : ResourceBindingEncoder {
    
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
        let allocator = Unmanaged.passUnretained(commandRecorder.commmandEncoderTemporaryArena)
        self.renderTargetAttachmentUsages = HashMap(allocator: .custom(allocator))
        
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
    func updateColorAttachmentUsages() {
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
        
            guard renderPipelineDescriptor.writeMasks[i] != [] else {
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
    func updateDepthStencilAttachmentUsages() {
        guard let gpuCommandsStartIndex = self.gpuCommandsStartIndexDepthStencil else {
            return
        }
        self.gpuCommandsStartIndexDepthStencil = nil
        
        guard let depthStencilDescriptor = self.depthStencilDescriptor else {
            return // No depth writes enabled, depth test always passes, no stencil tests.
        }
        
        depthCheck: if depthStencilDescriptor.isDepthWriteEnabled, let depthAttachment = drawRenderPass.renderTargetDescriptor.depthAttachment {
            let type : ResourceUsageType = depthStencilDescriptor.depthCompareFunction != .always ? .readWriteRenderTarget : .writeOnlyRenderTarget
            
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
            usageNode.pointee.element.commandRangeInPass = Range(gpuCommandsStartIndex..<self.lastGPUCommandIndex)
            self.renderTargetAttachmentUsages[.stencil] = usageNode
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

        let box = Unmanaged.passRetained(ReferenceBox(descriptor))
        commandRecorder.unmanagedReferences.append(box)
        commandRecorder.record(.setRenderPipelineDescriptor(box))
        
        self.updateColorAttachmentUsages()
    }
    
    @inlinable
    public func setVertexBuffer(_ buffer: Buffer?, offset: Int, index: Int) {
        if let currentBinding = self.boundVertexBuffers[index] {
            currentBinding.pointee.element.commandRangeInPass = currentBinding.pointee.element.commandRangeInPass.lowerBound..<self.nextCommandOffset
        }
        
        guard let buffer = buffer else { return }
        
        self.resourceUsages.registerResource(Resource(buffer))
        let newUsageNode = self.resourceUsages.resourceUsageNode(for: buffer.handle, encoder: self, usageType: .vertexBuffer, stages: .vertex, inArgumentBuffer: false, firstCommandOffset: self.nextCommandOffset)
        self.boundVertexBuffers[index] = newUsageNode
        
        commandRecorder.record(FrameGraphCommand.setVertexBuffer, (buffer.handle, UInt32(offset), UInt32(index)))
    }
    
    @inlinable
    public func setVertexBufferOffset(_ offset: Int, index: Int) {
        commandRecorder.record(FrameGraphCommand.setVertexBufferOffset(offset: UInt32(offset), index: UInt32(index)))
    }

    @inlinable
    public func setViewport(_ viewport: Viewport) {
        commandRecorder.record(FrameGraphCommand.setViewport, viewport)
    }
    
    @inlinable
    public func setFrontFacing(_ frontFacingWinding: Winding) {
        commandRecorder.record(.setFrontFacing(frontFacingWinding))
    }
    
    @inlinable
    public func setCullMode(_ cullMode: CullMode) {
        commandRecorder.record(.setCullMode(cullMode))
    }
    
    @inlinable
    public func setTriangleFillMode(_ fillMode: TriangleFillMode) {
        commandRecorder.record(.setTriangleFillMode(fillMode))
    }
    
    public func setDepthStencilDescriptor(_ descriptor: DepthStencilDescriptor?) {
        self.depthStencilDescriptor = descriptor
        
        let box = Unmanaged.passRetained(ReferenceBox(descriptor))
        commandRecorder.unmanagedReferences.append(box)
        commandRecorder.record(FrameGraphCommand.setDepthStencilDescriptor(box))
        
        self.updateDepthStencilAttachmentUsages()
    }
    
    @inlinable
    public func setScissorRect(_ rect: ScissorRect) {
        commandRecorder.record(FrameGraphCommand.setScissorRect, rect)
    }
    
    @inlinable
    public func setDepthClipMode(_ depthClipMode: DepthClipMode) {
        commandRecorder.record(.setDepthClipMode(depthClipMode))
    }
    
    @inlinable
    public func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float) {
        commandRecorder.record(FrameGraphCommand.setDepthBias, (depthBias, slopeScale, clamp))
    }
    
    @inlinable
    public func setStencilReferenceValue(_ referenceValue: UInt32) {
        commandRecorder.record(.setStencilReferenceValue(referenceValue))
    }
    
    @inlinable
    public func setStencilReferenceValues(front frontReferenceValue: UInt32, back backReferenceValue: UInt32) {
        commandRecorder.record(.setStencilReferenceValues(front: frontReferenceValue, back: backReferenceValue))
    }
    
    @inlinable
    public func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int = 1, baseInstance: Int = 0) {
        self.lastGPUCommandIndex = self.nextCommandOffset
        self.updateResourceUsages()
        
        self.gpuCommandsStartIndexColor = self.gpuCommandsStartIndexColor ?? self.nextCommandOffset
        self.gpuCommandsStartIndexDepthStencil = self.gpuCommandsStartIndexDepthStencil ?? self.nextCommandOffset
        
        commandRecorder.record(FrameGraphCommand.drawPrimitives, (primitiveType, UInt32(vertexStart), UInt32(vertexCount), UInt32(instanceCount), UInt32(baseInstance)))
    }
    
    @inlinable
    public func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int = 1, baseVertex: Int = 0, baseInstance: Int = 0) {
        self.lastGPUCommandIndex = self.nextCommandOffset
        self.updateResourceUsages()
        
        self.gpuCommandsStartIndexColor = self.gpuCommandsStartIndexColor ?? self.nextCommandOffset
        self.gpuCommandsStartIndexDepthStencil = self.gpuCommandsStartIndexDepthStencil ?? self.nextCommandOffset
        self.resourceUsages.addResourceUsage(for: indexBuffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .indexBuffer, stages: .vertex, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.drawIndexedPrimitives, (primitiveType, UInt32(indexCount), indexType, indexBuffer.handle, UInt32(indexBufferOffset), UInt32(instanceCount), Int32(baseVertex), UInt32(baseInstance)))
    }
    
    @inlinable
    public override func updateResourceUsages(endingEncoding: Bool = false) {
        super.updateResourceUsages(endingEncoding: endingEncoding)
        
        if endingEncoding {
            for usageNode in self.boundVertexBuffers {
                guard let usageNode = usageNode else { continue }
                if self.lastGPUCommandIndex > usageNode.pointee.element.commandRangeInPass.lowerBound {
                    usageNode.pointee.element.commandRangeInPass = Range(usageNode.pointee.element.commandRangeInPass.lowerBound...self.lastGPUCommandIndex)
                }
            }
            
            self.updateColorAttachmentUsages()
            self.updateDepthStencilAttachmentUsages()
        }
    }
}


@_fixed_layout
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
    
    @inlinable
    public func setStageInRegion(_ region: Region) {
        commandRecorder.record(FrameGraphCommand.setStageInRegion, region)
    }
    
    @inlinable
    public func setThreadgroupMemoryLength(_ length: Int, index: Int) {
        commandRecorder.record(.setThreadgroupMemoryLength(length: UInt32(length), index: UInt32(index)))
    }
    
    @usableFromInline
    func updateThreadgroupExecutionWidth(threadsPerThreadgroup: Size) {
        let threads = threadsPerThreadgroup.width * threadsPerThreadgroup.height * threadsPerThreadgroup.depth
        let isMultiple = threads % self.currentThreadExecutionWidth == 0
        self.currentComputePipeline!.threadGroupSizeIsMultipleOfThreadExecutionWidth = self.currentComputePipeline!.threadGroupSizeIsMultipleOfThreadExecutionWidth && isMultiple
    }

    @inlinable
    public func dispatchThreads(_ threadsPerGrid: Size, threadsPerThreadgroup: Size) {
        self.updateThreadgroupExecutionWidth(threadsPerThreadgroup: threadsPerThreadgroup)
        self.lastGPUCommandIndex = self.nextCommandOffset
        self.updateResourceUsages()
        
        commandRecorder.record(FrameGraphCommand.dispatchThreads, (threadsPerGrid, threadsPerThreadgroup))
    }
    
    @inlinable
    public func dispatchThreadgroups(_ threadgroupsPerGrid: Size, threadsPerThreadgroup: Size) {
        self.updateThreadgroupExecutionWidth(threadsPerThreadgroup: threadsPerThreadgroup)
        self.lastGPUCommandIndex = self.nextCommandOffset
        self.updateResourceUsages()
        
        commandRecorder.record(FrameGraphCommand.dispatchThreadgroups, (threadgroupsPerGrid, threadsPerThreadgroup))
    }
    
    @inlinable
    public func dispatchThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size) {
        self.updateThreadgroupExecutionWidth(threadsPerThreadgroup: threadsPerThreadgroup)
        self.lastGPUCommandIndex = self.nextCommandOffset
        self.updateResourceUsages()
        
        self.resourceUsages.addResourceUsage(for: indirectBuffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .indirectBuffer, stages: .compute, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.dispatchThreadgroupsIndirect, (indirectBuffer.handle, UInt32(indirectBufferOffset), threadsPerThreadgroup))
    }
}

@_fixed_layout
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
    
    @inlinable
    public func copy(from sourceBuffer: Buffer, sourceOffset: Int, sourceBytesPerRow: Int, sourceBytesPerImage: Int, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin, options: BlitOption = []) {
        let commandOffset = self.nextCommandOffset
        
        resourceUsages.addResourceUsage(for: sourceBuffer, commandIndex: commandOffset, encoder: self, usageType: .blitSource, stages: .blit, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: destinationTexture, commandIndex: commandOffset, encoder: self, usageType: .blitDestination, stages: .blit, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.copyBufferToTexture, (sourceBuffer.handle, UInt32(sourceOffset), UInt32(sourceBytesPerRow), UInt32(sourceBytesPerImage), sourceSize, destinationTexture.handle, UInt32(destinationSlice), UInt32(destinationLevel), destinationOrigin, options))
    }
    
    @inlinable
    public func copy(from sourceBuffer: Buffer, sourceOffset: Int, to destinationBuffer: Buffer, destinationOffset: Int, size: Int) {
        let commandOffset = self.nextCommandOffset
        
        resourceUsages.addResourceUsage(for: sourceBuffer, commandIndex: commandOffset, encoder: self, usageType: .blitSource, stages: .blit, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: destinationBuffer, commandIndex: commandOffset, encoder: self, usageType: .blitDestination, stages: .blit, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.copyBufferToBuffer, (sourceBuffer.handle, UInt32(sourceOffset), destinationBuffer.handle, UInt32(destinationOffset), UInt32(size)))
    }
    
    @inlinable
    public func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationBuffer: Buffer, destinationOffset: Int, destinationBytesPerRow: Int, destinationBytesPerImage: Int, options: BlitOption = []) {
        let commandOffset = self.nextCommandOffset
        
        resourceUsages.addResourceUsage(for: sourceTexture, commandIndex: commandOffset, encoder: self, usageType: .blitSource, stages: .blit, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: destinationBuffer, commandIndex: commandOffset, encoder: self, usageType: .blitDestination, stages: .blit, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.copyTextureToBuffer, (sourceTexture.handle, UInt32(sourceSlice), UInt32(sourceLevel), sourceOrigin, sourceSize, destinationBuffer.handle, UInt32(destinationOffset), UInt32(destinationBytesPerRow), UInt32(destinationBytesPerImage), options))
    }
    
    @inlinable
    public func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin) {
        let commandOffset = self.nextCommandOffset
        
        resourceUsages.addResourceUsage(for: sourceTexture, commandIndex: commandOffset, encoder: self, usageType: .blitSource, stages: .blit, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: destinationTexture, commandIndex: commandOffset, encoder: self, usageType: .blitDestination, stages: .blit, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.copyTextureToTexture, (sourceTexture.handle, UInt32(sourceSlice), UInt32(sourceLevel), sourceOrigin, sourceSize, destinationTexture.handle, UInt32(destinationSlice), UInt32(destinationLevel), destinationOrigin))
    }
    
    @inlinable
    public func fill(buffer: Buffer, range: Range<Int>, value: UInt8) {
        resourceUsages.addResourceUsage(for: buffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitDestination, stages: .blit, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.fillBuffer, (buffer.handle, range, value))
    }
    
    @inlinable
    public func generateMipmaps(for texture: Texture) {
        resourceUsages.addResourceUsage(for: texture, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitSynchronisation, stages: .blit, inArgumentBuffer: false)
        
        commandRecorder.record(.generateMipmaps(texture.handle))
    }
    
    @inlinable
    public func synchronize(buffer: Buffer) {
        resourceUsages.addResourceUsage(for: buffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitSynchronisation, stages: .blit, inArgumentBuffer: false)
        
        commandRecorder.record(.synchroniseBuffer(buffer.handle))
    }
    
    @inlinable
    public func synchronize(texture: Texture) {
        resourceUsages.addResourceUsage(for: texture, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitSynchronisation, stages: .blit, inArgumentBuffer: false)
        commandRecorder.record(.synchroniseTexture(texture.handle))
    }
    
    @inlinable
    public func synchronize(texture: Texture, slice: Int, level: Int) {
        resourceUsages.addResourceUsage(for: texture, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitSynchronisation, stages: .blit, inArgumentBuffer: false)
        commandRecorder.record(FrameGraphCommand.synchroniseTextureSlice, (texture.handle, UInt32(slice), UInt32(level)))
    }
}

@_fixed_layout
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
    @inlinable
    public func encodeRayIntersection(intersector: MPSRayIntersector, intersectionType: MPSIntersectionType, rayBuffer: Buffer, rayBufferOffset: Int, intersectionBuffer: Buffer, intersectionBufferOffset: Int, rayCount: Int, accelerationStructure: MPSAccelerationStructure) {
        
        let intersector = Unmanaged.passRetained(intersector)
        self.commandRecorder.unmanagedReferences.append(intersector)
        
        let accelerationStructure = Unmanaged.passRetained(accelerationStructure)
        self.commandRecorder.unmanagedReferences.append(accelerationStructure)
        
        resourceUsages.addResourceUsage(for: rayBuffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .read, stages: .compute, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: intersectionBuffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .write, stages: .compute, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.encodeRayIntersection, (intersector, intersectionType, rayBuffer.handle, rayBufferOffset, intersectionBuffer.handle, intersectionBufferOffset, rayCount, accelerationStructure))
    }
    
    @available(OSX 10.14, *)
    @inlinable
    public func encodeRayIntersection(intersector: MPSRayIntersector, intersectionType: MPSIntersectionType, rayBuffer: Buffer, rayBufferOffset: Int, intersectionBuffer: Buffer, intersectionBufferOffset: Int, rayCountBuffer: Buffer, rayCountBufferOffset: Int, accelerationStructure: MPSAccelerationStructure) {
        
        let intersector = Unmanaged.passRetained(intersector)
        self.commandRecorder.unmanagedReferences.append(intersector)
        
        let accelerationStructure = Unmanaged.passRetained(accelerationStructure)
        self.commandRecorder.unmanagedReferences.append(accelerationStructure)
        
        resourceUsages.addResourceUsage(for: rayBuffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .read, stages: .compute, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: intersectionBuffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .write, stages: .compute, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: rayCountBuffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .read, stages: .compute, inArgumentBuffer: false)
        
        commandRecorder.record(FrameGraphCommand.encodeRayIntersectionRayCountBuffer, (intersector, intersectionType, rayBuffer.handle, rayBufferOffset, intersectionBuffer.handle, intersectionBufferOffset, rayCountBuffer.handle, rayCountBufferOffset, accelerationStructure))
    }
    
    #endif
}
