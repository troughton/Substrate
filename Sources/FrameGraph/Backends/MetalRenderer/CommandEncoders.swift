//
//  CommandEncoders.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 25/12/17.
//

import SwiftFrameGraph
import Metal
import Utilities

final class EncoderManager {
    
    static let useParallelEncoding = false
    
    private let commandBuffer : MTLCommandBuffer
    private let resourceRegistry : ResourceRegistry
    private var previousRenderTarget : MetalRenderTargetDescriptor? = nil
    
    private var renderEncoder : FGMTLRenderCommandEncoder? = nil
    private var computeEncoder : FGMTLComputeCommandEncoder? = nil
    private var blitEncoder : FGMTLBlitCommandEncoder? = nil
    
    init(commandBuffer: MTLCommandBuffer, resourceRegistry: ResourceRegistry) {
        self.commandBuffer = commandBuffer
        self.resourceRegistry = resourceRegistry
    }
    
    static func sharesCommandEncoders(_ passA: RenderPassRecord, _ passB: RenderPassRecord, passes: [RenderPassRecord], renderTargetDescriptors: [MetalRenderTargetDescriptor?]) -> Bool {
        if passA.passIndex == passB.passIndex {
            return true
        }
        if passA.pass.passType == .draw, renderTargetDescriptors[passA.passIndex] === renderTargetDescriptors[passB.passIndex] {
            return true
        }
        
        return false
    }
    
    static func generateCommandEncoderIndices(passes: [RenderPassRecord], renderTargetDescriptors: [MetalRenderTargetDescriptor?]) -> ([Int], [String], count: Int) {
        var encoderIndex = 0
        var passEncoderIndices = [Int](repeating: 0, count: passes.count)
        
        for (i, pass) in passes.enumerated().dropFirst() {
            let previousPass = passes[i - 1]
            assert(pass.passIndex != previousPass.passIndex)
            
            if pass.pass.passType != .draw || renderTargetDescriptors[previousPass.passIndex] !== renderTargetDescriptors[pass.passIndex] {
                encoderIndex += 1
            }
            
            passEncoderIndices[i] = encoderIndex
        }
        
        let commandEncoderCount = encoderIndex + 1
        
        var commandEncoderNames = [String](repeating: "", count: commandEncoderCount)
        
        var startIndex = 0
        for i in 0..<commandEncoderCount {
            let endIndex = passEncoderIndices[startIndex...].firstIndex(where: { $0 != i }) ?? passEncoderIndices.endIndex
            
            if endIndex - startIndex <= 3 {
                let applicablePasses = passes[startIndex..<endIndex].lazy.map { $0.pass.name }.joined(separator: ", ")
                commandEncoderNames[i] = applicablePasses
            } else {
                commandEncoderNames[i] = "[\(passes[startIndex].pass.name)...\(passes[endIndex - 1].pass.name)] (\(endIndex - startIndex) passes)"
            }
            startIndex = endIndex
        }
        
        return (passEncoderIndices, commandEncoderNames, encoderIndex + 1)
    }
    
    func renderCommandEncoder(descriptor: MetalRenderTargetDescriptor, textureUsages: [Texture : TextureUsageProperties], commands: [FrameGraphCommand], resourceCommands: [ResourceCommand], resourceRegistry: ResourceRegistry, stateCaches: StateCaches) -> FGMTLRenderCommandEncoder? {
        if descriptor === previousRenderTarget, let renderEncoder = self.renderEncoder {
            return renderEncoder
        } else {
            self.previousRenderTarget = descriptor
            
            self.renderEncoder?.endEncoding()
            self.renderEncoder = nil
            
            self.computeEncoder?.endEncoding()
            self.computeEncoder = nil
            
            self.blitEncoder?.endEncoding()
            self.blitEncoder = nil
            
            let mtlDescriptor : MTLRenderPassDescriptor
            do {
                mtlDescriptor = try MTLRenderPassDescriptor(descriptor, resourceRegistry: self.resourceRegistry)
            } catch {
                return nil
            }
            
            let renderEncoder : FGMTLRenderCommandEncoder = EncoderManager.useParallelEncoding ? FGMTLParallelRenderCommandEncoder(encoder: commandBuffer.makeParallelRenderCommandEncoder(descriptor: mtlDescriptor)!, renderPassDescriptor: mtlDescriptor) : FGMTLThreadRenderCommandEncoder(encoder: commandBuffer.makeRenderCommandEncoder(descriptor: mtlDescriptor)!, renderPassDescriptor: mtlDescriptor)
            self.renderEncoder = renderEncoder
            return renderEncoder
        }
    }
    
    func computeCommandEncoder() -> FGMTLComputeCommandEncoder {
        self.renderEncoder?.endEncoding()
        self.renderEncoder = nil
        self.previousRenderTarget = nil
        
        self.computeEncoder?.endEncoding()
        self.computeEncoder = nil
        
        self.blitEncoder?.endEncoding()
        self.blitEncoder = nil
        
        let mtlComputeEncoder : MTLComputeCommandEncoder
        if #available(OSX 10.14, *) {
            mtlComputeEncoder = commandBuffer.makeComputeCommandEncoder(dispatchType: .serial)!
        } else {
            mtlComputeEncoder = commandBuffer.makeComputeCommandEncoder()!
        }
        
        let computeEncoder = FGMTLComputeCommandEncoder(encoder: mtlComputeEncoder)
        self.computeEncoder = computeEncoder
        return computeEncoder
    }
    
    func blitCommandEncoder() -> FGMTLBlitCommandEncoder {
        self.renderEncoder?.endEncoding()
        self.renderEncoder = nil
        self.previousRenderTarget = nil
        
        self.computeEncoder?.endEncoding()
        self.computeEncoder = nil
        
        self.blitEncoder?.endEncoding()
        self.blitEncoder = nil
        
        let blitEncoder = FGMTLBlitCommandEncoder(encoder: commandBuffer.makeBlitCommandEncoder()!)
        self.blitEncoder = blitEncoder
        return blitEncoder
    }
    
    func externalCommandEncoder() -> FGMTLExternalCommandEncoder {
        self.renderEncoder?.endEncoding()
        self.renderEncoder = nil
        self.previousRenderTarget = nil
        
        self.computeEncoder?.endEncoding()
        self.computeEncoder = nil
        
        self.blitEncoder?.endEncoding()
        self.blitEncoder = nil
        
        return FGMTLExternalCommandEncoder(commandBuffer: self.commandBuffer)
    }
    
    func endEncoding() {
        self.renderEncoder?.endEncoding()
        self.renderEncoder = nil
        self.previousRenderTarget = nil
        
        self.computeEncoder?.endEncoding()
        self.computeEncoder = nil
        
        self.blitEncoder?.endEncoding()
        self.blitEncoder = nil
    }
}

struct BufferOffsetKey : Hashable {
    var stage : MTLRenderStages
    var index : Int
    
    var hashValue: Int {
        return self.index &* 51 &+ Int(stage.rawValue)
    }
}

protocol FGMTLCommandEncoder : class {
    associatedtype Encoder
    
    func waitForFence(_ fence: MTLFence, beforeStages: MTLRenderStages?, encoder: Encoder)
    func updateFence(_ fence: MTLFence, afterStages: MTLRenderStages?, encoder: Encoder)
    
    func memoryBarrier(resource: MTLResource, afterStages: MTLRenderStages?, beforeStages: MTLRenderStages?, encoder: Encoder)
    
    func endEncoding()
}

extension FGMTLCommandEncoder {
    
    func checkResourceCommands(_ resourceCommands: [ResourceCommand], resourceCommandIndex: inout Int, phase: PerformOrder, commandIndex: Int, resourceRegistry: ResourceRegistry, encoder: Encoder) {
        var hasPerformedTextureBarrier = false
        while resourceCommandIndex < resourceCommands.count, commandIndex == resourceCommands[resourceCommandIndex].index, phase == resourceCommands[resourceCommandIndex].order {
            defer { resourceCommandIndex += 1 }
            
            switch resourceCommands[resourceCommandIndex].command {
                
            case .memoryBarrier(let resource, let afterStages, let beforeStages):
                if let texture = resource.texture {
                    self.memoryBarrier(resource: resourceRegistry[texture]!, afterStages: afterStages, beforeStages: beforeStages, encoder: encoder)
                } else if let buffer = resource.buffer {
                    self.memoryBarrier(resource: resourceRegistry[buffer]!.buffer, afterStages: afterStages, beforeStages: beforeStages, encoder: encoder)
                }
                
            case .textureBarrier:
                #if os(macOS)
                if !hasPerformedTextureBarrier {
                    (encoder as! MTLRenderCommandEncoder).textureBarrier()
                    hasPerformedTextureBarrier = true
                }
                #else
                break
                #endif
                
            case .updateFence(let fence, let afterStages):
                // TODO: We can combine together multiple fences that update at the same time.
                self.updateFence(fence.fence, afterStages: afterStages, encoder: encoder)
                
            case .waitForFence(let fence, let beforeStages):
                self.waitForFence(fence.fence, beforeStages: beforeStages, encoder: encoder)
                
            case .waitForMultiframeFence(let resource, let resourceType, let waitFence, let beforeStages):
                if case .buffer = resourceType {
                    let bufferRef = resourceRegistry[buffer: resource]!
                    if case .write = waitFence {
                        for fence in bufferRef.usageFences.writeWaitFences {
                            self.waitForFence(fence.fence, beforeStages: beforeStages, encoder: encoder)
                        }
                    } else {
                        for fence in bufferRef.usageFences.readWaitFences {
                            self.waitForFence(fence.fence, beforeStages: beforeStages, encoder: encoder)
                        }
                    }
                } else {
                    let textureRef = resourceRegistry[textureReference: resource]!
                    if case .write = waitFence {
                        for fence in textureRef.usageFences.writeWaitFences {
                            self.waitForFence(fence.fence, beforeStages: beforeStages, encoder: encoder)
                        }
                    } else {
                        for fence in textureRef.usageFences.readWaitFences {
                            self.waitForFence(fence.fence, beforeStages: beforeStages, encoder: encoder)
                        }
                    }
                }
                
            case .useResource(let resource, let usage):
                var mtlResource : MTLResource
                
                if let texture = resource.texture {
                    mtlResource = resourceRegistry[texture]!
                } else if let buffer = resource.buffer {
                    mtlResource = resourceRegistry[buffer]!.buffer
                } else {
                    preconditionFailure()
                }
                
                if let encoder = encoder as? MTLRenderCommandEncoder {
                    encoder.__use(&mtlResource, count: 1, usage: usage)
                } else if let encoder = encoder as? MTLComputeCommandEncoder {
                    encoder.__use(&mtlResource, count: 1, usage: usage)
                }
                
                
            default:
                fatalError()
            }
            
        }
    }
}

protocol FGMTLRenderCommandEncoder : class {
    var label : String? { get set }
    func executePass(commands: ArraySlice<FrameGraphCommand>, resourceCommands: [ResourceCommand], renderTarget: _RenderTargetDescriptor, passRenderTarget: _RenderTargetDescriptor, resourceRegistry: ResourceRegistry, stateCaches: StateCaches)
    func endEncoding()
}

public final class FGMTLParallelRenderCommandEncoder : FGMTLRenderCommandEncoder {
    static let commandCountThreshold = Int.max // 512
    
    let parallelEncoder: MTLParallelRenderCommandEncoder
    let renderPassDescriptor : MTLRenderPassDescriptor
    
    let dispatchGroup = DispatchGroup()
    var currentEncoder : FGMTLRenderCommandEncoder? = nil
    
    init(encoder: MTLParallelRenderCommandEncoder, renderPassDescriptor: MTLRenderPassDescriptor) {
        self.parallelEncoder = encoder
        self.renderPassDescriptor = renderPassDescriptor
    }
    
    var label: String? {
        get {
            return self.parallelEncoder.label
        }
        set {
            self.parallelEncoder.label = newValue
        }
    }
    
    func executePass(commands: ArraySlice<FrameGraphCommand>, resourceCommands: [ResourceCommand], renderTarget: _RenderTargetDescriptor, passRenderTarget: _RenderTargetDescriptor, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        if commands.count < FGMTLParallelRenderCommandEncoder.commandCountThreshold {
            if let currentEncoder = currentEncoder {
                currentEncoder.executePass(commands: commands, resourceCommands: resourceCommands, renderTarget: renderTarget, passRenderTarget: passRenderTarget, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
            } else {
                let encoder = self.parallelEncoder.makeRenderCommandEncoder()!
                let fgEncoder = FGMTLThreadRenderCommandEncoder(encoder: encoder, renderPassDescriptor: renderPassDescriptor)
                
                fgEncoder.executePass(commands: commands, resourceCommands: resourceCommands, renderTarget: renderTarget, passRenderTarget: passRenderTarget, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
                
                self.currentEncoder = fgEncoder
            }
        } else {
            // Execute in parallel if the workload is large enough.
            
            self.currentEncoder?.endEncoding()
            self.currentEncoder = nil
            
            let encoder = self.parallelEncoder.makeRenderCommandEncoder()!
            let fgEncoder = FGMTLThreadRenderCommandEncoder(encoder: encoder, renderPassDescriptor: renderPassDescriptor)
            
            DispatchQueue.global().async(group: self.dispatchGroup) {
                fgEncoder.executePass(commands: commands, resourceCommands: resourceCommands, renderTarget: renderTarget, passRenderTarget: passRenderTarget, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
                fgEncoder.endEncoding()
            }
        }
        
    }
    
    func endEncoding() {
        self.currentEncoder?.endEncoding()
        
        self.dispatchGroup.wait()
        self.parallelEncoder.endEncoding()
    }
}

public final class FGMTLThreadRenderCommandEncoder : FGMTLCommandEncoder, FGMTLRenderCommandEncoder {
    let encoder: MTLRenderCommandEncoder
    
    struct FenceWaitKey : Hashable {
        var fence : ObjectIdentifier
        var stages : MTLRenderStages.RawValue
        
        init(fence: MTLFence, stages: MTLRenderStages) {
            self.fence = ObjectIdentifier(fence)
            self.stages = stages.rawValue
        }
    }
    
    let renderPassDescriptor : MTLRenderPassDescriptor
    var pipelineDescriptor : _RenderPipelineDescriptor? = nil
    var baseBufferOffsets = [BufferOffsetKey : Int]()
    
    var updatedFences = Set<ObjectIdentifier>()
    var waitedOnFences = Set<FenceWaitKey>()
    
    init(encoder: MTLRenderCommandEncoder, renderPassDescriptor: MTLRenderPassDescriptor) {
        self.encoder = encoder
        self.renderPassDescriptor = renderPassDescriptor
    }
    
    var label: String? {
        get {
            return self.encoder.label
        }
        set {
            self.encoder.label = newValue
        }
    }
    
    func executePass(commands: ArraySlice<FrameGraphCommand>, resourceCommands: [ResourceCommand], renderTarget: _RenderTargetDescriptor, passRenderTarget: _RenderTargetDescriptor, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        var resourceCommandIndex = resourceCommands.binarySearch { $0.index < commands.startIndex }
        
        if passRenderTarget.depthAttachment == nil && passRenderTarget.stencilAttachment == nil, (self.renderPassDescriptor.depthAttachment.texture != nil || self.renderPassDescriptor.stencilAttachment.texture != nil) {
            encoder.setDepthStencilState(stateCaches.defaultDepthState) // The render pass unexpectedly has a depth/stencil attachment, so make sure the depth stencil state is set to the default.
        }
        
        for (i, command) in zip(commands.indices, commands) {
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i, resourceRegistry: resourceRegistry, encoder: encoder)
            self.executeCommand(command, encoder: encoder, renderTarget: renderTarget, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i, resourceRegistry: resourceRegistry, encoder: encoder)
        }
    }
    
    func endEncoding() {
        self.encoder.endEncoding()
    }
    
    func executeCommand(_ command: FrameGraphCommand, encoder: MTLRenderCommandEncoder, renderTarget: _RenderTargetDescriptor, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        switch command {
        case .clearRenderTargets:
            break
            
        case .insertDebugSignpost(let cString):
            encoder.insertDebugSignpost(String(cString: cString))
            
        case .setLabel(let label):
            encoder.label = String(cString: label)
            
        case .pushDebugGroup(let groupName):
            encoder.pushDebugGroup(String(cString: groupName))
            
        case .popDebugGroup:
            encoder.popDebugGroup()
            
        case .setBytes(let args):
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let stages = mtlBindingPath.stages
            if stages.contains(.vertex) {
                encoder.setVertexBytes(args.pointee.bytes, length: Int(args.pointee.length), index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                encoder.setFragmentBytes(args.pointee.bytes, length: Int(args.pointee.length), index: mtlBindingPath.bindIndex)
            }
            
        case .setVertexBuffer(let args):
            let mtlBuffer : MTLBufferReference?
            if let bufferHandle = args.pointee.handle {
                mtlBuffer = resourceRegistry[buffer: bufferHandle]
            } else {
                mtlBuffer = nil
            }
            let index = Int(args.pointee.index)
            encoder.setVertexBuffer(mtlBuffer?.buffer, offset: Int(args.pointee.offset) + (mtlBuffer?.offset ?? 0), index: index)
            self.baseBufferOffsets[BufferOffsetKey(stage: .vertex, index: index)] = mtlBuffer?.offset ?? 0
            
        case .setVertexBufferOffset(let offset, let index):
            let baseOffset = self.baseBufferOffsets[BufferOffsetKey(stage: .vertex, index: Int(index))] ?? 0
            encoder.setVertexBufferOffset(Int(offset) + baseOffset, index: Int(index))
            
        case .setArgumentBuffer(let args):
            let bindingPath = args.pointee.bindingPath
            let mtlBindingPath = MetalResourceBindingPath(bindingPath)
            let stages = mtlBindingPath.stages
            
            let argumentBuffer = args.pointee.argumentBuffer
            let mtlArgumentBuffer = resourceRegistry.allocateArgumentBufferIfNeeded(argumentBuffer, bindingPath: bindingPath, encoder: { () -> MTLArgumentEncoder in
                let functionName = stages.contains(.vertex) ? self.pipelineDescriptor!.vertexFunction : self.pipelineDescriptor!.fragmentFunction
                return stateCaches.argumentEncoder(atIndex: mtlBindingPath.bindIndex, functionName: functionName!, functionConstants: self.pipelineDescriptor!.functionConstants)
            }, stateCaches: stateCaches)
            
            if stages.contains(.vertex) {
                encoder.setVertexBuffer(mtlArgumentBuffer.buffer, offset: mtlArgumentBuffer.offset, index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                encoder.setFragmentBuffer(mtlArgumentBuffer.buffer, offset: mtlArgumentBuffer.offset, index: mtlBindingPath.bindIndex)
            }
            
        case .setArgumentBufferArray(let args):
            let bindingPath = args.pointee.bindingPath
            let mtlBindingPath = MetalResourceBindingPath(bindingPath)
            let stages = mtlBindingPath.stages
            
            let argumentBuffer = args.pointee.argumentBuffer
            let mtlArgumentBuffer = resourceRegistry.allocateArgumentBufferArrayIfNeeded(argumentBuffer, bindingPath: bindingPath, encoder: { () -> MTLArgumentEncoder in
                let functionName = stages.contains(.vertex) ? self.pipelineDescriptor!.vertexFunction : self.pipelineDescriptor!.fragmentFunction
                return stateCaches.argumentEncoder(atIndex: mtlBindingPath.bindIndex, functionName: functionName!, functionConstants: self.pipelineDescriptor!.functionConstants)
            }, stateCaches: stateCaches)
            
            if stages.contains(.vertex) {
                encoder.setVertexBuffer(mtlArgumentBuffer.buffer, offset: mtlArgumentBuffer.offset, index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                encoder.setFragmentBuffer(mtlArgumentBuffer.buffer, offset: mtlArgumentBuffer.offset, index: mtlBindingPath.bindIndex)
            }
            
        case .setBuffer(let args):
            let mtlBuffer = resourceRegistry[buffer: args.pointee.handle]
            
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let stages = mtlBindingPath.stages
            if stages.contains(.vertex) {
                encoder.setVertexBuffer(mtlBuffer?.buffer, offset: Int(args.pointee.offset) + (mtlBuffer?.offset ?? 0), index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                encoder.setFragmentBuffer(mtlBuffer?.buffer, offset: Int(args.pointee.offset) + (mtlBuffer?.offset ?? 0), index: mtlBindingPath.bindIndex)
            }
            
            self.baseBufferOffsets[BufferOffsetKey(stage: stages, index: mtlBindingPath.bindIndex)] = (mtlBuffer?.offset ?? 0)
            
        case .setBufferOffset(let args):
            
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let stages = mtlBindingPath.stages
            
            let baseOffset = self.baseBufferOffsets[BufferOffsetKey(stage: stages, index: mtlBindingPath.bindIndex)] ?? 0
            
            if stages.contains(.vertex) {
                encoder.setVertexBufferOffset(Int(args.pointee.offset) + baseOffset, index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                encoder.setFragmentBufferOffset(Int(args.pointee.offset) + baseOffset, index: mtlBindingPath.bindIndex)
            }
            
        case .setTexture(let args):
            let mtlTexture = resourceRegistry[texture: args.pointee.handle]
            
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let stages = mtlBindingPath.stages
            if stages.contains(.vertex) {
                encoder.setVertexTexture(mtlTexture, index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                encoder.setFragmentTexture(mtlTexture, index: mtlBindingPath.bindIndex)
            }
            
        case .setSamplerState(let args):
            let state = stateCaches[args.pointee.descriptor]
            
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let stages = mtlBindingPath.stages
            if stages.contains(.vertex) {
                encoder.setVertexSamplerState(state, index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                encoder.setFragmentSamplerState(state, index: mtlBindingPath.bindIndex)
            }
            
        case .setRenderPipelineDescriptor(let descriptorPtr):
            let descriptor = descriptorPtr.takeUnretainedValue().value
            self.pipelineDescriptor = descriptor
            encoder.setRenderPipelineState(stateCaches[descriptor, renderTarget: renderTarget])
            
        case .drawPrimitives(let args):
            encoder.drawPrimitives(type: MTLPrimitiveType(args.pointee.primitiveType), vertexStart: Int(args.pointee.vertexStart), vertexCount: Int(args.pointee.vertexCount), instanceCount: Int(args.pointee.instanceCount), baseInstance: Int(args.pointee.baseInstance))
            
        case .drawIndexedPrimitives(let args):
            let indexBuffer = resourceRegistry[buffer: args.pointee.indexBuffer]!
            
            encoder.drawIndexedPrimitives(type: MTLPrimitiveType(args.pointee.primitiveType), indexCount: Int(args.pointee.indexCount), indexType: MTLIndexType(args.pointee.indexType), indexBuffer: indexBuffer.buffer, indexBufferOffset: Int(args.pointee.indexBufferOffset) + indexBuffer.offset, instanceCount: Int(args.pointee.instanceCount), baseVertex: Int(args.pointee.baseVertex), baseInstance: Int(args.pointee.baseInstance))
            
        case .setViewport(let viewportPtr):
            encoder.setViewport(MTLViewport(viewportPtr.pointee))
            
        case .setFrontFacing(let winding):
            encoder.setFrontFacing(MTLWinding(winding))
            
        case .setCullMode(let cullMode):
            encoder.setCullMode(MTLCullMode(cullMode))
            
        case .setTriangleFillMode(let fillMode):
            encoder.setTriangleFillMode(MTLTriangleFillMode(fillMode))
            
        case .setDepthStencilDescriptor(let descriptorPtr):
            let state = stateCaches[descriptorPtr.takeUnretainedValue().value]
            encoder.setDepthStencilState(state)
            
        case .setScissorRect(let scissorPtr):
            encoder.setScissorRect(MTLScissorRect(scissorPtr.pointee))
            
        case .setDepthClipMode(let mode):
            encoder.setDepthClipMode(MTLDepthClipMode(mode))
            
        case .setDepthBias(let args):
            encoder.setDepthBias(args.pointee.depthBias, slopeScale: args.pointee.slopeScale, clamp: args.pointee.clamp)
            
        case .setStencilReferenceValue(let value):
            encoder.setStencilReferenceValue(value)
            
        case .setStencilReferenceValues(let front, let back):
            encoder.setStencilReferenceValues(front: front, back: back)
            
        default:
            fatalError()
        }
    }
    
    func waitForFence(_ fence: MTLFence, beforeStages: MTLRenderStages?, encoder: MTLRenderCommandEncoder) {
        let fenceWaitKey = FGMTLThreadRenderCommandEncoder.FenceWaitKey(fence: fence, stages: beforeStages!)
        if self.waitedOnFences.contains(fenceWaitKey) || self.updatedFences.contains(ObjectIdentifier(fence)) {
            return
        }
        
        encoder.wait(for: fence, before: beforeStages!)
        
        self.waitedOnFences.insert(fenceWaitKey)
    }
    
    func updateFence(_ fence: MTLFence, afterStages: MTLRenderStages?, encoder: MTLRenderCommandEncoder) {
        encoder.update(fence, after: afterStages!)
        
        self.updatedFences.insert(ObjectIdentifier(fence))
    }
    
    func memoryBarrier(resource: MTLResource, afterStages: MTLRenderStages?, beforeStages: MTLRenderStages?, encoder: MTLRenderCommandEncoder) {
        #if os(macOS)
        if #available(OSX 10.14, *) {
            var resource = resource
            encoder.__memoryBarrier(resources: &resource, count: 1, after: afterStages!, before: beforeStages!)
        }
        #endif
    }
}

public final class FGMTLComputeCommandEncoder : FGMTLCommandEncoder {
    let encoder: MTLComputeCommandEncoder
    
    var pipelineDescriptor : ComputePipelineDescriptor? = nil
    var baseBufferOffsets = [Int : Int]()
    
    var updatedFences = Set<ObjectIdentifier>()
    var waitedOnFences = Set<ObjectIdentifier>()
    
    init(encoder: MTLComputeCommandEncoder) {
        self.encoder = encoder
    }
    
    func executePass(commands: ArraySlice<FrameGraphCommand>, resourceCommands: [ResourceCommand], resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        var resourceCommandIndex = resourceCommands.binarySearch { $0.index < commands.startIndex }
        
        for (i, command) in zip(commands.indices, commands) {
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i, resourceRegistry: resourceRegistry, encoder: self.encoder)
            self.executeCommand(command, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i, resourceRegistry: resourceRegistry, encoder: self.encoder)
        }
    }
    
    func executeCommand(_ command: FrameGraphCommand, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        switch command {
        case .insertDebugSignpost(let cString):
            encoder.insertDebugSignpost(String(cString: cString))
            
        case .setLabel(let label):
            encoder.label = String(cString: label)
            
        case .pushDebugGroup(let groupName):
            encoder.pushDebugGroup(String(cString: groupName))
            
        case .popDebugGroup:
            encoder.popDebugGroup()
            
        case .setArgumentBuffer(let args):
            let bindingPath = args.pointee.bindingPath
            let mtlBindingPath = MetalResourceBindingPath(bindingPath)
            
            let argumentBuffer = args.pointee.argumentBuffer
            let mtlArgumentBuffer = resourceRegistry.allocateArgumentBufferIfNeeded(argumentBuffer, bindingPath: bindingPath, encoder: { () -> MTLArgumentEncoder in
                return stateCaches.argumentEncoder(atIndex: mtlBindingPath.bindIndex, functionName: self.pipelineDescriptor!.function, functionConstants: self.pipelineDescriptor!._functionConstants)
            }, stateCaches: stateCaches)
            
            encoder.setBuffer(mtlArgumentBuffer.buffer, offset: mtlArgumentBuffer.offset, index: mtlBindingPath.bindIndex)
            
        case .setArgumentBufferArray(let args):
            let bindingPath = args.pointee.bindingPath
            let mtlBindingPath = MetalResourceBindingPath(bindingPath)
            
            let argumentBuffer = args.pointee.argumentBuffer
            let mtlArgumentBuffer = resourceRegistry.allocateArgumentBufferArrayIfNeeded(argumentBuffer, bindingPath: bindingPath, encoder: { () -> MTLArgumentEncoder in
                return stateCaches.argumentEncoder(atIndex: mtlBindingPath.bindIndex, functionName: self.pipelineDescriptor!.function, functionConstants: self.pipelineDescriptor!._functionConstants)
            }, stateCaches: stateCaches)
            
            encoder.setBuffer(mtlArgumentBuffer.buffer, offset: mtlArgumentBuffer.offset, index: mtlBindingPath.bindIndex)
            
        case .setBytes(let args):
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            encoder.setBytes(args.pointee.bytes, length: Int(args.pointee.length), index: mtlBindingPath.bindIndex)
            
        case .setBuffer(let args):
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let mtlBuffer = resourceRegistry[buffer: args.pointee.handle]
            encoder.setBuffer(mtlBuffer?.buffer, offset: Int(args.pointee.offset) + (mtlBuffer?.offset ?? 0), index: mtlBindingPath.bindIndex)
            
            self.baseBufferOffsets[mtlBindingPath.bindIndex] = mtlBuffer?.offset ?? 0
            
        case .setBufferOffset(let args):
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let baseOffset = self.baseBufferOffsets[mtlBindingPath.bindIndex] ?? 0
            encoder.setBufferOffset(Int(args.pointee.offset) + baseOffset, index: mtlBindingPath.bindIndex)
            
        case .setTexture(let args):
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let mtlTexture = resourceRegistry[texture: args.pointee.handle]
            encoder.setTexture(mtlTexture, index: mtlBindingPath.bindIndex)
            
        case .setSamplerState(let args):
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let state = stateCaches[args.pointee.descriptor]
            encoder.setSamplerState(state, index: mtlBindingPath.bindIndex)
            
        case .dispatchThreads(let args):
            encoder.dispatchThreads(MTLSize(args.pointee.threads), threadsPerThreadgroup: MTLSize(args.pointee.threadsPerThreadgroup))
            
        case .dispatchThreadgroups(let args):
            encoder.dispatchThreadgroups(MTLSize(args.pointee.threadgroupsPerGrid), threadsPerThreadgroup: MTLSize(args.pointee.threadsPerThreadgroup))
            
        case .dispatchThreadgroupsIndirect(let args):
            let indirectBuffer = resourceRegistry[buffer: args.pointee.indirectBuffer]!
            encoder.dispatchThreadgroups(indirectBuffer: indirectBuffer.buffer, indirectBufferOffset: Int(args.pointee.indirectBufferOffset) + indirectBuffer.offset, threadsPerThreadgroup: MTLSize(args.pointee.threadsPerThreadgroup))
            
        case .setComputePipelineDescriptor(let descriptorPtr):
            let descriptor = descriptorPtr.takeUnretainedValue()
            self.pipelineDescriptor = descriptor.pipelineDescriptor
            encoder.setComputePipelineState(stateCaches[descriptor.pipelineDescriptor, descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth])
            
        case .setStageInRegion(let regionPtr):
            encoder.setStageInRegion(MTLRegion(regionPtr.pointee))
            
        case .setThreadgroupMemoryLength(let length, let index):
            encoder.setThreadgroupMemoryLength(Int(length), index: Int(index))
            
        default:
            fatalError()
        }
    }
    
    func waitForFence(_ fence: MTLFence, beforeStages: MTLRenderStages?, encoder: MTLComputeCommandEncoder) {
        if self.waitedOnFences.contains(ObjectIdentifier(fence)) || self.updatedFences.contains(ObjectIdentifier(fence)) {
            return
        }
        encoder.waitForFence(fence)
        
        self.waitedOnFences.insert(ObjectIdentifier(fence))
    }
    
    func updateFence(_ fence: MTLFence, afterStages: MTLRenderStages?, encoder: MTLComputeCommandEncoder) {
        encoder.updateFence(fence)
        self.updatedFences.insert(ObjectIdentifier(fence))
    }
    
    func memoryBarrier(resource: MTLResource, afterStages: MTLRenderStages?, beforeStages: MTLRenderStages?, encoder: MTLComputeCommandEncoder) {
        if #available(OSX 10.14, *) {
            var resource = resource
            encoder.__memoryBarrier(resources: &resource, count: 1)
        }
    }
    
    func endEncoding() {
        self.encoder.endEncoding()
    }
}

public final class FGMTLBlitCommandEncoder : FGMTLCommandEncoder {
    let encoder: MTLBlitCommandEncoder
    
    var updatedFences = Set<ObjectIdentifier>()
    var waitedOnFences = Set<ObjectIdentifier>()
    
    
    init(encoder: MTLBlitCommandEncoder) {
        self.encoder = encoder
    }
    
    func executePass(commands: ArraySlice<FrameGraphCommand>, resourceCommands: [ResourceCommand], resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        var resourceCommandIndex = resourceCommands.binarySearch { $0.index < commands.startIndex }
        
        for (i, command) in zip(commands.indices, commands) {
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i, resourceRegistry: resourceRegistry, encoder: self.encoder)
            self.executeCommand(command, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i, resourceRegistry: resourceRegistry, encoder: self.encoder)
        }
    }
    
    func executeCommand(_ command: FrameGraphCommand, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        switch command {
        case .insertDebugSignpost(let cString):
            encoder.insertDebugSignpost(String(cString: cString))
            
        case .setLabel(let label):
            encoder.label = String(cString: label)
            
        case .pushDebugGroup(let groupName):
            encoder.pushDebugGroup(String(cString: groupName))
            
        case .popDebugGroup:
            encoder.popDebugGroup()
            
        case .copyBufferToTexture(let args):
            let sourceBuffer = resourceRegistry[buffer: args.pointee.sourceBuffer]!
            encoder.copy(from: sourceBuffer.buffer, sourceOffset: Int(args.pointee.sourceOffset) + sourceBuffer.offset, sourceBytesPerRow: Int(args.pointee.sourceBytesPerRow), sourceBytesPerImage: Int(args.pointee.sourceBytesPerImage), sourceSize: MTLSize(args.pointee.sourceSize), to: resourceRegistry[texture: args.pointee.destinationTexture]!, destinationSlice: Int(args.pointee.destinationSlice), destinationLevel: Int(args.pointee.destinationLevel), destinationOrigin: MTLOrigin(args.pointee.destinationOrigin), options: MTLBlitOption(args.pointee.options))
            
        case .copyBufferToBuffer(let args):
            let sourceBuffer = resourceRegistry[buffer: args.pointee.sourceBuffer]!
            let destinationBuffer = resourceRegistry[buffer: args.pointee.destinationBuffer]!
            encoder.copy(from: sourceBuffer.buffer, sourceOffset: Int(args.pointee.sourceOffset) + sourceBuffer.offset, to: destinationBuffer.buffer, destinationOffset: Int(args.pointee.destinationOffset) + destinationBuffer.offset, size: Int(args.pointee.size))
            
        case .copyTextureToBuffer(let args):
            let destinationBuffer = resourceRegistry[buffer: args.pointee.destinationBuffer]!
            encoder.copy(from: resourceRegistry[texture: args.pointee.sourceTexture]!, sourceSlice: Int(args.pointee.sourceSlice), sourceLevel: Int(args.pointee.sourceLevel), sourceOrigin: MTLOrigin(args.pointee.sourceOrigin), sourceSize: MTLSize(args.pointee.sourceSize), to: destinationBuffer.buffer, destinationOffset: Int(args.pointee.destinationOffset) + destinationBuffer.offset, destinationBytesPerRow: Int(args.pointee.destinationBytesPerRow), destinationBytesPerImage: Int(args.pointee.destinationBytesPerImage), options: MTLBlitOption(args.pointee.options))
            
        case .copyTextureToTexture(let args):
            encoder.copy(from: resourceRegistry[texture: args.pointee.sourceTexture]!, sourceSlice: Int(args.pointee.sourceSlice), sourceLevel: Int(args.pointee.sourceLevel), sourceOrigin: MTLOrigin(args.pointee.sourceOrigin), sourceSize: MTLSize(args.pointee.sourceSize), to: resourceRegistry[texture: args.pointee.destinationTexture]!, destinationSlice: Int(args.pointee.destinationSlice), destinationLevel: Int(args.pointee.destinationLevel), destinationOrigin: MTLOrigin(args.pointee.destinationOrigin))
            
        case .fillBuffer(let args):
            let buffer = resourceRegistry[buffer: args.pointee.buffer]!
            let range = (args.pointee.range.lowerBound + buffer.offset)..<(args.pointee.range.upperBound + buffer.offset)
            encoder.fill(buffer: buffer.buffer, range: range, value: args.pointee.value)
            
        case .generateMipmaps(let texture):
            encoder.generateMipmaps(for: resourceRegistry[texture: texture]!)
            
        case .synchroniseTexture(let textureHandle):
            #if os(macOS)
            encoder.synchronize(resource: resourceRegistry[texture: textureHandle]!)
            #else
            break
            #endif
            
        case .synchroniseTextureSlice(let args):
            #if os(macOS)
            encoder.synchronize(texture: resourceRegistry[texture: args.pointee.texture]!, slice: Int(args.pointee.slice), level: Int(args.pointee.level))
            #else
            break
            #endif
            
        case .synchroniseBuffer(let buffer):
            #if os(macOS)
            let buffer = resourceRegistry[buffer: buffer]!
            encoder.synchronize(resource: buffer.buffer)
            #else
            break
            #endif
            
        default:
            fatalError()
        }
    }
    
    func waitForFence(_ fence: MTLFence, beforeStages: MTLRenderStages?, encoder: MTLBlitCommandEncoder) {
        if self.waitedOnFences.contains(ObjectIdentifier(fence)) || self.updatedFences.contains(ObjectIdentifier(fence)) {
            return
        }
        encoder.waitForFence(fence)
        
        self.waitedOnFences.insert(ObjectIdentifier(fence))
    }
    
    func updateFence(_ fence: MTLFence, afterStages: MTLRenderStages?, encoder: MTLBlitCommandEncoder) {
        encoder.updateFence(fence)
        self.updatedFences.insert(ObjectIdentifier(fence))
    }
    
    func memoryBarrier(resource: MTLResource, afterStages: MTLRenderStages?, beforeStages: MTLRenderStages?, encoder: MTLBlitCommandEncoder) {
    }
    
    func endEncoding() {
        self.encoder.endEncoding()
    }
}

final class FGMTLExternalCommandEncoder : FGMTLCommandEncoder {
    typealias Encoder = Void
    
    let commandBuffer: MTLCommandBuffer
    
    init(commandBuffer: MTLCommandBuffer) {
        self.commandBuffer = commandBuffer
    }
    
    func executePass(commands: ArraySlice<FrameGraphCommand>, resourceCommands: [ResourceCommand], resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        var resourceCommandIndex = resourceCommands.binarySearch { $0.index < commands.startIndex }
        
        for (i, command) in zip(commands.indices, commands) {
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i, resourceRegistry: resourceRegistry, encoder: ())
            self.executeCommand(command, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i, resourceRegistry: resourceRegistry, encoder: ())
        }
    }
    
    func executeCommand(_ command: FrameGraphCommand, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        switch command {
        case .encodeRayIntersection(let args):
            let intersector = args.pointee.intersector.takeUnretainedValue()
            
            let rayBuffer = resourceRegistry[buffer: args.pointee.rayBuffer]!
            let intersectionBuffer = resourceRegistry[buffer: args.pointee.intersectionBuffer]!
            
            intersector.encodeIntersection(commandBuffer: self.commandBuffer, intersectionType: args.pointee.intersectionType, rayBuffer: rayBuffer.buffer, rayBufferOffset: rayBuffer.offset + args.pointee.rayBufferOffset, intersectionBuffer: intersectionBuffer.buffer, intersectionBufferOffset: intersectionBuffer.offset + args.pointee.intersectionBufferOffset, rayCount: args.pointee.rayCount, accelerationStructure: args.pointee.accelerationStructure.takeUnretainedValue())
            
        case .encodeRayIntersectionRayCountBuffer(let args):
            
            let intersector = args.pointee.intersector.takeUnretainedValue()
            
            let rayBuffer = resourceRegistry[buffer: args.pointee.rayBuffer]!
            let intersectionBuffer = resourceRegistry[buffer: args.pointee.intersectionBuffer]!
            let rayCountBuffer = resourceRegistry[buffer: args.pointee.rayCountBuffer]!
            
            intersector.encodeIntersection(commandBuffer: self.commandBuffer, intersectionType: args.pointee.intersectionType, rayBuffer: rayBuffer.buffer, rayBufferOffset: rayBuffer.offset + args.pointee.rayBufferOffset, intersectionBuffer: intersectionBuffer.buffer, intersectionBufferOffset: intersectionBuffer.offset + args.pointee.intersectionBufferOffset, rayCountBuffer: rayCountBuffer.buffer, rayCountBufferOffset: rayCountBuffer.offset + args.pointee.rayCountBufferOffset, accelerationStructure: args.pointee.accelerationStructure.takeUnretainedValue())
            
        default:
            break
        }
    }
    
    func waitForFence(_ fence: MTLFence, beforeStages: MTLRenderStages?, encoder: FGMTLExternalCommandEncoder.Encoder) {
        
    }
    
    func updateFence(_ fence: MTLFence, afterStages: MTLRenderStages?, encoder: FGMTLExternalCommandEncoder.Encoder) {
        
    }
    
    func memoryBarrier(resource: MTLResource, afterStages: MTLRenderStages?, beforeStages: MTLRenderStages?, encoder: FGMTLExternalCommandEncoder.Encoder) {
        
    }
    
    func endEncoding() {
        
    }
    
}
