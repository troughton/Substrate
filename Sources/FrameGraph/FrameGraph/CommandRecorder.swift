//
//  LazyFrameGraph.swift
//  FrameGraph
//
//  Created by Thomas Roughton on 16/12/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

import Utilities
import Foundation
import RenderAPI

protocol Releasable {
    func release()
}

extension Unmanaged : Releasable { }

public final class ReferenceBox<T> {
    public var value : T
    
    public init(_ value: T) {
        self.value = value
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
    
    public typealias SetArgumentBufferArgs = (bindingPath: ResourceBindingPath, argumentBuffer: Unmanaged<ArgumentBuffer>)
    case setArgumentBuffer(UnsafePointer<SetArgumentBufferArgs>)
    
    // Render
    
    public typealias SetVertexBufferArgs = (handle: Buffer.Handle?, offset: UInt32, index: UInt32)
    case setVertexBuffer(UnsafePointer<SetVertexBufferArgs>)
    
    case setVertexBufferOffset(offset: UInt32, index: UInt32)
    
    case setRenderPipelineState(Unmanaged<ReferenceBox<RenderPipelineDescriptor>>)
    
    public typealias DrawPrimitivesArgs = (primitiveType: PrimitiveType, vertexStart: UInt32, vertexCount: UInt32, instanceCount: UInt32, baseInstance: UInt32)
    case drawPrimitives(UnsafePointer<DrawPrimitivesArgs>)
    
    public typealias DrawIndexedPrimitivesArgs = (primitiveType: PrimitiveType, indexCount: UInt32, indexType: IndexType, indexBuffer: Buffer.Handle, indexBufferOffset: UInt32, instanceCount: UInt32, baseVertex: Int32, baseInstance: UInt32)
    case drawIndexedPrimitives(UnsafePointer<DrawIndexedPrimitivesArgs>)
    
    case setViewport(UnsafePointer<Viewport>)
    
    case setFrontFacing(Winding)
    
    case setCullMode(CullMode)
    
    case setDepthStencilState(Unmanaged<ReferenceBox<DepthStencilDescriptor?>>)
    
    case setScissorRect(UnsafePointer<ScissorRect>)
    
    case setDepthClipMode(DepthClipMode)
    
    public typealias SetDepthBiasArgs = (depthBias: Float, slopeScale: Float, clamp: Float)
    case setDepthBias(UnsafePointer<SetDepthBiasArgs>)
    
    case setStencilReferenceValue(UInt32)
    
    case setStencilReferenceValues(front: UInt32, back: UInt32)
    
    
    // Compute
    
    public typealias DispatchThreadgroupsArgs = (threadgroupsPerGrid: Size, threadsPerThreadgroup: Size)
    case dispatchThreadgroups(UnsafePointer<DispatchThreadgroupsArgs>)
    
    public typealias DispatchThreadgroupsIndirectArgs = (indirectBuffer: Buffer.Handle, indirectBufferOffset: UInt32, threadsPerThreadgroup: Size)
    case dispatchThreadgroupsIndirect(UnsafePointer<DispatchThreadgroupsIndirectArgs>)
    
    case setComputePipelineState(Unmanaged<ReferenceBox<ComputePipelineDescriptor>>)
    
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
    
}

@discardableResult
func << <T>(lhs: (FrameGraphCommandRecorder, UnsafePointer<T>), rhs: (UnsafePointer<T>) -> FrameGraphCommand) -> FrameGraphCommandRecorder {
    lhs.0 << rhs(lhs.1)
    return lhs.0
}

public final class FrameGraphCommandRecorder {
    var commands = [FrameGraphCommand]()
    let dataArena = MemoryArena()
    
    var unmanagedReferences = [Releasable]()
    
    public var nextCommandIndex : Int {
        return self.commands.count
    }
    
    public func reset() {
        commands.removeAll(keepingCapacity: true)
        dataArena.reset()
        
        for reference in unmanagedReferences {
            reference.release()
        }
        self.unmanagedReferences.removeAll(keepingCapacity: true)
    }
    
    public func copyData<T>(_ data: T) -> UnsafePointer<T> {
        let result = self.dataArena.allocate() as UnsafeMutablePointer<T>
        result.initialize(to: data)
        return UnsafePointer(result)
    }
    
    public static func << <T>(lhs: FrameGraphCommandRecorder, rhs: T) -> (FrameGraphCommandRecorder, UnsafePointer<T>) {
        let result = lhs.dataArena.allocate() as UnsafeMutablePointer<T>
        result.initialize(to: rhs)
        
        return (lhs, UnsafePointer(result))
    }
    
    public static func <<(lhs: FrameGraphCommandRecorder, rhs: String) -> (FrameGraphCommandRecorder, UnsafePointer<CChar>) {
        let cStringAddress = rhs.withCString { label -> UnsafePointer<CChar> in
            let numChars = strlen(label)
            let destination : UnsafeMutablePointer<CChar> = lhs.dataArena.allocate(count: numChars + 1)
            destination.initialize(from: label, count: numChars)
            destination[numChars] = 0
            return UnsafePointer(destination)
        }
        
        return (lhs, cStringAddress)
    }
    
    @discardableResult
    public static func <<(lhs: FrameGraphCommandRecorder, rhs: FrameGraphCommand) -> FrameGraphCommandRecorder {
        lhs.commands.append(rhs)
        return lhs
    }
    
    @discardableResult
    public func copyBytes(_ bytes: UnsafeRawPointer, length: Int) -> UnsafeRawPointer {
        let newBytes = self.dataArena.allocate(bytes: length, alignedTo: 16)
        newBytes.copyMemory(from: bytes, byteCount: length)
        return UnsafeRawPointer(newBytes)
    }
    
    public func setLabel(_ label: String) {
        (self << label) << FrameGraphCommand.setLabel
    }
    
    public func pushDebugGroup(_ string: String) {
       (self << string) << FrameGraphCommand.pushDebugGroup
    }
    
    
    public func insertDebugSignpost(_ string: String) {
        (self << string) << FrameGraphCommand.insertDebugSignpost
    }
    
}

public protocol CommandEncoder {
    var passRecord : RenderPassRecord { get }
    
    var commandRecorder : FrameGraphCommandRecorder { get }
    var startCommandIndex : Int { get }
    
    func endEncoding()
}

extension CommandEncoder {
    /// Returns the offset of the next command within this pass' command list.
    public var nextCommandOffset : Int {
        return self.commandRecorder.nextCommandIndex - self.startCommandIndex
    }
    
    var renderPass : RenderPass {
        return self.passRecord.pass
    }
}

extension CommandEncoder {
    public func pushDebugGroup(_ string: String) {
        commandRecorder.pushDebugGroup(string)
    }
    
    public func popDebugGroup() {
        commandRecorder << .popDebugGroup
    }
    
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

public class ResourceBindingEncoder : CommandEncoder {
    
    public let commandRecorder : FrameGraphCommandRecorder
    public let passRecord: RenderPassRecord
    public let startCommandIndex : Int
    let resourceUsages : ResourceUsages
    
    var pendingArgumentBuffers = [(FunctionArgumentKey, ArgumentBuffer)]()
    var resourceBindingCommands = [(FunctionArgumentKey, FrameGraphCommand)]()

    // The UnsafeMutableRawPointer points to the args parameterising the command.
    // It enables us to go back and change the command during recording (e.g. with a setBufferOffset after a setBuffer)
    var boundResources = [ResourceBindingPath : (UnsafeMutableRawPointer?, ResourceUsageNodePtr)]()
    
    var lastGPUCommandIndex = 0
    
    var needsUpdateBindings = false
    var pipelineStateChanged = false
    
    init(commandRecorder: FrameGraphCommandRecorder, resourceUsages: ResourceUsages, passRecord: RenderPassRecord) {
        self.commandRecorder = commandRecorder
        self.resourceUsages = resourceUsages
        self.passRecord = passRecord
        self.startCommandIndex = self.commandRecorder.nextCommandIndex
    }
    
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, key: FunctionArgumentKey) {
        let args : FrameGraphCommand.SetBytesArgs = (.nil, commandRecorder.copyBytes(bytes, length: length), UInt32(length))
        
        self.resourceBindingCommands.append(
            (key, .setBytes(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    public func setBuffer(_ buffer: Buffer?, offset: Int, key: FunctionArgumentKey) {
        guard let buffer = buffer else { return }
        self.resourceUsages.registerResource(buffer)
        
        let args : FrameGraphCommand.SetBufferArgs = (.nil, buffer.handle, UInt32(offset), false)
        
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
        self.resourceUsages.registerResource(texture)
        
        let args : FrameGraphCommand.SetTextureArgs = (.nil, texture.handle)
        
        self.resourceBindingCommands.append(
            (key, .setTexture(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    public func setArgumentBuffer(_ argumentBuffer: ArgumentBuffer?, key: FunctionArgumentKey) {
        guard let argumentBuffer = argumentBuffer else { return }
        
        self.pendingArgumentBuffers.append((key, argumentBuffer))
        self.needsUpdateBindings = true
    }
    
    func updateResourceUsages(endingEncoding: Bool = false) {
        guard self.needsUpdateBindings || endingEncoding else {
            return
        }
        defer { self.needsUpdateBindings = false }
        
        let lastUsageIndex = self.lastGPUCommandIndex
        
        if self.pipelineStateChanged || endingEncoding {
            defer { self.pipelineStateChanged = false }
            
            // The pipeline state has changed, so some bindings may have become inactive.
            // Check through all active bindings to make sure they're still active; if not, end their usage.
            
            for (path, (_, usageNode)) in self.boundResources {
                if endingEncoding || !RenderBackend.bindingIsActive(at: path) {
                    usageNode.pointee.element.commandRangeInPass = Range(usageNode.pointee.element.commandRangeInPass.lowerBound...lastUsageIndex)
                }
            }
            
        }
        
        if endingEncoding {
            // We shouldn't bind anything if we're ending encoding; doing so could mean we bind invalid resources
            // and then are unable to materialise them within the backends' resource registries since their lifetime
            // has already expired.
            return
        }
        
        let firstCommandOffset = self.nextCommandOffset
        
        var unusedCommands = [(FunctionArgumentKey, FrameGraphCommand)]()
        
        for (key, command) in self.resourceBindingCommands {
            guard let bindingPath = key.computedBindingPath, let reflection = RenderBackend.argumentReflection(at: bindingPath), reflection.isActive else {
                unusedCommands.append((key, command))
                // print("No binding was found for key \(key.stringValue)")
                continue
            }
            
            self.commandRecorder.commands.append(command)
            
            let argsPtr : UnsafeMutableRawPointer
            let identifier : ObjectIdentifier
            switch command {
            case .setSamplerState(let args):
                if let (previousArgsOpt, _) = self.boundResources[reflection.bindingPath], let previousArgs = previousArgsOpt?.assumingMemoryBound(to: FrameGraphCommand.SetSamplerStateArgs.self) {
                    if previousArgs.pointee.descriptor == args.pointee.descriptor { // Ignore the duplicate binding.
                        self.commandRecorder.commands.removeLast()
                        continue
                    }
                }

                UnsafeMutablePointer(mutating: args).pointee.bindingPath = reflection.bindingPath
                continue
                
            case .setBytes(let args):
                UnsafeMutablePointer(mutating: args).pointee.bindingPath = reflection.bindingPath
                continue
                
            case .setBufferOffset(let args):
                UnsafeMutablePointer(mutating: args).pointee.bindingPath = reflection.bindingPath

                guard let (setBufferArgsRaw, _) = self.boundResources[reflection.bindingPath] else {
                    assertionFailure("No buffer bound when setBufferOffset was called for key \(key).")
                    continue
                }
                let setBufferArgs = setBufferArgsRaw!.assumingMemoryBound(to: FrameGraphCommand.SetBufferArgs.self)
                
                let handle = setBufferArgs.pointee.handle
                UnsafeMutablePointer(mutating: args).pointee.handle = handle
                setBufferArgs.pointee.hasDynamicOffset = true

                continue
                
            case .setBuffer(let args):
                if let (previousArgsOpt, _) = self.boundResources[reflection.bindingPath], let previousArgs = previousArgsOpt?.assumingMemoryBound(to: FrameGraphCommand.SetBufferArgs.self) {
                    if previousArgs.pointee.handle == args.pointee.handle { // Ignore the duplicate binding.
                        if previousArgs.pointee.offset == args.pointee.offset {
                            self.commandRecorder.commands.removeLast()
                            continue
                        } /* else {
                            // TODO: translate duplicate setBuffer calls into setBufferOffset.
                        }*/
                    }
                }


                identifier = args.pointee.handle
                UnsafeMutablePointer(mutating: args).pointee.bindingPath = reflection.bindingPath
                argsPtr = UnsafeMutableRawPointer(mutating: args)

            case .setTexture(let args):
                 if let (previousArgsOpt, _) = self.boundResources[reflection.bindingPath], let previousArgs = previousArgsOpt?.assumingMemoryBound(to: FrameGraphCommand.SetTextureArgs.self) {
                    if previousArgs.pointee.handle == args.pointee.handle { // Ingore the duplicate binding.
                        self.commandRecorder.commands.removeLast()
                        continue
                    }
                }

                identifier = args.pointee.handle
                UnsafeMutablePointer(mutating: args).pointee.bindingPath = reflection.bindingPath
                argsPtr = UnsafeMutableRawPointer(mutating: args)
                
            default:
                fatalError()
            }
            
            let node = self.resourceUsages.resourceUsageNode(for: identifier, encoder: self, usageType: reflection.usageType, stages: reflection.stages, inArgumentBuffer: false, firstCommandOffset: firstCommandOffset)
            
            if let (_, currentlyBoundNode) = self.boundResources.removeValue(forKey: reflection.bindingPath) {
                currentlyBoundNode.pointee.element.commandRangeInPass = Range(currentlyBoundNode.pointee.element.commandRangeInPass.lowerBound...lastUsageIndex)
            }
            
            self.boundResources[reflection.bindingPath] = (argsPtr, node)
        }
        
        self.resourceBindingCommands.removeAll(keepingCapacity: true)
        self.resourceBindingCommands.append(contentsOf: unusedCommands)
        
        var unusedArgumentBuffers = [(FunctionArgumentKey, ArgumentBuffer)]()
        
        for (key, argumentBuffer) in self.pendingArgumentBuffers {
            guard let argumentBufferPath = (key.bindingPath ?? RenderBackend.bindingPath(argumentBuffer: argumentBuffer, argumentName: key.stringValue)) else {
                unusedArgumentBuffers.append((key, argumentBuffer))
                // print("No binding was found for argument buffer key \(key.stringValue)")
                continue
            }
            
            argumentBuffer.translateEnqueuedBindings { (key, arrayIndex, resource) in
                let renderAPIResource : Resource?
                switch resource {
                case .buffer(let buffer, _):
                    renderAPIResource = buffer
                case .texture(let texture):
                    renderAPIResource = texture
                default:
                    renderAPIResource = nil
                }
                
                guard let bindingPath = key.bindingPath(argumentBufferPath: argumentBufferPath, arrayIndex: arrayIndex), let reflection = RenderBackend.argumentReflection(at: bindingPath), reflection.isActive else {
                    
                    if let identifier = renderAPIResource?.handle {
                        // print("Resource \(renderAPIResource) with key \(key) is not used.")
                        let _ = self.resourceUsages.resourceUsageNode(for: identifier, encoder: self, usageType: .argumentBufferUnused, stages: [], inArgumentBuffer: true, firstCommandOffset: firstCommandOffset)
                    }
                    
                    return nil
                }
                
                let identifier : ObjectIdentifier
                if let renderAPIResource = renderAPIResource {
                    identifier = renderAPIResource.handle
                    self.resourceUsages.registerResource(renderAPIResource)
                } else {
                    return bindingPath
                }
                
                let node = self.resourceUsages.resourceUsageNode(for: identifier, encoder: self, usageType: reflection.usageType, stages: reflection.stages, inArgumentBuffer: true, firstCommandOffset: firstCommandOffset)
                
                if let (_, currentlyBoundNode) = self.boundResources.removeValue(forKey: bindingPath) {
                    currentlyBoundNode.pointee.element.commandRangeInPass = Range(currentlyBoundNode.pointee.element.commandRangeInPass.lowerBound...lastUsageIndex)
                }
                
                self.boundResources[bindingPath] = (nil, node)
                
                return bindingPath
            }
            
            let unmanagedArgBuffer = Unmanaged.passRetained(argumentBuffer)
            self.commandRecorder.unmanagedReferences.append(unmanagedArgBuffer)
            
            (commandRecorder << (argumentBufferPath, unmanagedArgBuffer)) << FrameGraphCommand.setArgumentBuffer
            
        }
        
        self.pendingArgumentBuffers.removeAll(keepingCapacity: true)
        self.pendingArgumentBuffers.append(contentsOf: unusedArgumentBuffers)
    }
    
    public func endEncoding() {
        self.updateResourceUsages(endingEncoding: true)
    }
}

extension ResourceBindingEncoder {
    
    public func setValue<T>(_ value: T, key: FunctionArgumentKey) {
        var value = value
        withUnsafeBytes(of: &value) { bytes in
            self.setBytes(bytes.baseAddress!, length: bytes.count, key: key)
        }
    }
    
    public func setArguments<A : Encodable>(_ arguments: A) {
        let encoder = FunctionArgumentEncoder(commandEncoder: self)
        try! encoder.encode(arguments)
    }
    
}

public final class RenderCommandEncoder : ResourceBindingEncoder {
    
    enum Attachment : Hashable {
        case color(Int)
        case depth
        case stencil
    }
    
    let drawRenderPass : DrawRenderPass
    
    var boundVertexBuffers = [ResourceUsageNodePtr?](repeating: nil, count: 8)
    var renderTargetAttachmentUsages = [Attachment : ResourceUsageNodePtr]()
    
    var renderPipelineDescriptor : RenderPipelineDescriptor? = nil
    var depthStencilDescriptor : DepthStencilDescriptor? = nil
    
    var gpuCommandsStartIndexColor : Int? = nil
    var gpuCommandsStartIndexDepthStencil : Int? = nil

    init(commandRecorder: FrameGraphCommandRecorder, resourceUsages: ResourceUsages, renderPass: DrawRenderPass, passRecord: RenderPassRecord) {
        self.drawRenderPass = renderPass
        super.init(commandRecorder: commandRecorder, resourceUsages: resourceUsages, passRecord: passRecord)
        
        assert(passRecord.pass === renderPass)
        
        for (i, attachment) in renderPass.renderTargetDescriptor.colorAttachments.enumerated() {
            guard let attachment = attachment else { continue }
            self.resourceUsages.registerResource(attachment.texture)
            
            if attachment.wantsClear {
                let usageNode = self.resourceUsages.resourceUsageNode(for: attachment.texture.handle, encoder: self, usageType: .writeOnlyRenderTarget, stages: .fragment, inArgumentBuffer: false, firstCommandOffset: 0)
                self.renderTargetAttachmentUsages[.color(i)] = usageNode
            }
        }
        
        if let depthAttachment = renderPass.renderTargetDescriptor.depthAttachment {
            self.resourceUsages.registerResource(depthAttachment.texture)
            
            if depthAttachment.wantsClear {
                let usageNode = self.resourceUsages.resourceUsageNode(for: depthAttachment.texture.handle, encoder: self, usageType: .writeOnlyRenderTarget, stages: .vertex, inArgumentBuffer: false, firstCommandOffset: 0)
                self.renderTargetAttachmentUsages[.depth] = usageNode
            }
        }
        
        if let stencilAttachment = renderPass.renderTargetDescriptor.stencilAttachment {
            self.resourceUsages.registerResource(stencilAttachment.texture)
            
            if stencilAttachment.wantsClear, !(renderPass.renderTargetDescriptor.depthAttachment?.wantsClear ?? false) {
                let usageNode = self.resourceUsages.resourceUsageNode(for: stencilAttachment.texture.handle, encoder: self, usageType: .writeOnlyRenderTarget, stages: .vertex, inArgumentBuffer: false, firstCommandOffset: 0)
                self.renderTargetAttachmentUsages[.stencil] = usageNode
            }
        }
    }
    
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
                usageNode.pointee.element.type = type == .readWriteRenderTarget ? type : usageNode.pointee.element.type
                usageNode.pointee.element.commandRangeInPass = usageNode.pointee.element.commandRangeInPass.lowerBound..<self.lastGPUCommandIndex // extend the usage's timeline
                continue
            }
            
            let usageNode = self.resourceUsages.resourceUsageNode(for: attachment.texture.handle, encoder: self, usageType: type, stages: .fragment, inArgumentBuffer: false, firstCommandOffset: gpuCommandsStartIndex)
            usageNode.pointee.element.commandRangeInPass = gpuCommandsStartIndex..<self.lastGPUCommandIndex
            self.renderTargetAttachmentUsages[.color(i)] = usageNode
        }
    }
    
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
                usageNode.pointee.element.type = type == .readWriteRenderTarget ? type : usageNode.pointee.element.type
                usageNode.pointee.element.commandRangeInPass = usageNode.pointee.element.commandRangeInPass.lowerBound..<self.lastGPUCommandIndex // extend the usage's timeline
                break depthCheck
            }
            
            let usageNode = self.resourceUsages.resourceUsageNode(for: depthAttachment.texture.handle, encoder: self, usageType: type, stages: .vertex, inArgumentBuffer: false, firstCommandOffset: gpuCommandsStartIndex)
            usageNode.pointee.element.commandRangeInPass = gpuCommandsStartIndex..<self.lastGPUCommandIndex
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
                usageNode.pointee.element.type = type == .readWriteRenderTarget ? type : usageNode.pointee.element.type
                usageNode.pointee.element.commandRangeInPass = usageNode.pointee.element.commandRangeInPass.lowerBound..<self.lastGPUCommandIndex // extend the usage's timeline
                break stencilCheck
            }
            
            let usageNode = self.resourceUsages.resourceUsageNode(for: stencilAttachment.texture.handle, encoder: self, usageType: type, stages: .vertex, inArgumentBuffer: false, firstCommandOffset: gpuCommandsStartIndex)
            usageNode.pointee.element.commandRangeInPass = gpuCommandsStartIndex..<self.lastGPUCommandIndex
            self.renderTargetAttachmentUsages[.stencil] = usageNode
        }
    }
    
    public var label : String = "" {
        didSet {
            commandRecorder.setLabel(label)
        }
    }
    
    public func setRenderPipelineState(_ descriptor: RenderPipelineDescriptor) {
        self.renderPipelineDescriptor = descriptor
        
        RenderBackend.setReflectionRenderPipeline(descriptor: descriptor, renderTarget: self.drawRenderPass.renderTargetDescriptor)
        self.pipelineStateChanged = true
        self.needsUpdateBindings = true

        let box = Unmanaged.passRetained(ReferenceBox(descriptor))
        commandRecorder.unmanagedReferences.append(box)
        commandRecorder << FrameGraphCommand.setRenderPipelineState(box)
        
        self.updateColorAttachmentUsages()
    }
    
    public func setVertexBuffer(_ buffer: Buffer?, offset: Int, index: Int) {
        if let currentBinding = self.boundVertexBuffers[index] {
            currentBinding.pointee.element.commandRangeInPass = currentBinding.pointee.element.commandRangeInPass.lowerBound..<self.nextCommandOffset
        }
        
        guard let buffer = buffer else { return }
        
        self.resourceUsages.registerResource(buffer)
        let newUsageNode = self.resourceUsages.resourceUsageNode(for: buffer.handle, encoder: self, usageType: .vertexBuffer, stages: .vertex, inArgumentBuffer: false, firstCommandOffset: self.nextCommandOffset)
        self.boundVertexBuffers[index] = newUsageNode
        
        (commandRecorder << (buffer.handle, UInt32(offset), UInt32(index))) << FrameGraphCommand.setVertexBuffer
    }
    
    public func setVertexBufferOffset(_ offset: Int, index: Int) {
        commandRecorder << FrameGraphCommand.setVertexBufferOffset(offset: UInt32(offset), index: UInt32(index))
    }

    public func setViewport(_ viewport: Viewport) {
        (commandRecorder << viewport) << FrameGraphCommand.setViewport
    }
    
    public func setFrontFacing(_ frontFacingWinding: Winding) {
        commandRecorder << .setFrontFacing(frontFacingWinding)
    }
    
    public func setCullMode(_ cullMode: CullMode) {
        commandRecorder << .setCullMode(cullMode)
    }
    
    public func setDepthStencilState(_ descriptor: DepthStencilDescriptor?) {
        self.depthStencilDescriptor = descriptor
        
        let box = Unmanaged.passRetained(ReferenceBox(descriptor))
        commandRecorder.unmanagedReferences.append(box)
        commandRecorder << FrameGraphCommand.setDepthStencilState(box)
        
        self.updateDepthStencilAttachmentUsages()
    }
    
    public func setScissorRect(_ rect: ScissorRect) {
        (commandRecorder << rect) << FrameGraphCommand.setScissorRect
    }
    
    public func setDepthClipMode(_ depthClipMode: DepthClipMode) {
        commandRecorder << .setDepthClipMode(depthClipMode)
    }
    
    public func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float) {
        (commandRecorder << (depthBias, slopeScale, clamp)) << FrameGraphCommand.setDepthBias
    }
    
    public func setStencilReferenceValue(_ referenceValue: UInt32) {
        commandRecorder << .setStencilReferenceValue(referenceValue)
    }
    
    public func setStencilReferenceValues(front frontReferenceValue: UInt32, back backReferenceValue: UInt32) {
        commandRecorder << .setStencilReferenceValues(front: frontReferenceValue, back: backReferenceValue)
    }
    
    public func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int = 1, baseInstance: Int = 0) {
        self.updateResourceUsages()
        self.gpuCommandsStartIndexColor = self.gpuCommandsStartIndexColor ?? self.nextCommandOffset
        self.gpuCommandsStartIndexDepthStencil = self.gpuCommandsStartIndexDepthStencil ?? self.nextCommandOffset
        self.lastGPUCommandIndex = self.nextCommandOffset
        
        (commandRecorder << (primitiveType, UInt32(vertexStart), UInt32(vertexCount), UInt32(instanceCount), UInt32(baseInstance))) << FrameGraphCommand.drawPrimitives
    }
    
    public func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int = 1, baseVertex: Int = 0, baseInstance: Int = 0) {
        self.updateResourceUsages()
        self.gpuCommandsStartIndexColor = self.gpuCommandsStartIndexColor ?? self.nextCommandOffset
        self.gpuCommandsStartIndexDepthStencil = self.gpuCommandsStartIndexDepthStencil ?? self.nextCommandOffset
        self.lastGPUCommandIndex = self.nextCommandOffset
        
        self.resourceUsages.addResourceUsage(for: indexBuffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .indexBuffer, stages: .vertex, inArgumentBuffer: false)
        
        (commandRecorder << (primitiveType, UInt32(indexCount), indexType, indexBuffer.handle, UInt32(indexBufferOffset), UInt32(instanceCount), Int32(baseVertex), UInt32(baseInstance))) << FrameGraphCommand.drawIndexedPrimitives
    }
    
    override func updateResourceUsages(endingEncoding: Bool = false) {
        super.updateResourceUsages(endingEncoding: endingEncoding)
        
        if endingEncoding {
            for usageNode in self.boundVertexBuffers {
                guard let usageNode = usageNode else { continue }
                usageNode.pointee.element.commandRangeInPass = usageNode.pointee.element.commandRangeInPass.lowerBound..<self.lastGPUCommandIndex
            }
            
            self.updateColorAttachmentUsages()
            self.updateDepthStencilAttachmentUsages()
        }
    }
}


public final class ComputeCommandEncoder : ResourceBindingEncoder {
    
    let computeRenderPass : ComputeRenderPass
    
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
    
    public func setComputePipelineState(_ descriptor: ComputePipelineDescriptor) {
        RenderBackend.setReflectionComputePipeline(descriptor: descriptor)
        self.pipelineStateChanged = true
        self.needsUpdateBindings = true
        
        let box = Unmanaged.passRetained(ReferenceBox(descriptor))
        commandRecorder.unmanagedReferences.append(box)
        commandRecorder << .setComputePipelineState(box)
    }
    
    public func setStageInRegion(_ region: Region) {
        (commandRecorder << region) << FrameGraphCommand.setStageInRegion
    }
    
    public func setThreadgroupMemoryLength(_ length: Int, index: Int) {
        commandRecorder << .setThreadgroupMemoryLength(length: UInt32(length), index: UInt32(index))
    }
    
    public func dispatchThreadgroups(_ threadgroupsPerGrid: Size, threadsPerThreadgroup: Size) {
        self.updateResourceUsages()
        self.lastGPUCommandIndex = self.nextCommandOffset
        
        (commandRecorder << (threadgroupsPerGrid, threadsPerThreadgroup)) << FrameGraphCommand.dispatchThreadgroups
    }
    
    public func dispatchThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size) {
        self.updateResourceUsages()
        self.lastGPUCommandIndex = self.nextCommandOffset
        
        self.resourceUsages.addResourceUsage(for: indirectBuffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .indirectBuffer, stages: .vertex, inArgumentBuffer: false)
        
        (commandRecorder << (indirectBuffer.handle, UInt32(indirectBufferOffset), threadsPerThreadgroup)) << FrameGraphCommand.dispatchThreadgroupsIndirect
    }
}

public final class BlitCommandEncoder : CommandEncoder {

    public let commandRecorder : FrameGraphCommandRecorder
    public let passRecord: RenderPassRecord
    public let startCommandIndex: Int
    let resourceUsages : ResourceUsages
    let blitRenderPass : BlitRenderPass
    
    init(commandRecorder: FrameGraphCommandRecorder, resourceUsages: ResourceUsages, renderPass: BlitRenderPass, passRecord: RenderPassRecord) {
        self.commandRecorder = commandRecorder
        self.resourceUsages = resourceUsages
        self.blitRenderPass = renderPass
        self.passRecord = passRecord
        self.startCommandIndex = self.commandRecorder.nextCommandIndex
        
        assert(passRecord.pass === renderPass)
    }
    
    public func endEncoding() {
        // Nothing to do.
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
        
        (commandRecorder << (sourceBuffer.handle, UInt32(sourceOffset), UInt32(sourceBytesPerRow), UInt32(sourceBytesPerImage), sourceSize, destinationTexture.handle, UInt32(destinationSlice), UInt32(destinationLevel), destinationOrigin, options)) << FrameGraphCommand.copyBufferToTexture
    }
    
    public func copy(from sourceBuffer: Buffer, sourceOffset: Int, to destinationBuffer: Buffer, destinationOffset: Int, size: Int) {
        let commandOffset = self.nextCommandOffset
        
        resourceUsages.addResourceUsage(for: sourceBuffer, commandIndex: commandOffset, encoder: self, usageType: .blitSource, stages: .blit, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: destinationBuffer, commandIndex: commandOffset, encoder: self, usageType: .blitDestination, stages: .blit, inArgumentBuffer: false)
        
        (commandRecorder << (sourceBuffer.handle, UInt32(sourceOffset), destinationBuffer.handle, UInt32(destinationOffset), UInt32(size))) << FrameGraphCommand.copyBufferToBuffer
    }
    
    public func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationBuffer: Buffer, destinationOffset: Int, destinationBytesPerRow: Int, destinationBytesPerImage: Int, options: BlitOption = []) {
        let commandOffset = self.nextCommandOffset
        
        resourceUsages.addResourceUsage(for: sourceTexture, commandIndex: commandOffset, encoder: self, usageType: .blitSource, stages: .blit, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: destinationBuffer, commandIndex: commandOffset, encoder: self, usageType: .blitDestination, stages: .blit, inArgumentBuffer: false)
        
        (commandRecorder << (sourceTexture.handle, UInt32(sourceSlice), UInt32(sourceLevel), sourceOrigin, sourceSize, destinationBuffer.handle, UInt32(destinationOffset), UInt32(destinationBytesPerRow), UInt32(destinationBytesPerImage), options)) << FrameGraphCommand.copyTextureToBuffer
    }
    
    public func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin) {
        let commandOffset = self.nextCommandOffset
        
        resourceUsages.addResourceUsage(for: sourceTexture, commandIndex: commandOffset, encoder: self, usageType: .blitSource, stages: .blit, inArgumentBuffer: false)
        resourceUsages.addResourceUsage(for: destinationTexture, commandIndex: commandOffset, encoder: self, usageType: .blitDestination, stages: .blit, inArgumentBuffer: false)
        
        (commandRecorder << (sourceTexture.handle, UInt32(sourceSlice), UInt32(sourceLevel), sourceOrigin, sourceSize, destinationTexture.handle, UInt32(destinationSlice), UInt32(destinationLevel), destinationOrigin)) << FrameGraphCommand.copyTextureToTexture
    }
    
    public func fill(buffer: Buffer, range: Range<Int>, value: UInt8) {
        resourceUsages.addResourceUsage(for: buffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitDestination, stages: .blit, inArgumentBuffer: false)
        
        (commandRecorder << (buffer.handle, range, value)) << FrameGraphCommand.fillBuffer
    }
    
    public func generateMipmaps(for texture: Texture) {
        resourceUsages.addResourceUsage(for: texture, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitSynchronisation, stages: .blit, inArgumentBuffer: false)
        
        commandRecorder << .generateMipmaps(texture.handle)
    }
    
    public func synchronize(buffer: Buffer) {
        resourceUsages.addResourceUsage(for: buffer, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitSynchronisation, stages: .blit, inArgumentBuffer: false)
        
        commandRecorder << .synchroniseBuffer(buffer.handle)
    }
    
    public func synchronize(texture: Texture) {
        resourceUsages.addResourceUsage(for: texture, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitSynchronisation, stages: .blit, inArgumentBuffer: false)
        commandRecorder << .synchroniseTexture(texture.handle)
    }
    
    public func synchronize(texture: Texture, slice: Int, level: Int) {
        resourceUsages.addResourceUsage(for: texture, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitSynchronisation, stages: .blit, inArgumentBuffer: false)
        (commandRecorder << (texture.handle, UInt32(slice), UInt32(level))) << FrameGraphCommand.synchroniseTextureSlice
    }
}
