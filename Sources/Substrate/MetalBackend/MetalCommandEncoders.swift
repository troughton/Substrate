//
//  CommandEncoders.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 25/12/17.
//

#if canImport(Metal)

@preconcurrency import Metal
import SubstrateUtilities

typealias FGMTLRenderCommandEncoder = FGMTLThreadRenderCommandEncoder

final class FGMTLParallelRenderCommandEncoder {
    static let commandCountThreshold = Int.max // 512
    
    let parallelEncoder: MTLParallelRenderCommandEncoder
    let renderPassDescriptor : MTLRenderPassDescriptor
    let isAppleSiliconGPU: Bool
    var pendingTasks = [Task<Void, Never>]()
    
    var currentEncoder : FGMTLThreadRenderCommandEncoder? = nil
    
    init(encoder: MTLParallelRenderCommandEncoder, renderPassDescriptor: MTLRenderPassDescriptor, isAppleSiliconGPU: Bool) {
        self.parallelEncoder = encoder
        self.renderPassDescriptor = renderPassDescriptor
        self.isAppleSiliconGPU = isAppleSiliconGPU
    }
    
    var label: String? {
        get {
            return self.parallelEncoder.label
        }
        set {
            self.parallelEncoder.label = newValue
        }
    }
    
    func executePass(_ pass: RenderPassRecord, resourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>], renderTarget: RenderTargetDescriptor, passRenderTarget: RenderTargetDescriptor, resourceMap: FrameResourceMap<MetalBackend>, stateCaches: MetalStateCaches) async {
        if pass.commandRange!.count < FGMTLParallelRenderCommandEncoder.commandCountThreshold {
            if let currentEncoder = currentEncoder {
                await currentEncoder.executePass(pass, resourceCommands: resourceCommands, renderTarget: renderTarget, passRenderTarget: passRenderTarget, resourceMap: resourceMap, stateCaches: stateCaches)
            } else {
                let encoder = self.parallelEncoder.makeRenderCommandEncoder()!
                let fgEncoder = FGMTLThreadRenderCommandEncoder(encoder: encoder, renderPassDescriptor: renderPassDescriptor, isAppleSiliconGPU: self.isAppleSiliconGPU)
                
                await fgEncoder.executePass(pass, resourceCommands: resourceCommands, renderTarget: renderTarget, passRenderTarget: passRenderTarget, resourceMap: resourceMap, stateCaches: stateCaches)
                
                self.currentEncoder = fgEncoder
            }
        } else {
            // Execute in parallel if the workload is large enough.
            
            self.currentEncoder?.endEncoding()
            self.currentEncoder = nil
            
            let encoder = self.parallelEncoder.makeRenderCommandEncoder()!
            let fgEncoder = FGMTLThreadRenderCommandEncoder(encoder: encoder, renderPassDescriptor: renderPassDescriptor, isAppleSiliconGPU: self.isAppleSiliconGPU)
            
            let task = Task.detached {
                await fgEncoder.executePass(pass, resourceCommands: resourceCommands, renderTarget: renderTarget, passRenderTarget: passRenderTarget, resourceMap: resourceMap, stateCaches: stateCaches)
                fgEncoder.endEncoding()
            }
            self.pendingTasks.append(task)
        }
        
    }
    
    func endEncoding() async {
        self.currentEncoder?.endEncoding()
        
        for task in self.pendingTasks {
            _ = await task.value
        }
        self.parallelEncoder.endEncoding()
    }
}

final class FGMTLThreadRenderCommandEncoder {
    let encoder: MTLRenderCommandEncoder
    let isAppleSiliconGPU: Bool
    
    let renderPassDescriptor : MTLRenderPassDescriptor
    var hasFragmentFunction: Bool = false
    private let boundBuffers: UnsafeMutablePointer<UnsafeMutableRawPointer?>
    private let baseBufferOffsets : UnsafeMutablePointer<Int> // 31 vertex, 31 fragment, since that's the maximum number of entries in a buffer argument table (https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
    private unowned(unsafe) var boundPipelineState: MTLRenderPipelineState? = nil
    private unowned(unsafe) var boundDepthStencilState: MTLDepthStencilState? = nil
    
    private var triangleFillMode: TriangleFillMode = .fill
    private var depthClipMode: DepthClipMode = .clip
    
    init(encoder: MTLRenderCommandEncoder, renderPassDescriptor: MTLRenderPassDescriptor, isAppleSiliconGPU: Bool) {
        self.encoder = encoder
        self.renderPassDescriptor = renderPassDescriptor
        self.isAppleSiliconGPU = isAppleSiliconGPU
        
        
        self.boundBuffers = .allocate(capacity: 62)
        self.boundBuffers.initialize(repeating: nil, count: 62)
        self.baseBufferOffsets = .allocate(capacity: 62)
        self.baseBufferOffsets.initialize(repeating: 0, count: 62)
    }
    
    deinit {
        self.boundBuffers.deallocate()
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
    
    func executePass(_ pass: RenderPassRecord, resourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>], renderTarget: RenderTargetDescriptor, passRenderTarget: RenderTargetDescriptor, resourceMap: FrameResourceMap<MetalBackend>, stateCaches: MetalStateCaches) async {
        
        await RenderGraph.signposter.withIntervalSignpost("Encode Render Pass Commands", "Encode pass commands for pass \(pass.name)") {
            var resourceCommandIndex = resourceCommands.binarySearch { $0.index < pass.commandRange!.lowerBound }
            
            if passRenderTarget.depthAttachment == nil && passRenderTarget.stencilAttachment == nil, (self.renderPassDescriptor.depthAttachment.texture != nil || self.renderPassDescriptor.stencilAttachment.texture != nil) {
                let depthState = stateCaches.depthStencilCache.defaultDepthState
                encoder.setDepthStencilState(depthState) // The render pass unexpectedly has a depth/stencil attachment, so make sure the depth stencil state is set to the default.
                self.boundDepthStencilState = depthState
            }
            
            for (i, command) in zip(pass.commandRange!, pass.commands) {
                await self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i, resourceMap: resourceMap)
                await self.executeCommand(command, encoder: encoder, renderTarget: renderTarget, resourceMap: resourceMap, stateCaches: stateCaches)
                await self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i, resourceMap: resourceMap)
            }
        }
    }
    
    func endEncoding() {
        self.encoder.endEncoding()
    }
    
    private func setBuffer(_ mtlBuffer: MTLBufferReference?, offset: Int, bindIndex: Int, stages: MTLRenderStages) {
        guard let mtlBuffer = mtlBuffer else {
            if stages.contains(.vertex) {
                self.boundBuffers[bindIndex] = nil
            }
            if stages.contains(.fragment) || !self.hasFragmentFunction { // If we currently have no fragment function, but later set one after binding an argument buffer, that argument buffer should also be bound for the fragment function.
                self.boundBuffers[bindIndex + 31] = nil
            }
            return
        }

        let totalOffset = offset + mtlBuffer.offset
        
        if stages.contains(.vertex) {
            self.baseBufferOffsets[bindIndex] = mtlBuffer.offset
            if self.boundBuffers[bindIndex] == mtlBuffer._buffer.toOpaque() {
                encoder.setVertexBufferOffset(totalOffset, index: bindIndex)
            } else {
                self.boundBuffers[bindIndex] = mtlBuffer._buffer.toOpaque()
                encoder.setVertexBuffer(mtlBuffer.buffer, offset: totalOffset, index: bindIndex)
            }
        }
        if stages.contains(.fragment) || !self.hasFragmentFunction { // If we currently have no fragment function, but later set one after binding an argument buffer, that argument buffer should also be bound for the fragment function.
            self.baseBufferOffsets[bindIndex + 31] = mtlBuffer.offset
            if self.boundBuffers[bindIndex + 31] == mtlBuffer._buffer.toOpaque() {
                encoder.setFragmentBufferOffset(totalOffset, index: bindIndex)
            } else {
                self.boundBuffers[bindIndex + 31] = mtlBuffer._buffer.toOpaque()
                encoder.setFragmentBuffer(mtlBuffer.buffer, offset: totalOffset, index: bindIndex)
            }
        }
    }
    
    func executeCommand(_ command: RenderGraphCommand, encoder: MTLRenderCommandEncoder, renderTarget: RenderTargetDescriptor, resourceMap: FrameResourceMap<MetalBackend>, stateCaches: MetalStateCaches) async {
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
                self.boundBuffers[mtlBindingPath.bindIndex] = nil
            }
            if stages.contains(.fragment) {
                encoder.setFragmentBytes(args.pointee.bytes, length: Int(args.pointee.length), index: mtlBindingPath.bindIndex)
                self.boundBuffers[mtlBindingPath.bindIndex] = nil
            }
            
        case .setVertexBuffer(let args):
            let mtlBuffer : MTLBufferReference?
            if let buffer = args.pointee.buffer {
                mtlBuffer = resourceMap[buffer]
            } else {
                mtlBuffer = nil
            }
            let index = Int(args.pointee.index)
            assert(index < 31, "The maximum number of buffers allowed in the buffer argument table for a single function is 31.")
            // For vertex buffers, index the bindings backwards from the maximum (30) to allow argument buffers and push constants to go first.
            
            self.setBuffer(mtlBuffer, offset: Int(args.pointee.offset), bindIndex: 30 - index, stages: .vertex)
            
        case .setVertexBufferOffset(let offset, let index):
            let baseOffset = self.baseBufferOffsets[30 - Int(index)]
            encoder.setVertexBufferOffset(Int(offset) + baseOffset, index: 30 - Int(index))
            
        case .setArgumentBuffer(let args):
            let bindingPath = args.pointee.bindingPath
            let mtlBindingPath = bindingPath
            let stages = mtlBindingPath.stages
            
            let argumentBuffer = args.pointee.argumentBuffer
            let mtlArgumentBuffer = resourceMap[argumentBuffer]
            
            self.setBuffer(mtlArgumentBuffer, offset: 0, bindIndex: mtlBindingPath.bindIndex, stages: stages)
            
        case .setArgumentBufferArray(let args):
            let bindingPath = args.pointee.bindingPath
            let mtlBindingPath = bindingPath
            let stages = mtlBindingPath.stages
            
            let argumentBuffer = args.pointee.argumentBuffer
            let mtlArgumentBuffer = resourceMap[argumentBuffer]
            
            self.setBuffer(mtlArgumentBuffer, offset: 0, bindIndex: mtlBindingPath.bindIndex, stages: stages)
            
        case .setBuffer(let args):
            guard let mtlBuffer = resourceMap[args.pointee.buffer] else {
                break
            }
            
            let mtlBindingPath = args.pointee.bindingPath
            assert(mtlBindingPath.bindIndex < 31, "The maximum number of buffers allowed in the buffer argument table for a single function is 31.")
            
            let stages = mtlBindingPath.stages
            self.setBuffer(mtlBuffer, offset: Int(args.pointee.offset), bindIndex: mtlBindingPath.bindIndex, stages: stages)
            
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
            guard let mtlTexture = resourceMap[args.pointee.texture]?.texture else { break }
            
            let mtlBindingPath = args.pointee.bindingPath
            let stages = mtlBindingPath.stages
            if stages.contains(.vertex) {
                encoder.setVertexTexture(mtlTexture, index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                encoder.setFragmentTexture(mtlTexture, index: mtlBindingPath.bindIndex)
            }
            
        case .setSamplerState(let args):
            let state = await resourceMap[args.pointee.descriptor]
            
            let mtlBindingPath = args.pointee.bindingPath
            let stages = mtlBindingPath.stages
            if stages.contains(.vertex) {
                encoder.setVertexSamplerState(state, index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                encoder.setFragmentSamplerState(state, index: mtlBindingPath.bindIndex)
            }
            
        case .setAccelerationStructure(let args):
            guard #available(macOS 12.0, iOS 15.0, *), let mtlStructure = resourceMap[args.pointee.structure] else {
                break
            }
            
            let mtlBindingPath = args.pointee.bindingPath
            let stages = mtlBindingPath.stages
            if stages.contains(.vertex) {
                encoder.setVertexAccelerationStructure((mtlStructure as! MTLAccelerationStructure), bufferIndex: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                encoder.setFragmentAccelerationStructure((mtlStructure as! MTLAccelerationStructure), bufferIndex: mtlBindingPath.bindIndex)
            }
            
        case .setVisibleFunctionTable(let args):
            guard #available(macOS 12.0, iOS 15.0, *), let mtlTable = resourceMap[args.pointee.table] else {
                break
            }
            
            let mtlBindingPath = args.pointee.bindingPath
            let stages = mtlBindingPath.stages
            if stages.contains(.vertex) {
                encoder.setVertexVisibleFunctionTable(mtlTable.table, bufferIndex: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                encoder.setFragmentVisibleFunctionTable(mtlTable.table, bufferIndex: mtlBindingPath.bindIndex)
            }
            
        case .setIntersectionFunctionTable(let args):
            guard #available(macOS 12.0, iOS 15.0, *), let mtlTable = resourceMap[args.pointee.table] else {
                break
            }
            
            let mtlBindingPath = args.pointee.bindingPath
            let stages = mtlBindingPath.stages
            if stages.contains(.vertex) {
                encoder.setVertexIntersectionFunctionTable(mtlTable.table, bufferIndex: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                encoder.setFragmentIntersectionFunctionTable(mtlTable.table, bufferIndex: mtlBindingPath.bindIndex)
            }
            
        case .setRenderPipelineDescriptor(let descriptorPtr):
            let descriptor = descriptorPtr.takeUnretainedValue().value
            self.hasFragmentFunction = !descriptor.fragmentFunction.name.isEmpty
            
            if descriptor.fillMode != self.triangleFillMode {
                self.encoder.setTriangleFillMode(MTLTriangleFillMode(descriptor.fillMode))
                self.triangleFillMode = descriptor.fillMode
            }
                
            let state = await stateCaches.renderPipelineCache[descriptor, renderTarget: renderTarget]!
            if state !== self.boundPipelineState {
                encoder.setRenderPipelineState(state)
                self.boundPipelineState = state
            }
            
        case .setRenderPipelineState(let statePtr):
            let mtlState = Unmanaged<MTLRenderPipelineState>.fromOpaque(statePtr.pointee.state).takeUnretainedValue()
            self.hasFragmentFunction = statePtr.pointee.hasFragmentFunction
            
            if statePtr.pointee.triangleFillMode != self.triangleFillMode {
                self.encoder.setTriangleFillMode(MTLTriangleFillMode(statePtr.pointee.triangleFillMode))
                self.triangleFillMode = statePtr.pointee.triangleFillMode
            }
                
            if mtlState !== self.boundPipelineState {
                encoder.setRenderPipelineState(mtlState)
                self.boundPipelineState = mtlState
            }
            
        case .drawPrimitives(let args):
            encoder.drawPrimitives(type: MTLPrimitiveType(args.pointee.primitiveType), vertexStart: Int(args.pointee.vertexStart), vertexCount: Int(args.pointee.vertexCount), instanceCount: Int(args.pointee.instanceCount), baseInstance: Int(args.pointee.baseInstance))
            
        case .drawIndexedPrimitives(let args):
            let indexBuffer = resourceMap[args.pointee.indexBuffer]!
            
            encoder.drawIndexedPrimitives(type: MTLPrimitiveType(args.pointee.primitiveType), indexCount: Int(args.pointee.indexCount), indexType: MTLIndexType(args.pointee.indexType), indexBuffer: indexBuffer.buffer, indexBufferOffset: Int(args.pointee.indexBufferOffset) + indexBuffer.offset, instanceCount: Int(args.pointee.instanceCount), baseVertex: Int(args.pointee.baseVertex), baseInstance: Int(args.pointee.baseInstance))
            
        case .setViewport(let viewportPtr):
            encoder.setViewport(MTLViewport(viewportPtr.pointee))
            
        case .setFrontFacing(let winding):
            encoder.setFrontFacing(MTLWinding(winding))
            
        case .setCullMode(let cullMode):
            encoder.setCullMode(MTLCullMode(cullMode))
            
        case .setDepthStencilDescriptor(let descriptorPtr):
            let descriptor = descriptorPtr.takeUnretainedValue().value
            
            if descriptor.depthClipMode != self.depthClipMode {
                self.encoder.setDepthClipMode(MTLDepthClipMode(descriptor.depthClipMode))
                self.depthClipMode = descriptor.depthClipMode
            }
            
            let state = await stateCaches.depthStencilCache[descriptor]
            if state !== self.boundDepthStencilState, renderTarget.depthAttachment != nil || renderTarget.stencilAttachment != nil {
                encoder.setDepthStencilState(state)
                self.boundDepthStencilState = state
            }
            
        case .setScissorRect(let scissorPtr):
            encoder.setScissorRect(MTLScissorRect(scissorPtr.pointee))
            
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
    
    func checkResourceCommands(_ resourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>], resourceCommandIndex: inout Int, phase: PerformOrder, commandIndex: Int, resourceMap: FrameResourceMap<MetalBackend>) async {
        while resourceCommandIndex < resourceCommands.count, commandIndex == resourceCommands[resourceCommandIndex].index, phase == resourceCommands[resourceCommandIndex].order {
            defer { resourceCommandIndex += 1 }
            
            switch resourceCommands[resourceCommandIndex].command {
                
            case .resourceMemoryBarrier(let resources, let afterStages, let beforeStages):
                #if os(macOS) || targetEnvironment(macCatalyst)
                if !self.isAppleSiliconGPU {
                    encoder.__memoryBarrier(resources: resources.baseAddress!, count: resources.count, after: afterStages, before: beforeStages)
                }
                #else
                break
                #endif
                
            case .scopedMemoryBarrier(let scope, let afterStages, let beforeStages):
                #if os(macOS) || targetEnvironment(macCatalyst)
                if !self.isAppleSiliconGPU {
                    encoder.memoryBarrier(scope: scope, after: afterStages, before: beforeStages)
                }
                #else
                break
                #endif
                
            case .updateFence(let fence, let afterStages):
                self.updateFence(fence.fence, afterStages: afterStages)
                
            case .waitForFence(let fence, let beforeStages):
                self.waitForFence(fence.fence, beforeStages: beforeStages)
                
            case .useResources(let resources, let usage, let stages):
                if #available(iOS 13.0, macOS 10.15, *) {
                    encoder.use(resources.baseAddress!, count: resources.count, usage: usage, stages: stages)
                } else {
                    encoder.__use(resources.baseAddress!, count: resources.count, usage: usage)
                }
            }
        }
    }
    
    func waitForFence(_ fence: MTLFence, beforeStages: MTLRenderStages?) {
        encoder.waitForFence(fence, before: beforeStages!)
    }
    
    func updateFence(_ fence: MTLFence, afterStages: MTLRenderStages?) {
        encoder.updateFence(fence, after: afterStages!)
    }
}

final class FGMTLComputeCommandEncoder {
    let encoder: MTLComputeCommandEncoder
    let isAppleSiliconGPU: Bool
    
    private let boundBuffers : UnsafeMutablePointer<UnsafeMutableRawPointer?>
    private let baseBufferOffsets : UnsafeMutablePointer<Int> // 31, since that's the maximum number of entries in a buffer argument table (https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
    private unowned(unsafe) var boundPipelineState: MTLComputePipelineState? = nil
    
    init(encoder: MTLComputeCommandEncoder, isAppleSiliconGPU: Bool) {
        self.encoder = encoder
        self.isAppleSiliconGPU = isAppleSiliconGPU
        
        self.boundBuffers = .allocate(capacity: 31)
        self.boundBuffers.initialize(repeating: nil, count: 31)
        self.baseBufferOffsets = .allocate(capacity: 31)
        self.baseBufferOffsets.initialize(repeating: 0, count: 31)
    }
    
    deinit {
        self.boundBuffers.deallocate()
        self.baseBufferOffsets.deallocate()
    }
    
    private func setBuffer(_ mtlBuffer: MTLBufferReference?, offset: Int, bindIndex: Int) {
        guard let mtlBuffer = mtlBuffer else {
            self.boundBuffers[bindIndex] = nil
            return
        }

        let totalOffset = offset + mtlBuffer.offset
        
        self.baseBufferOffsets[bindIndex] = mtlBuffer.offset
        if self.boundBuffers[bindIndex] == mtlBuffer._buffer.toOpaque() {
            encoder.setBufferOffset(totalOffset, index: bindIndex)
        } else {
            self.boundBuffers[bindIndex] = mtlBuffer._buffer.toOpaque()
            encoder.setBuffer(mtlBuffer.buffer, offset: totalOffset, index: bindIndex)
        }
    }
    
    func executePass(_ pass: RenderPassRecord, resourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>], resourceMap: FrameResourceMap<MetalBackend>, stateCaches: MetalStateCaches) async {
        await RenderGraph.signposter.withIntervalSignpost("Encode Compute Pass Commands", "Encode pass commands for pass \(pass.name)") {
            
            var resourceCommandIndex = resourceCommands.binarySearch { $0.index < pass.commandRange!.lowerBound }
            
            for (i, command) in zip(pass.commandRange!, pass.commands) {
                await self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i, resourceMap: resourceMap)
                await self.executeCommand(command, resourceMap: resourceMap, stateCaches: stateCaches)
                await self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i, resourceMap: resourceMap)
            }
        }
    }
    
    func executeCommand(_ command: RenderGraphCommand, resourceMap: FrameResourceMap<MetalBackend>, stateCaches: MetalStateCaches) async {
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
            let mtlArgumentBuffer = resourceMap[argumentBuffer]
            self.setBuffer(mtlArgumentBuffer, offset: 0, bindIndex: mtlBindingPath.bindIndex)
            
        case .setArgumentBufferArray(let args):
            let bindingPath = args.pointee.bindingPath
            let mtlBindingPath = bindingPath
            
            let argumentBuffer = args.pointee.argumentBuffer
            let mtlArgumentBuffer = resourceMap[argumentBuffer]
            
            self.setBuffer(mtlArgumentBuffer, offset: 0, bindIndex: mtlBindingPath.bindIndex)
            
        case .setBytes(let args):
            let mtlBindingPath = args.pointee.bindingPath
            encoder.setBytes(args.pointee.bytes, length: Int(args.pointee.length), index: mtlBindingPath.bindIndex)
            self.boundBuffers[mtlBindingPath.bindIndex] = nil
            
        case .setBuffer(let args):
            let mtlBindingPath = args.pointee.bindingPath
            guard let mtlBuffer = resourceMap[args.pointee.buffer] else { break }
            
            self.setBuffer(mtlBuffer, offset: Int(args.pointee.offset), bindIndex: mtlBindingPath.bindIndex)
            
        case .setBufferOffset(let args):
            let mtlBindingPath = args.pointee.bindingPath
            let baseOffset = self.baseBufferOffsets[mtlBindingPath.bindIndex]
            encoder.setBufferOffset(Int(args.pointee.offset) + baseOffset, index: mtlBindingPath.bindIndex)
            
        case .setTexture(let args):
            let mtlBindingPath = args.pointee.bindingPath
            guard let mtlTexture = resourceMap[args.pointee.texture] else { break }
            encoder.setTexture(mtlTexture.texture, index: mtlBindingPath.bindIndex)
            
        case .setAccelerationStructure(let args):
            guard #available(macOS 11.0, iOS 14.0, *), let mtlStructure = resourceMap[args.pointee.structure] else {
                break
            }
            
            let mtlBindingPath = args.pointee.bindingPath
            encoder.setAccelerationStructure((mtlStructure as! MTLAccelerationStructure), bufferIndex: mtlBindingPath.bindIndex)
            
        case .setVisibleFunctionTable(let args):
            guard #available(macOS 11.0, iOS 14.0, *), let mtlTable = resourceMap[args.pointee.table] else {
                break
            }
            
            let mtlBindingPath = args.pointee.bindingPath
            encoder.setVisibleFunctionTable(mtlTable.table, bufferIndex: mtlBindingPath.bindIndex)
            
        case .setIntersectionFunctionTable(let args):
            guard #available(macOS 11.0, iOS 14.0, *), let mtlTable = resourceMap[args.pointee.table] else {
                break
            }
            
            let mtlBindingPath = args.pointee.bindingPath
            encoder.setIntersectionFunctionTable(mtlTable.table, bufferIndex: mtlBindingPath.bindIndex)
            
        case .setSamplerState(let args):
            let mtlBindingPath = args.pointee.bindingPath
            let state = await resourceMap[args.pointee.descriptor]
            encoder.setSamplerState(state, index: mtlBindingPath.bindIndex)
            
        case .dispatchThreads(let args):
            encoder.dispatchThreads(MTLSize(args.pointee.threads), threadsPerThreadgroup: MTLSize(args.pointee.threadsPerThreadgroup))
            
        case .dispatchThreadgroups(let args):
            encoder.dispatchThreadgroups(MTLSize(args.pointee.threadgroupsPerGrid), threadsPerThreadgroup: MTLSize(args.pointee.threadsPerThreadgroup))
            
        case .dispatchThreadgroupsIndirect(let args):
            let indirectBuffer = resourceMap[args.pointee.indirectBuffer]!
            encoder.dispatchThreadgroups(indirectBuffer: indirectBuffer.buffer, indirectBufferOffset: Int(args.pointee.indirectBufferOffset) + indirectBuffer.offset, threadsPerThreadgroup: MTLSize(args.pointee.threadsPerThreadgroup))
            
        case .setComputePipelineDescriptor(let descriptorPtr):
            let descriptor = descriptorPtr.takeUnretainedValue()
            let state = await stateCaches.computePipelineCache[descriptor.pipelineDescriptor, descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth]!
            if state !== self.boundPipelineState {
                encoder.setComputePipelineState(state)
                self.boundPipelineState = state
            }
            
        case .setComputePipelineState(let statePtr):
            let state = statePtr.takeUnretainedValue()
            let mtlState = Unmanaged<MTLComputePipelineState>.fromOpaque(UnsafeRawPointer(state.state)).takeUnretainedValue()
            if mtlState !== self.boundPipelineState {
                encoder.setComputePipelineState(mtlState)
                self.boundPipelineState = mtlState
            }
            
        case .setStageInRegion(let regionPtr):
            encoder.setStageInRegion(MTLRegion(regionPtr.pointee))
            
        case .setThreadgroupMemoryLength(let length, let index):
            encoder.setThreadgroupMemoryLength(Int(length), index: Int(index))
            
        default:
            fatalError()
        }
    }
    
    func checkResourceCommands(_ resourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>], resourceCommandIndex: inout Int, phase: PerformOrder, commandIndex: Int, resourceMap: FrameResourceMap<MetalBackend>) async {
        while resourceCommandIndex < resourceCommands.count, commandIndex == resourceCommands[resourceCommandIndex].index, phase == resourceCommands[resourceCommandIndex].order {
            defer { resourceCommandIndex += 1 }
            
            switch resourceCommands[resourceCommandIndex].command {
                
            case .resourceMemoryBarrier(let resources, _, _):
                encoder.__memoryBarrier(resources: resources.baseAddress!, count: resources.count)

            case .scopedMemoryBarrier(let scope, _, _):
                encoder.memoryBarrier(scope: scope)
                
            case .updateFence(let fence, _):
                encoder.updateFence(fence.fence)
                
            case .waitForFence(let fence, _):
                encoder.waitForFence(fence.fence)
                
            case .useResources(let resources, let usage, _):
                encoder.__use(resources.baseAddress!, count: resources.count, usage: usage)
            }
            
        }
    }
    
    func endEncoding() {
        self.encoder.endEncoding()
    }
}

final class FGMTLBlitCommandEncoder {
    let encoder: MTLBlitCommandEncoder
    let isAppleSiliconGPU: Bool
    
    init(encoder: MTLBlitCommandEncoder, isAppleSiliconGPU: Bool) {
        self.encoder = encoder
        self.isAppleSiliconGPU = isAppleSiliconGPU
    }
    
    func executePass(_ pass: RenderPassRecord, resourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>], resourceMap: FrameResourceMap<MetalBackend>, stateCaches: MetalStateCaches) async {
        
        await RenderGraph.signposter.withIntervalSignpost("Encode Blit Pass Commands", "Encode pass commands for pass \(pass.name)") {
            var resourceCommandIndex = resourceCommands.binarySearch { $0.index < pass.commandRange!.lowerBound }
            
            for (i, command) in zip(pass.commandRange!, pass.commands) {
                await self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i, resourceMap: resourceMap)
                self.executeCommand(command, resourceMap: resourceMap, stateCaches: stateCaches)
                await self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i, resourceMap: resourceMap)
            }
        }
    }
    
    func executeCommand(_ command: RenderGraphCommand, resourceMap: FrameResourceMap<MetalBackend>, stateCaches: MetalStateCaches) {
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
            let sourceBuffer = resourceMap[args.pointee.sourceBuffer]!
            encoder.copy(from: sourceBuffer.buffer, sourceOffset: Int(args.pointee.sourceOffset) + sourceBuffer.offset, sourceBytesPerRow: Int(args.pointee.sourceBytesPerRow), sourceBytesPerImage: Int(args.pointee.sourceBytesPerImage), sourceSize: MTLSize(args.pointee.sourceSize), to: resourceMap[args.pointee.destinationTexture]!.texture, destinationSlice: Int(args.pointee.destinationSlice), destinationLevel: Int(args.pointee.destinationLevel), destinationOrigin: MTLOrigin(args.pointee.destinationOrigin), options: MTLBlitOption(args.pointee.options))
            
        case .copyBufferToBuffer(let args):
            let sourceBuffer = resourceMap[args.pointee.sourceBuffer]!
            let destinationBuffer = resourceMap[args.pointee.destinationBuffer]!
            encoder.copy(from: sourceBuffer.buffer, sourceOffset: Int(args.pointee.sourceOffset) + sourceBuffer.offset, to: destinationBuffer.buffer, destinationOffset: Int(args.pointee.destinationOffset) + destinationBuffer.offset, size: Int(args.pointee.size))
            
        case .copyTextureToBuffer(let args):
            let destinationBuffer = resourceMap[args.pointee.destinationBuffer]!
            encoder.copy(from: resourceMap[args.pointee.sourceTexture]!.texture, sourceSlice: Int(args.pointee.sourceSlice), sourceLevel: Int(args.pointee.sourceLevel), sourceOrigin: MTLOrigin(args.pointee.sourceOrigin), sourceSize: MTLSize(args.pointee.sourceSize), to: destinationBuffer.buffer, destinationOffset: Int(args.pointee.destinationOffset) + destinationBuffer.offset, destinationBytesPerRow: Int(args.pointee.destinationBytesPerRow), destinationBytesPerImage: Int(args.pointee.destinationBytesPerImage), options: MTLBlitOption(args.pointee.options))
            
        case .copyTextureToTexture(let args):
            encoder.copy(from: resourceMap[args.pointee.sourceTexture]!.texture, sourceSlice: Int(args.pointee.sourceSlice), sourceLevel: Int(args.pointee.sourceLevel), sourceOrigin: MTLOrigin(args.pointee.sourceOrigin), sourceSize: MTLSize(args.pointee.sourceSize), to: resourceMap[args.pointee.destinationTexture]!.texture, destinationSlice: Int(args.pointee.destinationSlice), destinationLevel: Int(args.pointee.destinationLevel), destinationOrigin: MTLOrigin(args.pointee.destinationOrigin))
            
        case .fillBuffer(let args):
            let buffer = resourceMap[args.pointee.buffer]!
            let range = (args.pointee.range.lowerBound + buffer.offset)..<(args.pointee.range.upperBound + buffer.offset)
            encoder.fill(buffer: buffer.buffer, range: range, value: args.pointee.value)
            
        case .generateMipmaps(let texture):
            encoder.generateMipmaps(for: resourceMap[texture]!.texture)
            
        case .synchroniseTexture(let textureHandle):
            #if os(macOS) || targetEnvironment(macCatalyst)
            if !self.isAppleSiliconGPU {
                encoder.synchronize(resource: resourceMap[textureHandle]!.texture)
            }
            #else
            break
            #endif
            
        case .synchroniseTextureSlice(let args):
            #if os(macOS) || targetEnvironment(macCatalyst)
            if !self.isAppleSiliconGPU {
                encoder.synchronize(texture: resourceMap[args.pointee.texture]!.texture, slice: Int(args.pointee.slice), level: Int(args.pointee.level))
            }
            #else
            break
            #endif
            
        case .synchroniseBuffer(let buffer):
            #if os(macOS) || targetEnvironment(macCatalyst)
            if !self.isAppleSiliconGPU {
                let buffer = resourceMap[buffer]!
                encoder.synchronize(resource: buffer.buffer)
            }
            #else
            break
            #endif
            
        default:
            fatalError()
        }
    }
    
    func checkResourceCommands(_ resourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>], resourceCommandIndex: inout Int, phase: PerformOrder, commandIndex: Int, resourceMap: FrameResourceMap<MetalBackend>) async {
        while resourceCommandIndex < resourceCommands.count, commandIndex == resourceCommands[resourceCommandIndex].index, phase == resourceCommands[resourceCommandIndex].order {
            defer { resourceCommandIndex += 1 }
            
            switch resourceCommands[resourceCommandIndex].command {
            case .resourceMemoryBarrier, .scopedMemoryBarrier, .useResources:
                break
                
            case .updateFence(let fence, _):
                encoder.updateFence(fence.fence)
                
            case .waitForFence(let fence, _):
                encoder.waitForFence(fence.fence)
            }
            
        }
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
    
    func executePass(_ pass: RenderPassRecord, resourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>], resourceMap: FrameResourceMap<MetalBackend>, stateCaches: MetalStateCaches) async {
        
        await RenderGraph.signposter.withIntervalSignpost("Encode Exteranl Pass Commands", "Encode pass commands for pass \(pass.name)") {
            for (_, command) in zip(pass.commandRange!, pass.commands) {
                self.executeCommand(command, resourceMap: resourceMap, stateCaches: stateCaches)
            }
        }
    }
    
    func executeCommand(_ command: RenderGraphCommand, resourceMap: FrameResourceMap<MetalBackend>, stateCaches: MetalStateCaches) {
        switch command {
        case .encodeExternalCommand(let closure):
            closure.takeUnretainedValue().command(Unmanaged.passUnretained(self.commandBuffer).toOpaque())
            
        case .encodeRayIntersection(let args):
            let intersector = args.pointee.intersector.takeUnretainedValue()
            
            let rayBuffer = resourceMap[args.pointee.rayBuffer]!
            let intersectionBuffer = resourceMap[args.pointee.intersectionBuffer]!
            
            intersector.encodeIntersection(commandBuffer: self.commandBuffer, intersectionType: args.pointee.intersectionType, rayBuffer: rayBuffer.buffer, rayBufferOffset: rayBuffer.offset + args.pointee.rayBufferOffset, intersectionBuffer: intersectionBuffer.buffer, intersectionBufferOffset: intersectionBuffer.offset + args.pointee.intersectionBufferOffset, rayCount: args.pointee.rayCount, accelerationStructure: args.pointee.accelerationStructure.takeUnretainedValue())
            
        case .encodeRayIntersectionRayCountBuffer(let args):
            
            let intersector = args.pointee.intersector.takeUnretainedValue()
            
            let rayBuffer = resourceMap[args.pointee.rayBuffer]!
            let intersectionBuffer = resourceMap[args.pointee.intersectionBuffer]!
            let rayCountBuffer = resourceMap[args.pointee.rayCountBuffer]!
            
            intersector.encodeIntersection(commandBuffer: self.commandBuffer, intersectionType: args.pointee.intersectionType, rayBuffer: rayBuffer.buffer, rayBufferOffset: rayBuffer.offset + args.pointee.rayBufferOffset, intersectionBuffer: intersectionBuffer.buffer, intersectionBufferOffset: intersectionBuffer.offset + args.pointee.intersectionBufferOffset, rayCountBuffer: rayCountBuffer.buffer, rayCountBufferOffset: rayCountBuffer.offset + args.pointee.rayCountBufferOffset, accelerationStructure: args.pointee.accelerationStructure.takeUnretainedValue())
            
        default:
            break
        }
    }
    
}

@available(macOS 11.0, iOS 14.0, *)
final class FGMTLAccelerationStructureCommandEncoder {
    let encoder: MTLAccelerationStructureCommandEncoder
    let isAppleSiliconGPU: Bool
    
    init(encoder: MTLAccelerationStructureCommandEncoder, isAppleSiliconGPU: Bool) {
        self.encoder = encoder
        self.isAppleSiliconGPU = isAppleSiliconGPU
    }
    
    func executePass(_ pass: RenderPassRecord, resourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>], resourceMap: FrameResourceMap<MetalBackend>, stateCaches: MetalStateCaches) async {
        await RenderGraph.signposter.withIntervalSignpost("Encode Acceleration Structure Pass Commands", "Encode pass commands for pass \(pass.name)") {
            var resourceCommandIndex = resourceCommands.binarySearch { $0.index < pass.commandRange!.lowerBound }
            
            for (i, command) in zip(pass.commandRange!, pass.commands) {
                await self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i, resourceMap: resourceMap)
                self.executeCommand(command, resourceMap: resourceMap, stateCaches: stateCaches)
                await self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i, resourceMap: resourceMap)
            }
        }
    }
    
    func executeCommand(_ command: RenderGraphCommand, resourceMap: FrameResourceMap<MetalBackend>, stateCaches: MetalStateCaches) {
        switch command {
        case .insertDebugSignpost(let cString):
            encoder.insertDebugSignpost(String(cString: cString))
            
        case .setLabel(let label):
            encoder.label = String(cString: label)
            
        case .pushDebugGroup(let groupName):
            encoder.pushDebugGroup(String(cString: groupName))
            
        case .popDebugGroup:
            encoder.popDebugGroup()
            
        case .buildAccelerationStructure(let args):
            let structure = resourceMap[args.pointee.structure]! as! MTLAccelerationStructure
            let descriptor = args.pointee.descriptor.metalDescriptor(resourceMap: resourceMap)
            let scratchBuffer = resourceMap[args.pointee.scratchBuffer]!
            let scratchBufferOffset = args.pointee.scratchBufferOffset
            encoder.build(accelerationStructure: structure, descriptor: descriptor, scratchBuffer: scratchBuffer.buffer, scratchBufferOffset: scratchBuffer.offset + scratchBufferOffset)
            
        case .refitAccelerationStructure(let args):
            let source = resourceMap[args.pointee.source]! as! MTLAccelerationStructure
            let descriptor = args.pointee.descriptor.metalDescriptor(resourceMap: resourceMap)
            let destination = args.pointee.destination.map { resourceMap[$0]! as! MTLAccelerationStructure }
            let scratchBuffer = resourceMap[args.pointee.scratchBuffer]!
            let scratchBufferOffset = args.pointee.scratchBufferOffset
            
            encoder.refit(sourceAccelerationStructure: source, descriptor: descriptor, destinationAccelerationStructure: destination, scratchBuffer: scratchBuffer.buffer, scratchBufferOffset: scratchBuffer.offset + scratchBufferOffset)
            
        case .copyAccelerationStructure(let args):
            let source = resourceMap[args.pointee.source]! as! MTLAccelerationStructure
            let destination = resourceMap[args.pointee.destination]! as! MTLAccelerationStructure
            encoder.copy(sourceAccelerationStructure: source, destinationAccelerationStructure: destination)
            
        case .writeCompactedAccelerationStructureSize(let args):
            let structure = resourceMap[args.pointee.structure]! as! MTLAccelerationStructure
            let buffer = resourceMap[args.pointee.toBuffer]!
            let bufferOffset = args.pointee.bufferOffset
            encoder.writeCompactedSize(accelerationStructure: structure, buffer: buffer.buffer, offset: buffer.offset + bufferOffset)
            
        case .copyAndCompactAccelerationStructure(let args):
            let source = resourceMap[args.pointee.source]! as! MTLAccelerationStructure
            let destination = resourceMap[args.pointee.destination]! as! MTLAccelerationStructure
            encoder.copyAndCompact(sourceAccelerationStructure: source, destinationAccelerationStructure: destination)
            
        default:
            fatalError()
        }
    }
    
    func checkResourceCommands(_ resourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>], resourceCommandIndex: inout Int, phase: PerformOrder, commandIndex: Int, resourceMap: FrameResourceMap<MetalBackend>) async {
        while resourceCommandIndex < resourceCommands.count, commandIndex == resourceCommands[resourceCommandIndex].index, phase == resourceCommands[resourceCommandIndex].order {
            defer { resourceCommandIndex += 1 }
            
            switch resourceCommands[resourceCommandIndex].command {
            case .resourceMemoryBarrier, .scopedMemoryBarrier:
                break
                
            case .useResources(let resources, let usage, _):
                encoder.__use(resources.baseAddress!, count: resources.count, usage: usage)
                
            case .updateFence(let fence, _):
                encoder.updateFence(fence.fence)
                
            case .waitForFence(let fence, _):
                encoder.waitForFence(fence.fence)
            }
            
        }
    }
    
    func endEncoding() {
        self.encoder.endEncoding()
    }
}

#endif // canImport(Metal)
