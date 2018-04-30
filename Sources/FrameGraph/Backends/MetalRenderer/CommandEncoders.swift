//
//  CommandEncoders.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 25/12/17.
//

import RenderAPI
import FrameGraph
import Metal

final class EncoderManager {
    
    private let commandBuffer : MTLCommandBuffer
    private let resourceRegistry : ResourceRegistry
    private var previousRenderTarget : MetalRenderTargetDescriptor? = nil
    
    private var renderEncoder : MTLRenderCommandEncoder? = nil
    private var renderEncoderState : MTLRenderCommandEncoderState? = nil
    
    private var computeEncoder : MTLComputeCommandEncoder? = nil
    private var computeEncoderState : MTLComputeCommandEncoderState? = nil
    
    private var blitEncoder : MTLBlitCommandEncoder? = nil
    
    init(commandBuffer: MTLCommandBuffer, resourceRegistry: ResourceRegistry) {
        self.commandBuffer = commandBuffer
        self.resourceRegistry = resourceRegistry
    }
    
    func renderCommandEncoder(descriptor: MetalRenderTargetDescriptor, textureUsages: [Texture : MTLTextureUsage]) -> MTLRenderCommandEncoder {
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
            
            let mtlDescriptor = MTLRenderPassDescriptor(descriptor, resourceRegistry: self.resourceRegistry, textureUsages: textureUsages)
            
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: mtlDescriptor)!
            self.renderEncoder = renderEncoder
            return renderEncoder
        }
    }
    
    func computeCommandEncoder() -> MTLComputeCommandEncoder {
        if let computeEncoder = self.computeEncoder {
            return computeEncoder
        } else {
            self.renderEncoder?.endEncoding()
            self.renderEncoder = nil
            self.previousRenderTarget = nil
            
            self.blitEncoder?.endEncoding()
            self.blitEncoder = nil
            
            let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
            self.computeEncoder = computeEncoder
            return computeEncoder
        }
    }
    
    func blitCommandEncoder() -> MTLBlitCommandEncoder {
        if let blitEncoder = self.blitEncoder {
            return blitEncoder
        } else {
            self.renderEncoder?.endEncoding()
            self.renderEncoder = nil
            self.previousRenderTarget = nil
            
            self.computeEncoder?.endEncoding()
            self.computeEncoder = nil
            
            let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
            self.blitEncoder = blitEncoder
            return blitEncoder
        }
    }
    
    func endEncoding() {
        self.renderEncoder?.endEncoding()
        self.computeEncoder?.endEncoding()
        self.blitEncoder?.endEncoding()
    }
}

struct BufferOffsetKey : Hashable {
    var stage : MTLRenderStages
    var index : Int
    
    var hashValue: Int {
        return self.index &* 51 &+ Int(stage.rawValue)
    }
}

class MTLRenderCommandEncoderState {
    var pipelineDescriptor : RenderPipelineDescriptor? = nil
    var baseBufferOffsets = [BufferOffsetKey : Int]()
}

class MTLComputeCommandEncoderState {
    var pipelineDescriptor : ComputePipelineDescriptor? = nil
    var baseBufferOffsets = [Int : Int]()
}

extension MTLRenderCommandEncoder {
    
    func executePass(commands: ArraySlice<FrameGraphCommand>, resourceCheck: (PerformOrder, Int, MTLCommandEncoder) -> Void, renderTarget: RenderTargetDescriptor, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        let state = MTLRenderCommandEncoderState()
        
        for (i, command) in zip(commands.indices, commands) {
            resourceCheck(.before, i, self)
            self.executeCommand(command, state: state, renderTarget: renderTarget, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
            resourceCheck(.after, i, self)
        }
    }
    
    func executeCommand(_ command: FrameGraphCommand, state: MTLRenderCommandEncoderState, renderTarget: RenderTargetDescriptor, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        switch command {
        case .insertDebugSignpost(let cString):
            self.insertDebugSignpost(String(cString: cString))
            
        case .setLabel(let label):
            self.label = String(cString: label)
            
        case .pushDebugGroup(let groupName):
            self.pushDebugGroup(String(cString: groupName))
            
        case .popDebugGroup:
            self.popDebugGroup()
            
        case .setBytes(let args):
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let stages = mtlBindingPath.stages
            if stages.contains(.vertex) {
                self.setVertexBytes(args.pointee.bytes, length: Int(args.pointee.length), index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                self.setFragmentBytes(args.pointee.bytes, length: Int(args.pointee.length), index: mtlBindingPath.bindIndex)
            }
            
        case .setVertexBuffer(let args):
            let mtlBuffer : MTLBufferReference?
            if let bufferHandle = args.pointee.handle {
                mtlBuffer = resourceRegistry[buffer: bufferHandle]
            } else {
                mtlBuffer = nil
            }
            let index = Int(args.pointee.index)
            self.setVertexBuffer(mtlBuffer?.buffer, offset: Int(args.pointee.offset) + (mtlBuffer?.offset ?? 0), index: index)
            state.baseBufferOffsets[BufferOffsetKey(stage: .vertex, index: index)] = mtlBuffer?.offset ?? 0
            
        case .setVertexBufferOffset(let offset, let index):
            let baseOffset = state.baseBufferOffsets[BufferOffsetKey(stage: .vertex, index: Int(index))] ?? 0
            self.setVertexBufferOffset(Int(offset) + baseOffset, index: Int(index))
            
        case .setArgumentBuffer(let args):
            let bindingPath = args.pointee.bindingPath
            let mtlBindingPath = MetalResourceBindingPath(bindingPath)
            let stages = mtlBindingPath.stages
            
            let argumentBuffer = args.pointee.argumentBuffer.takeUnretainedValue()
            let mtlArgumentBuffer = resourceRegistry.allocateArgumentBufferIfNeeded(argumentBuffer, bindingPath: bindingPath, encoder: { () -> MTLArgumentEncoder in
                let functionName = stages.contains(.vertex) ? state.pipelineDescriptor!.vertexFunction : state.pipelineDescriptor!.fragmentFunction
                return stateCaches.argumentEncoder(atIndex: mtlBindingPath.bindIndex, functionName: functionName!, functionConstants: state.pipelineDescriptor!.functionConstants)
            }, stateCaches: stateCaches)
            
            if stages.contains(.vertex) {
                self.setVertexBuffer(mtlArgumentBuffer.buffer, offset: mtlArgumentBuffer.offset, index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                self.setFragmentBuffer(mtlArgumentBuffer.buffer, offset: mtlArgumentBuffer.offset, index: mtlBindingPath.bindIndex)
            }
            
        case .setBuffer(let args):
            let mtlBuffer = resourceRegistry[buffer: args.pointee.handle]
        
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let stages = mtlBindingPath.stages
            if stages.contains(.vertex) {
                self.setVertexBuffer(mtlBuffer?.buffer, offset: Int(args.pointee.offset) + (mtlBuffer?.offset ?? 0), index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                self.setFragmentBuffer(mtlBuffer?.buffer, offset: Int(args.pointee.offset) + (mtlBuffer?.offset ?? 0), index: mtlBindingPath.bindIndex)
            }
            
            state.baseBufferOffsets[BufferOffsetKey(stage: stages, index: mtlBindingPath.bindIndex)] = (mtlBuffer?.offset ?? 0)
            
        case .setBufferOffset(let args):
            
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let stages = mtlBindingPath.stages
            
            let baseOffset = state.baseBufferOffsets[BufferOffsetKey(stage: stages, index: mtlBindingPath.bindIndex)] ?? 0
            
            if stages.contains(.vertex) {
                self.setVertexBufferOffset(Int(args.pointee.offset) + baseOffset, index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                self.setFragmentBufferOffset(Int(args.pointee.offset) + baseOffset, index: mtlBindingPath.bindIndex)
            }
            
        case .setTexture(let args):
            let mtlTexture = resourceRegistry[texture: args.pointee.handle]
            
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let stages = mtlBindingPath.stages
            if stages.contains(.vertex) {
                self.setVertexTexture(mtlTexture, index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                self.setFragmentTexture(mtlTexture, index: mtlBindingPath.bindIndex)
            }
            
        case .setSamplerState(let args):
            let state = stateCaches[args.pointee.descriptor]
            
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let stages = mtlBindingPath.stages
            if stages.contains(.vertex) {
                self.setVertexSamplerState(state, index: mtlBindingPath.bindIndex)
            }
            if stages.contains(.fragment) {
                self.setFragmentSamplerState(state, index: mtlBindingPath.bindIndex)
            }
            
        case .setRenderPipelineState(let descriptorPtr):
            let descriptor = descriptorPtr.takeUnretainedValue().value
            state.pipelineDescriptor = descriptor
            self.setRenderPipelineState(stateCaches[descriptor, renderTarget: renderTarget])
            
        case .drawPrimitives(let args):
            self.drawPrimitives(type: MTLPrimitiveType(args.pointee.primitiveType), vertexStart: Int(args.pointee.vertexStart), vertexCount: Int(args.pointee.vertexCount), instanceCount: Int(args.pointee.instanceCount), baseInstance: Int(args.pointee.baseInstance))
            
        case .drawIndexedPrimitives(let args):
            let indexBuffer = resourceRegistry[buffer: args.pointee.indexBuffer]!
            
            self.drawIndexedPrimitives(type: MTLPrimitiveType(args.pointee.primitiveType), indexCount: Int(args.pointee.indexCount), indexType: MTLIndexType(args.pointee.indexType), indexBuffer: indexBuffer.buffer, indexBufferOffset: Int(args.pointee.indexBufferOffset) + indexBuffer.offset, instanceCount: Int(args.pointee.instanceCount), baseVertex: Int(args.pointee.baseVertex), baseInstance: Int(args.pointee.baseInstance))
            
        case .setViewport(let viewportPtr):
            self.setViewport(MTLViewport(viewportPtr.pointee))
            
        case .setFrontFacing(let winding):
            self.setFrontFacing(MTLWinding(winding))
            
        case .setCullMode(let cullMode):
            self.setCullMode(MTLCullMode(cullMode))
            
        case .setDepthStencilState(let descriptorPtr):
            let state : MTLDepthStencilState?
            if let descriptor = descriptorPtr.takeUnretainedValue().value {
                state = stateCaches[descriptor]
            } else {
                state = nil
            }
            self.setDepthStencilState(state)
            
        case .setScissorRect(let scissorPtr):
            self.setScissorRect(MTLScissorRect(scissorPtr.pointee))
            
        case .setDepthClipMode(let mode):
            self.setDepthClipMode(MTLDepthClipMode(mode))
            
        case .setDepthBias(let args):
            self.setDepthBias(args.pointee.depthBias, slopeScale: args.pointee.slopeScale, clamp: args.pointee.clamp)
            
        case .setStencilReferenceValue(let value):
            self.setStencilReferenceValue(value)
            
        case .setStencilReferenceValues(let front, let back):
            self.setStencilReferenceValues(front: front, back: back)
            
        default:
            fatalError()
        }
    }
}

extension MTLComputeCommandEncoder {
    
    func executePass(commands: ArraySlice<FrameGraphCommand>, resourceCheck: (PerformOrder, Int, MTLCommandEncoder) -> Void, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        let state = MTLComputeCommandEncoderState()
        
        for (i, command) in zip(commands.indices, commands) {
            resourceCheck(.before, i, self)
            self.executeCommand(command, state: state, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
            resourceCheck(.after, i, self)
        }
    }
    
    func executeCommand(_ command: FrameGraphCommand, state: MTLComputeCommandEncoderState, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        switch command {
        case .insertDebugSignpost(let cString):
            self.insertDebugSignpost(String(cString: cString))
            
        case .setLabel(let label):
            self.label = String(cString: label)
            
        case .pushDebugGroup(let groupName):
            self.pushDebugGroup(String(cString: groupName))
            
        case .popDebugGroup:
            self.popDebugGroup()
            
        case .setArgumentBuffer(let args):
            let bindingPath = args.pointee.bindingPath
            let mtlBindingPath = MetalResourceBindingPath(bindingPath)
            
            let argumentBuffer = args.pointee.argumentBuffer.takeUnretainedValue()
            let mtlArgumentBuffer = resourceRegistry.allocateArgumentBufferIfNeeded(argumentBuffer, bindingPath: bindingPath, encoder: { () -> MTLArgumentEncoder in
                return stateCaches.argumentEncoder(atIndex: mtlBindingPath.bindIndex, functionName: state.pipelineDescriptor!.function, functionConstants: state.pipelineDescriptor!.functionConstants)
            }, stateCaches: stateCaches)
            
            self.setBuffer(mtlArgumentBuffer.buffer, offset: mtlArgumentBuffer.offset, index: mtlBindingPath.bindIndex)
            
        case .setBytes(let args):
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            self.setBytes(args.pointee.bytes, length: Int(args.pointee.length), index: mtlBindingPath.bindIndex)
            
        case .setBuffer(let args):
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let mtlBuffer = resourceRegistry[buffer: args.pointee.handle]
            self.setBuffer(mtlBuffer?.buffer, offset: Int(args.pointee.offset) + (mtlBuffer?.offset ?? 0), index: mtlBindingPath.bindIndex)
            
            state.baseBufferOffsets[mtlBindingPath.bindIndex] = mtlBuffer?.offset ?? 0
            
        case .setBufferOffset(let args):
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let baseOffset = state.baseBufferOffsets[mtlBindingPath.bindIndex] ?? 0
            self.setBufferOffset(Int(args.pointee.offset) + baseOffset, index: mtlBindingPath.bindIndex)
            
        case .setTexture(let args):
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let mtlTexture = resourceRegistry[texture: args.pointee.handle]
            self.setTexture(mtlTexture, index: mtlBindingPath.bindIndex)
            
        case .setSamplerState(let args):
            let mtlBindingPath = MetalResourceBindingPath(args.pointee.bindingPath)
            let state = stateCaches[args.pointee.descriptor]
            self.setSamplerState(state, index: mtlBindingPath.bindIndex)
            
        case .dispatchThreadgroups(let args):
            self.dispatchThreadgroups(MTLSize(args.pointee.threadgroupsPerGrid), threadsPerThreadgroup: MTLSize(args.pointee.threadsPerThreadgroup))
            
        case .dispatchThreadgroupsIndirect(let args):
            let indirectBuffer = resourceRegistry[buffer: args.pointee.indirectBuffer]!
            self.dispatchThreadgroups(indirectBuffer: indirectBuffer.buffer, indirectBufferOffset: Int(args.pointee.indirectBufferOffset) + indirectBuffer.offset, threadsPerThreadgroup: MTLSize(args.pointee.threadsPerThreadgroup))
            
        case .setComputePipelineState(let descriptorPtr):
            let descriptor = descriptorPtr.takeUnretainedValue().value
            state.pipelineDescriptor = descriptor
            self.setComputePipelineState(stateCaches[descriptor])
            
        case .setStageInRegion(let regionPtr):
            self.setStageInRegion(MTLRegion(regionPtr.pointee))
            
        case .setThreadgroupMemoryLength(let length, let index):
            self.setThreadgroupMemoryLength(Int(length), index: Int(index))
            
        default:
            fatalError()
        }
    }
}

extension MTLBlitCommandEncoder {
    
    func executeCommands(_ commands: ArraySlice<FrameGraphCommand>, resourceCheck: (PerformOrder, Int, MTLCommandEncoder) -> Void, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        for (i, command) in zip(commands.indices, commands) {
            resourceCheck(.before, i, self)
            self.executeCommand(command, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
            resourceCheck(.after, i, self)
        }
    }
    
    func executeCommand(_ command: FrameGraphCommand, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        switch command {
        case .insertDebugSignpost(let cString):
            self.insertDebugSignpost(String(cString: cString))
            
        case .setLabel(let label):
            self.label = String(cString: label)
            
        case .pushDebugGroup(let groupName):
            self.pushDebugGroup(String(cString: groupName))
            
        case .popDebugGroup:
            self.popDebugGroup()
            
        case .copyBufferToTexture(let args):
            let sourceBuffer = resourceRegistry[buffer: args.pointee.sourceBuffer]!
            self.copy(from: sourceBuffer.buffer, sourceOffset: Int(args.pointee.sourceOffset) + sourceBuffer.offset, sourceBytesPerRow: Int(args.pointee.sourceBytesPerRow), sourceBytesPerImage: Int(args.pointee.sourceBytesPerImage), sourceSize: MTLSize(args.pointee.sourceSize), to: resourceRegistry[texture: args.pointee.destinationTexture]!, destinationSlice: Int(args.pointee.destinationSlice), destinationLevel: Int(args.pointee.destinationLevel), destinationOrigin: MTLOrigin(args.pointee.destinationOrigin), options: MTLBlitOption(args.pointee.options))
            
        case .copyBufferToBuffer(let args):
            let sourceBuffer = resourceRegistry[buffer: args.pointee.sourceBuffer]!
            let destinationBuffer = resourceRegistry[buffer: args.pointee.destinationBuffer]!
            self.copy(from: sourceBuffer.buffer, sourceOffset: Int(args.pointee.sourceOffset) + sourceBuffer.offset, to: destinationBuffer.buffer, destinationOffset: Int(args.pointee.destinationOffset) + destinationBuffer.offset, size: Int(args.pointee.size))
            
        case .copyTextureToBuffer(let args):
            let destinationBuffer = resourceRegistry[buffer: args.pointee.destinationBuffer]!
            self.copy(from: resourceRegistry[texture: args.pointee.sourceTexture]!, sourceSlice: Int(args.pointee.sourceSlice), sourceLevel: Int(args.pointee.sourceLevel), sourceOrigin: MTLOrigin(args.pointee.sourceOrigin), sourceSize: MTLSize(args.pointee.sourceSize), to: destinationBuffer.buffer, destinationOffset: Int(args.pointee.destinationOffset) + destinationBuffer.offset, destinationBytesPerRow: Int(args.pointee.destinationBytesPerRow), destinationBytesPerImage: Int(args.pointee.destinationBytesPerImage), options: MTLBlitOption(args.pointee.options))
            
        case .copyTextureToTexture(let args):
            self.copy(from: resourceRegistry[texture: args.pointee.sourceTexture]!, sourceSlice: Int(args.pointee.sourceSlice), sourceLevel: Int(args.pointee.sourceLevel), sourceOrigin: MTLOrigin(args.pointee.sourceOrigin), sourceSize: MTLSize(args.pointee.sourceSize), to: resourceRegistry[texture: args.pointee.destinationTexture]!, destinationSlice: Int(args.pointee.destinationSlice), destinationLevel: Int(args.pointee.destinationLevel), destinationOrigin: MTLOrigin(args.pointee.destinationOrigin))
            
        case .fillBuffer(let args):
            let buffer = resourceRegistry[buffer: args.pointee.buffer]!
            let range = (args.pointee.range.lowerBound + buffer.offset)..<(args.pointee.range.upperBound + buffer.offset)
            self.fill(buffer: buffer.buffer, range: range, value: args.pointee.value)
            
        case .generateMipmaps(let texture):
            self.generateMipmaps(for: resourceRegistry[texture: texture]!)
            
        case .synchroniseTexture(let textureHandle):
            self.synchronize(resource: resourceRegistry[texture: textureHandle]!)
            
        case .synchroniseTextureSlice(let args):
            self.synchronize(texture: resourceRegistry[texture: args.pointee.texture]!, slice: Int(args.pointee.slice), level: Int(args.pointee.level))
            
        case .synchroniseBuffer(let buffer):
            let buffer = resourceRegistry[buffer: buffer]!
            self.synchronize(resource: buffer.buffer)
            
        default:
            fatalError()
        }
    }
}
