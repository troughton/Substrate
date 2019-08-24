//
//  CommandEncoders.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 25/12/17.
//

#if canImport(Metal)

import Metal
import FrameGraphUtilities

final class MetalEncoderManager {
    
    static let useParallelEncoding = false
    
    private let commandBuffer : MTLCommandBuffer
    private let resourceRegistry : MetalResourceRegistry
    private var previousRenderTarget : MetalRenderTargetDescriptor? = nil
    
    private var renderEncoder : FGMTLRenderCommandEncoder? = nil
    private var computeEncoder : FGMTLComputeCommandEncoder? = nil
    private var blitEncoder : FGMTLBlitCommandEncoder? = nil
    
    init(commandBuffer: MTLCommandBuffer, resourceRegistry: MetalResourceRegistry) {
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
    
    func renderCommandEncoder(descriptor: MetalRenderTargetDescriptor, textureUsages: [Texture : MetalTextureUsageProperties], resourceCommands: [MetalFrameResourceCommand], resourceRegistry: MetalResourceRegistry, stateCaches: MetalStateCaches) -> FGMTLRenderCommandEncoder? {
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
                print("Error creating pass descriptor: \(error)")
                return nil
            }
            
            let renderEncoder : FGMTLRenderCommandEncoder = /* MetalEncoderManager.useParallelEncoding ? FGMTLParallelRenderCommandEncoder(encoder: commandBuffer.makeParallelRenderCommandEncoder(descriptor: mtlDescriptor)!, renderPassDescriptor: mtlDescriptor) : */ FGMTLThreadRenderCommandEncoder(encoder: commandBuffer.makeRenderCommandEncoder(descriptor: mtlDescriptor)!, renderPassDescriptor: mtlDescriptor)
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
            mtlComputeEncoder = commandBuffer.makeComputeCommandEncoder(dispatchType: .concurrent)!
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

typealias FGMTLRenderCommandEncoder = FGMTLThreadRenderCommandEncoder

public final class FGMTLParallelRenderCommandEncoder {
    static let commandCountThreshold = Int.max // 512
    
    let parallelEncoder: MTLParallelRenderCommandEncoder
    let renderPassDescriptor : MTLRenderPassDescriptor
    
    let dispatchGroup = DispatchGroup()
    var currentEncoder : FGMTLThreadRenderCommandEncoder? = nil
    
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
    
    func executePass(_ pass: RenderPassRecord, resourceCommands: [MetalFrameResourceCommand], renderTarget: RenderTargetDescriptor, passRenderTarget: RenderTargetDescriptor, resourceRegistry: MetalResourceRegistry, stateCaches: MetalStateCaches) {
        if pass.commandRange!.count < FGMTLParallelRenderCommandEncoder.commandCountThreshold {
            if let currentEncoder = currentEncoder {
                currentEncoder.executePass(pass, resourceCommands: resourceCommands, renderTarget: renderTarget, passRenderTarget: passRenderTarget, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
            } else {
                let encoder = self.parallelEncoder.makeRenderCommandEncoder()!
                let fgEncoder = FGMTLThreadRenderCommandEncoder(encoder: encoder, renderPassDescriptor: renderPassDescriptor)
                
                fgEncoder.executePass(pass, resourceCommands: resourceCommands, renderTarget: renderTarget, passRenderTarget: passRenderTarget, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
                
                self.currentEncoder = fgEncoder
            }
        } else {
            // Execute in parallel if the workload is large enough.
            
            self.currentEncoder?.endEncoding()
            self.currentEncoder = nil
            
            let encoder = self.parallelEncoder.makeRenderCommandEncoder()!
            let fgEncoder = FGMTLThreadRenderCommandEncoder(encoder: encoder, renderPassDescriptor: renderPassDescriptor)
            
            DispatchQueue.global().async(group: self.dispatchGroup) {
                fgEncoder.executePass(pass, resourceCommands: resourceCommands, renderTarget: renderTarget, passRenderTarget: passRenderTarget, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
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

public final class FGMTLThreadRenderCommandEncoder {
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
    var pipelineDescriptor : RenderPipelineDescriptor? = nil
    private let baseBufferOffsets : UnsafeMutablePointer<Int> // 31 vertex, 31 fragment, since that's the maximum number of entries in a buffer argument table (https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
    
    var updatedFences = Set<ObjectIdentifier>()
    var waitedOnFences = Set<FenceWaitKey>()
    
    init(encoder: MTLRenderCommandEncoder, renderPassDescriptor: MTLRenderPassDescriptor) {
        self.encoder = encoder
        self.renderPassDescriptor = renderPassDescriptor
        
        self.baseBufferOffsets = .allocate(capacity: 62)
        self.baseBufferOffsets.initialize(repeating: 0, count: 62)
    }
    
    deinit {
        self.baseBufferOffsets.deallocate()
    }
    
    var label: String? {
        get {
            return self.encoder.label
        }
        set {
            self.encoder.label = newValue
        }
    }
    
    func executePass(_ pass: RenderPassRecord, resourceCommands: [MetalFrameResourceCommand], renderTarget: RenderTargetDescriptor, passRenderTarget: RenderTargetDescriptor, resourceRegistry: MetalResourceRegistry, stateCaches: MetalStateCaches) {
        var resourceCommandIndex = resourceCommands.binarySearch { $0.index < pass.commandRange!.lowerBound }
        
        if passRenderTarget.depthAttachment == nil && passRenderTarget.stencilAttachment == nil, (self.renderPassDescriptor.depthAttachment.texture != nil || self.renderPassDescriptor.stencilAttachment.texture != nil) {
            encoder.setDepthStencilState(stateCaches.defaultDepthState) // The render pass unexpectedly has a depth/stencil attachment, so make sure the depth stencil state is set to the default.
        }
        
        for (i, command) in zip(pass.commandRange!, pass.commands) {
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i, resourceRegistry: resourceRegistry)
            self.executeCommand(command, encoder: encoder, renderTarget: renderTarget, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i, resourceRegistry: resourceRegistry)
        }
    }
    
    func endEncoding() {
        self.encoder.endEncoding()
    }
    
    func executeCommand(_ command: FrameGraphCommand, encoder: MTLRenderCommandEncoder, renderTarget: RenderTargetDescriptor, resourceRegistry: MetalResourceRegistry, stateCaches: MetalStateCaches) {
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
            let mtlBindingPath = args.pointee.bindingPath
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
            assert(index < 31, "The maximum number of buffers allowed in the buffer argument table for a single function is 31.")
            // For vertex buffers, index the bindings backwards from the maximum (30) to allow argument buffers and push constants to go first.
            
            self.baseBufferOffsets[index] = mtlBuffer?.offset ?? 0
            encoder.setVertexBuffer(mtlBuffer?.buffer, offset: Int(args.pointee.offset) + self.baseBufferOffsets[index], index: 30 - index)
            
        case .setVertexBufferOffset(let offset, let index):
            let baseOffset = self.baseBufferOffsets[Int(index)]
            encoder.setVertexBufferOffset(Int(offset) + baseOffset, index: 30 - Int(index))
            
        case .setArgumentBuffer(let args):
            let bindingPath = args.pointee.bindingPath
            let mtlBindingPath = bindingPath
            let stages = mtlBindingPath.stages
            
            let argumentBuffer = args.pointee.argumentBuffer
            let mtlArgumentBuffer = resourceRegistry[argumentBuffer]!
            
            if stages.contains(.vertex) {
                encoder.setVertexBuffer(mtlArgumentBuffer.buffer, offset: mtlArgumentBuffer.offset, index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                encoder.setFragmentBuffer(mtlArgumentBuffer.buffer, offset: mtlArgumentBuffer.offset, index: mtlBindingPath.bindIndex)
            }
            
        case .setArgumentBufferArray(let args):
            let bindingPath = args.pointee.bindingPath
            let mtlBindingPath = bindingPath
            let stages = mtlBindingPath.stages
            
            let argumentBuffer = args.pointee.argumentBuffer
            let mtlArgumentBuffer = resourceRegistry[argumentBuffer]!
            
            if stages.contains(.vertex) {
                encoder.setVertexBuffer(mtlArgumentBuffer.buffer, offset: mtlArgumentBuffer.offset, index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                encoder.setFragmentBuffer(mtlArgumentBuffer.buffer, offset: mtlArgumentBuffer.offset, index: mtlBindingPath.bindIndex)
            }
            
        case .setBuffer(let args):
            let mtlBuffer = resourceRegistry[buffer: args.pointee.handle]
            
            let mtlBindingPath = args.pointee.bindingPath
            assert(mtlBindingPath.bindIndex < 31, "The maximum number of buffers allowed in the buffer argument table for a single function is 31.")
            
            let stages = mtlBindingPath.stages
            if stages.contains(.vertex) {
                self.baseBufferOffsets[mtlBindingPath.bindIndex] = (mtlBuffer?.offset ?? 0)
                encoder.setVertexBuffer(mtlBuffer?.buffer, offset: Int(args.pointee.offset) + (mtlBuffer?.offset ?? 0), index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                self.baseBufferOffsets[mtlBindingPath.bindIndex + 31] = (mtlBuffer?.offset ?? 0)
                encoder.setFragmentBuffer(mtlBuffer?.buffer, offset: Int(args.pointee.offset) + (mtlBuffer?.offset ?? 0), index: mtlBindingPath.bindIndex)
            }
            
        case .setBufferOffset(let args):
            
            let mtlBindingPath = args.pointee.bindingPath
            let stages = mtlBindingPath.stages
            
            assert(mtlBindingPath.bindIndex < 31, "The maximum number of buffers allowed in the buffer argument table for a single function is 31.")
            
            if stages.contains(.vertex) {
                let baseOffset = self.baseBufferOffsets[mtlBindingPath.bindIndex]
                encoder.setVertexBufferOffset(Int(args.pointee.offset) + baseOffset, index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                let baseOffset = self.baseBufferOffsets[mtlBindingPath.bindIndex + 31]
                encoder.setFragmentBufferOffset(Int(args.pointee.offset) + baseOffset, index: mtlBindingPath.bindIndex)
            }
            
        case .setTexture(let args):
            let mtlTexture = resourceRegistry[texture: args.pointee.handle]
            
            let mtlBindingPath = args.pointee.bindingPath
            let stages = mtlBindingPath.stages
            if stages.contains(.vertex) {
                encoder.setVertexTexture(mtlTexture, index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                encoder.setFragmentTexture(mtlTexture, index: mtlBindingPath.bindIndex)
            }
            
        case .setSamplerState(let args):
            let state = stateCaches[args.pointee.descriptor]
            
            let mtlBindingPath = args.pointee.bindingPath
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
            encoder.setRenderPipelineState(stateCaches[descriptor, renderTarget: renderTarget]!)
            
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
    
    func checkResourceCommands(_ resourceCommands: [MetalFrameResourceCommand], resourceCommandIndex: inout Int, phase: PerformOrder, commandIndex: Int, resourceRegistry: MetalResourceRegistry) {
        var hasPerformedTextureBarrier = false
        while resourceCommandIndex < resourceCommands.count, commandIndex == resourceCommands[resourceCommandIndex].index, phase == resourceCommands[resourceCommandIndex].order {
            defer { resourceCommandIndex += 1 }
            
            switch resourceCommands[resourceCommandIndex].command {
                
            case .memoryBarrier(let resource, let afterStages, let beforeStages):
                if let texture = resource.texture {
                    self.memoryBarrier(resource: resourceRegistry[texture]!, afterStages: afterStages, beforeStages: beforeStages)
                } else if let buffer = resource.buffer {
                    self.memoryBarrier(resource: resourceRegistry[buffer]!.buffer, afterStages: afterStages, beforeStages: beforeStages)
                }
                
            case .textureBarrier:
                #if os(macOS)
                if !hasPerformedTextureBarrier {
                    encoder.textureBarrier()
                    hasPerformedTextureBarrier = true
                }
                #else
                break
                #endif
                
            case .updateFence(let fence, let afterStages):
                // TODO: We can combine together multiple fences that update at the same time.
                self.updateFence(fence.fence, afterStages: afterStages)
                
            case .waitForFence(let fence, let beforeStages):
                self.waitForFence(fence.fence, beforeStages: beforeStages)
                
            case .waitForMultiframeFence(let resource, _, let waitFence, let beforeStages):
                resourceRegistry.withResourceUsageFencesIfPresent(for: resource, perform: { fenceStates in
                    if case .write = waitFence {
                        for fence in fenceStates.writeWaitFences where fence.isValid {
                            self.waitForFence(fence.fence, beforeStages: beforeStages)
                        }
                    } else {
                        if fenceStates.readWaitFence.isValid {
                            self.waitForFence(fenceStates.readWaitFence.fence, beforeStages: beforeStages)
                        }
                    }
                })
                
            case .useResource(let resource, let usage, let stages):
                var mtlResource : MTLResource
                
                if let texture = resource.texture {
                    mtlResource = resourceRegistry[texture]!
                } else if let buffer = resource.buffer {
                    mtlResource = resourceRegistry[buffer]!.buffer
                } else if let argumentBuffer = resource.argumentBuffer {
                    mtlResource = resourceRegistry[argumentBuffer]!.buffer
                } else {
                    preconditionFailure()
                }
                
                if #available(iOS 13.0, macOS 10.15, *) {
                    encoder.use(mtlResource, usage: usage, stages: stages)
                } else {
                    encoder.useResource(mtlResource, usage: usage)
                }
            }
        }
    }
    
    func waitForFence(_ fence: MTLFence, beforeStages: MTLRenderStages?) {
        let fenceWaitKey = FGMTLThreadRenderCommandEncoder.FenceWaitKey(fence: fence, stages: beforeStages!)
        if self.waitedOnFences.contains(fenceWaitKey) || self.updatedFences.contains(ObjectIdentifier(fence)) {
            return
        }
        
        #if os(macOS)
        encoder.waitForFence(fence, before: beforeStages!)
        #else
        encoder.wait(for: fence, before: beforeStages!)
        #endif
        
        self.waitedOnFences.insert(fenceWaitKey)
    }
    
    func updateFence(_ fence: MTLFence, afterStages: MTLRenderStages?) {
        #if os(macOS)
        encoder.updateFence(fence, after: afterStages!)
        #else
        encoder.update(fence, after: afterStages!)
        #endif
        
        self.updatedFences.insert(ObjectIdentifier(fence))
    }
    
    func memoryBarrier(resource: MTLResource, afterStages: MTLRenderStages?, beforeStages: MTLRenderStages?) {
        #if os(macOS)
        if #available(OSX 10.14, *) {
            var resource = resource
            encoder.__memoryBarrier(resources: &resource, count: 1, after: afterStages!, before: beforeStages!)
        }
        #endif
    }
}

public final class FGMTLComputeCommandEncoder {
    let encoder: MTLComputeCommandEncoder
    
    var pipelineDescriptor : ComputePipelineDescriptor? = nil
    private let baseBufferOffsets : UnsafeMutablePointer<Int> // 31, since that's the maximum number of entries in a buffer argument table (https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
    
    var updatedFences = Set<ObjectIdentifier>()
    var waitedOnFences = Set<ObjectIdentifier>()
    
    init(encoder: MTLComputeCommandEncoder) {
        self.encoder = encoder
        
        self.baseBufferOffsets = .allocate(capacity: 31)
        self.baseBufferOffsets.initialize(repeating: 0, count: 31)
    }
    
    deinit {
        self.baseBufferOffsets.deallocate()
    }
    
    func executePass(_ pass: RenderPassRecord, resourceCommands: [MetalFrameResourceCommand], resourceRegistry: MetalResourceRegistry, stateCaches: MetalStateCaches) {
        var resourceCommandIndex = resourceCommands.binarySearch { $0.index < pass.commandRange!.lowerBound }
        
        for (i, command) in zip(pass.commandRange!, pass.commands) {
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i, resourceRegistry: resourceRegistry)
            self.executeCommand(command, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i, resourceRegistry: resourceRegistry)
        }
    }
    
    func executeCommand(_ command: FrameGraphCommand, resourceRegistry: MetalResourceRegistry, stateCaches: MetalStateCaches) {
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
            let mtlBindingPath = bindingPath
            
            let argumentBuffer = args.pointee.argumentBuffer
            let mtlArgumentBuffer = resourceRegistry[argumentBuffer]!
            
            encoder.setBuffer(mtlArgumentBuffer.buffer, offset: mtlArgumentBuffer.offset, index: mtlBindingPath.bindIndex)
            
        case .setArgumentBufferArray(let args):
            let bindingPath = args.pointee.bindingPath
            let mtlBindingPath = bindingPath
            
            let argumentBuffer = args.pointee.argumentBuffer
            let mtlArgumentBuffer = resourceRegistry[argumentBuffer]!
            
            encoder.setBuffer(mtlArgumentBuffer.buffer, offset: mtlArgumentBuffer.offset, index: mtlBindingPath.bindIndex)
            
        case .setBytes(let args):
            let mtlBindingPath = args.pointee.bindingPath
            encoder.setBytes(args.pointee.bytes, length: Int(args.pointee.length), index: mtlBindingPath.bindIndex)
            
        case .setBuffer(let args):
            let mtlBindingPath = args.pointee.bindingPath
            let mtlBuffer = resourceRegistry[buffer: args.pointee.handle]
            encoder.setBuffer(mtlBuffer?.buffer, offset: Int(args.pointee.offset) + (mtlBuffer?.offset ?? 0), index: mtlBindingPath.bindIndex)
            
            self.baseBufferOffsets[mtlBindingPath.bindIndex] = mtlBuffer?.offset ?? 0
            
        case .setBufferOffset(let args):
            let mtlBindingPath = args.pointee.bindingPath
            let baseOffset = self.baseBufferOffsets[mtlBindingPath.bindIndex]
            encoder.setBufferOffset(Int(args.pointee.offset) + baseOffset, index: mtlBindingPath.bindIndex)
            
        case .setTexture(let args):
            let mtlBindingPath = args.pointee.bindingPath
            let mtlTexture = resourceRegistry[texture: args.pointee.handle]
            encoder.setTexture(mtlTexture, index: mtlBindingPath.bindIndex)
            
        case .setSamplerState(let args):
            let mtlBindingPath = args.pointee.bindingPath
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
            encoder.setComputePipelineState(stateCaches[descriptor.pipelineDescriptor, descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth]!)
            
        case .setStageInRegion(let regionPtr):
            encoder.setStageInRegion(MTLRegion(regionPtr.pointee))
            
        case .setThreadgroupMemoryLength(let length, let index):
            encoder.setThreadgroupMemoryLength(Int(length), index: Int(index))
            
        default:
            fatalError()
        }
    }
    
    func checkResourceCommands(_ resourceCommands: [MetalFrameResourceCommand], resourceCommandIndex: inout Int, phase: PerformOrder, commandIndex: Int, resourceRegistry: MetalResourceRegistry) {
        var hasPerformedTextureBarrier = false
        while resourceCommandIndex < resourceCommands.count, commandIndex == resourceCommands[resourceCommandIndex].index, phase == resourceCommands[resourceCommandIndex].order {
            defer { resourceCommandIndex += 1 }
            
            switch resourceCommands[resourceCommandIndex].command {
                
            case .memoryBarrier(let resource, _, _):
                if let texture = resource.texture {
                    self.memoryBarrier(resource: resourceRegistry[texture]!)
                } else if let buffer = resource.buffer {
                    self.memoryBarrier(resource: resourceRegistry[buffer]!.buffer)
                }
                
            case .textureBarrier:
                assertionFailure()
                
            case .updateFence(let fence, _):
                // TODO: We can combine together multiple fences that update at the same time.
                self.updateFence(fence.fence)
                
            case .waitForFence(let fence, _):
                self.waitForFence(fence.fence)
                
            case .waitForMultiframeFence(let resource, _, let waitFence, _):
                resourceRegistry.withResourceUsageFencesIfPresent(for: resource, perform: { fenceStates in
                    if case .write = waitFence {
                        for fence in fenceStates.writeWaitFences where fence.isValid {
                            self.waitForFence(fence.fence)
                        }
                    } else {
                        if fenceStates.readWaitFence.isValid {
                            self.waitForFence(fenceStates.readWaitFence.fence)
                        }
                    }
                })
                
            case .useResource(let resource, let usage, _):
                var mtlResource : MTLResource
                
                if let texture = resource.texture {
                    mtlResource = resourceRegistry[texture]!
                } else if let buffer = resource.buffer {
                    mtlResource = resourceRegistry[buffer]!.buffer
                } else if let argumentBuffer = resource.argumentBuffer {
                    mtlResource = resourceRegistry[argumentBuffer]!.buffer
                } else {
                    preconditionFailure()
                }
                
                encoder.useResource(mtlResource, usage: usage)
            }
            
        }
    }
    
    func waitForFence(_ fence: MTLFence) {
        if self.waitedOnFences.contains(ObjectIdentifier(fence)) || self.updatedFences.contains(ObjectIdentifier(fence)) {
            return
        }
        encoder.waitForFence(fence)
        
        self.waitedOnFences.insert(ObjectIdentifier(fence))
    }
    
    func updateFence(_ fence: MTLFence) {
        encoder.updateFence(fence)
        self.updatedFences.insert(ObjectIdentifier(fence))
    }
    
    func memoryBarrier(resource: MTLResource) {
        if #available(OSX 10.15, iOS 12.0, tvOS 12.0, *) {
            print("This is untested; is the texture barrier still needed on Catalina?")
            var resource = resource
            encoder.__memoryBarrier(resources: &resource, count: 1)
        } else if #available(OSX 10.14, *) {
            encoder.memoryBarrier(scope: .textures) // There appears to be a bug in Metal where a texture barrier must be inserted even if no textures are modified or even used.
            var resource = resource
            encoder.__memoryBarrier(resources: &resource, count: 1)
        }
    }
    
    func endEncoding() {
        self.encoder.endEncoding()
    }
}

public final class FGMTLBlitCommandEncoder {
    let encoder: MTLBlitCommandEncoder
    
    var updatedFences = Set<ObjectIdentifier>()
    var waitedOnFences = Set<ObjectIdentifier>()
    
    
    init(encoder: MTLBlitCommandEncoder) {
        self.encoder = encoder
    }
    
    func executePass(_ pass: RenderPassRecord, resourceCommands: [MetalFrameResourceCommand], resourceRegistry: MetalResourceRegistry, stateCaches: MetalStateCaches) {
        var resourceCommandIndex = resourceCommands.binarySearch { $0.index < pass.commandRange!.lowerBound }
        
        for (i, command) in zip(pass.commandRange!, pass.commands) {
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i, resourceRegistry: resourceRegistry)
            self.executeCommand(command, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i, resourceRegistry: resourceRegistry)
        }
    }
    
    func executeCommand(_ command: FrameGraphCommand, resourceRegistry: MetalResourceRegistry, stateCaches: MetalStateCaches) {
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
    
    func checkResourceCommands(_ resourceCommands: [MetalFrameResourceCommand], resourceCommandIndex: inout Int, phase: PerformOrder, commandIndex: Int, resourceRegistry: MetalResourceRegistry) {
        var hasPerformedTextureBarrier = false
        while resourceCommandIndex < resourceCommands.count, commandIndex == resourceCommands[resourceCommandIndex].index, phase == resourceCommands[resourceCommandIndex].order {
            defer { resourceCommandIndex += 1 }
            
            switch resourceCommands[resourceCommandIndex].command {
                
            case .memoryBarrier(let resource, _, _):
                if let texture = resource.texture {
                    self.memoryBarrier(resource: resourceRegistry[texture]!)
                } else if let buffer = resource.buffer {
                    self.memoryBarrier(resource: resourceRegistry[buffer]!.buffer)
                }
                
            case .textureBarrier:
                assertionFailure()
                
            case .updateFence(let fence, _):
                // TODO: We can combine together multiple fences that update at the same time.
                self.updateFence(fence.fence)
                
            case .waitForFence(let fence, _):
                self.waitForFence(fence.fence)
                
            case .waitForMultiframeFence(let resource, _, let waitFence, _):
                resourceRegistry.withResourceUsageFencesIfPresent(for: resource, perform: { fenceStates in
                    if case .write = waitFence {
                        for fence in fenceStates.writeWaitFences where fence.isValid {
                            self.waitForFence(fence.fence)
                        }
                    } else {
                        if fenceStates.readWaitFence.isValid {
                            self.waitForFence(fenceStates.readWaitFence.fence)
                        }
                    }
                })
                
            case .useResource:
                break
            }
            
        }
    }
    
    func waitForFence(_ fence: MTLFence) {
        if self.waitedOnFences.contains(ObjectIdentifier(fence)) || self.updatedFences.contains(ObjectIdentifier(fence)) {
            return
        }
        encoder.waitForFence(fence)
        
        self.waitedOnFences.insert(ObjectIdentifier(fence))
    }
    
    func updateFence(_ fence: MTLFence) {
        encoder.updateFence(fence)
        self.updatedFences.insert(ObjectIdentifier(fence))
    }
    
    func memoryBarrier(resource: MTLResource) {
        
    }
    
    func endEncoding() {
        self.encoder.endEncoding()
    }
}

final class FGMTLExternalCommandEncoder {
    typealias Encoder = Void
    
    let commandBuffer: MTLCommandBuffer
    
    init(commandBuffer: MTLCommandBuffer) {
        self.commandBuffer = commandBuffer
    }
    
    func executePass(_ pass: RenderPassRecord, resourceCommands: [MetalFrameResourceCommand], resourceRegistry: MetalResourceRegistry, stateCaches: MetalStateCaches) {
        if _isDebugAssertConfiguration() {
            let resourceCommandIndex = resourceCommands.binarySearch { $0.index < pass.commandRange!.lowerBound }
            assert(resourceCommands[resourceCommandIndex].index >= pass.commandRange!.upperBound) // External encoders shouldn't have any resource commands.
        }
        
        for (_, command) in zip(pass.commandRange!, pass.commands) {
//            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i, resourceRegistry: resourceRegistry, encoder: ())
            self.executeCommand(command, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
//            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i, resourceRegistry: resourceRegistry, encoder: ())
        }
    }
    
    func executeCommand(_ command: FrameGraphCommand, resourceRegistry: MetalResourceRegistry, stateCaches: MetalStateCaches) {
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

#endif // canImport(Metal)
