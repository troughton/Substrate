//
//  MetalFrameCommandInfo.swift
//  
//
//  Created by Thomas Roughton on 28/03/20.
//

import Foundation
import Atomics

struct CommandEncoderInfo: Sendable {
    var type: RenderPassType
    
    var commandBufferIndex: Int
    var queueFamilyIndex: Int // corresponding to the Vulkan concept of queue families; this indicates whether e.g. the encoder is executed on the main render queue vs async compute etc.
    
    var passRange: Range<Int>
    
    var queueCommandWaitIndices: QueueCommandIndices
    
    var usesWindowTexture: Bool
    
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
    var name: String? = nil
#endif
}

struct FrameCommandInfo<RenderTarget: BackendRenderTargetDescriptor>: Sendable {
    let globalFrameIndex: UInt64
    let baseCommandBufferGlobalIndex: UInt64
    
    let passes: [RenderPassRecord]
    let passEncoderIndices: [Int]
    var commandEncoders: [CommandEncoderInfo]
    let commandEncoderRenderTargets: [RenderTarget?]
    
    // storedTextures contain all textures that are stored to (i.e. textures that aren't eligible to be memoryless on iOS).
    let storedTextures: [Texture]
    
    init(passes: [RenderPassRecord], initialCommandBufferGlobalIndex: UInt64) {
        self.globalFrameIndex = RenderGraph.globalSubmissionIndex.load(ordering: .relaxed)
        self.passes = passes
        self.baseCommandBufferGlobalIndex = initialCommandBufferGlobalIndex
        
        var storedTextures = [Texture]()
        let renderTargetsDescriptors = FrameCommandInfo.generateRenderTargetDescriptors(passes: passes, storedTextures: &storedTextures)
        self.storedTextures = storedTextures
        
        assert(passes.enumerated().allSatisfy({ $0 == $1.passIndex }))
        
        do {
            var commandEncoders = [CommandEncoderInfo]()
            var commandEncoderRenderTargets = [RenderTarget?]()
            var commandBufferIndex = 0
            
            let addEncoder = { (passRange: Range<Int>, usesWindowTexture: Bool) -> Void in
                
                let queueFamilyIndex = 0 // TODO: correctly compute this for Vulkan.
                
                if let previousEncoder = commandEncoders.last,
                   previousEncoder.usesWindowTexture != usesWindowTexture || previousEncoder.queueFamilyIndex != queueFamilyIndex {
                    commandBufferIndex += 1
                }
                
                var encoderInfo = CommandEncoderInfo(type: passes[passRange.first!].type,
                                                     commandBufferIndex: commandBufferIndex,
                                                     queueFamilyIndex: queueFamilyIndex,
                                                     passRange: passRange,
                                                     queueCommandWaitIndices: QueueCommandIndices(repeating: 0),
                                                     usesWindowTexture: usesWindowTexture)
                
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
                let name: String
                if passRange.count <= 4 {
                    name = passes[passRange].lazy.map { $0.name }.joined(separator: ", ")
                } else {
                    name = "[\(passes[passRange.first!].name)...\(passes[passRange.last!].name)] (\(passRange.count) passes)"
                }
                encoderInfo.name = name
#endif
                
                commandEncoders.append(encoderInfo)
                commandEncoderRenderTargets.append(renderTargetsDescriptors[passRange.lowerBound])
            }
            
            var encoderFirstPass = 0
            var encoderUsesWindowTexture = passes.first?.usesWindowTexture ?? false
            
            for (i, pass) in passes.enumerated().dropFirst() {
                let previousPass = passes[i - 1]
                assert(pass.passIndex != previousPass.passIndex)
                
                if (pass.type != .draw && !(pass.type == .blit && previousPass.type == .blit)) ||
                    renderTargetsDescriptors[previousPass.passIndex] !== renderTargetsDescriptors[pass.passIndex] {
                    // Save the current command encoder and start a new one
                    addEncoder(encoderFirstPass..<i, encoderUsesWindowTexture)
                    encoderFirstPass = i
                    encoderUsesWindowTexture = false
                }
                
                encoderUsesWindowTexture = encoderUsesWindowTexture || pass.usesWindowTexture
            }
            if !passes.isEmpty {
                addEncoder(encoderFirstPass..<passes.count, encoderUsesWindowTexture)
            }
            
            self.commandEncoders = commandEncoders
            self.commandEncoderRenderTargets = commandEncoderRenderTargets
            
            var passEncoderIndices = [Int](repeating: 0, count: passes.count)
            var encoderIndex = 0
            for i in passEncoderIndices.indices {
                if !self.commandEncoders[encoderIndex].passRange.contains(i) {
                    encoderIndex += 1
                }
                passEncoderIndices[i] = encoderIndex
            }
            
            self.passEncoderIndices = passEncoderIndices
        }
    }
    
    public var commandBufferCount: Int {
        return self.commandEncoders.last.map { $0.commandBufferIndex + 1 } ?? 0
    }

    public func encoderIndex(for passIndex: Int) -> Int {
        return self.passEncoderIndices[passIndex]
    }
    
    public func encoderIndex(for pass: RenderPassRecord) -> Int {
        return self.encoderIndex(for: pass.passIndex)
    }
    
    public func encoder(for passIndex: Int) -> CommandEncoderInfo {
        return self.commandEncoders[self.encoderIndex(for: passIndex)]
    }
    
    public func encoder(for pass: RenderPassRecord) -> CommandEncoderInfo {
        return self.encoder(for: pass.passIndex)
    }
    
    public func globalCommandBufferIndex(frameIndex: Int) -> UInt64 {
        return self.baseCommandBufferGlobalIndex + UInt64(frameIndex)
    }
    
    // Generates a render target descriptor, if applicable, for each pass.
    // MetalRenderTargetDescriptor is a reference type, so we can check if two passes share a render target
    // (and therefore MTLRenderCommandEncoder)
    private static func generateRenderTargetDescriptors(passes: [RenderPassRecord], storedTextures: inout [Texture]) -> [RenderTarget?] {
        var descriptors = [RenderTarget?](repeating: nil, count: passes.count)
        
        var currentDescriptor : RenderTarget? = nil
        for (i, passRecord) in passes.enumerated() {
            if passRecord.type == .draw {
                if let descriptor = currentDescriptor {
                    currentDescriptor = descriptor.descriptorMergedWithPass(passRecord, allRenderPasses: passes, storedTextures: &storedTextures)
                } else {
                    currentDescriptor = RenderTarget(renderPass: passRecord)
                }
            } else {
                currentDescriptor?.finalise(allRenderPasses: passes, storedTextures: &storedTextures)
                currentDescriptor = nil
            }
            
            descriptors[i] = currentDescriptor
        }
        
        currentDescriptor?.finalise(allRenderPasses: passes, storedTextures: &storedTextures)
        
        return descriptors
    }
}
