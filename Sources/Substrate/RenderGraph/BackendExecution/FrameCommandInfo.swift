//
//  MetalFrameCommandInfo.swift
//  
//
//  Created by Thomas Roughton on 28/03/20.
//

import Foundation

struct CommandEncoderInfo<RenderTargetDescriptor: BackendRenderTargetDescriptor> {
    var name: String
    var type: RenderPassType
    
    var renderTargetDescriptor: RenderTargetDescriptor?
    var commandBufferIndex: Int
    var queueFamilyIndex: Int // corresponding to the Vulkan concept of queue families; this indicates whether e.g. the encoder is executed on the main render queue vs async compute etc.
    
    var passRange: Range<Int>
    var commandRange: Range<Int>
    
    var queueCommandWaitIndices: QueueCommandIndices
    
    var usesWindowTexture: Bool
}

struct FrameCommandInfo<Backend: SpecificRenderBackend> {
    let globalFrameIndex: UInt64
    let baseCommandBufferSignalValue: UInt64
    
    let passes: [RenderPassRecord]
    let passEncoderIndices: [Int]
    var commandEncoders: [CommandEncoderInfo<Backend.RenderTargetDescriptor>]
    
    // storedTextures contain all textures that are stored to (i.e. textures that aren't eligible to be memoryless on iOS).
    var storedTextures: [Texture]
    
    init(passes: [RenderPassRecord], initialCommandBufferSignalValue: UInt64) {
        self.globalFrameIndex = RenderGraph.globalSubmissionIndex
        self.passes = passes
        self.baseCommandBufferSignalValue = initialCommandBufferSignalValue
        
        var storedTextures = [Texture]()
        let renderTargetDescriptors = FrameCommandInfo.generateRenderTargetDescriptors(passes: passes, storedTextures: &storedTextures)
        self.storedTextures = storedTextures
        
        assert(passes.enumerated().allSatisfy({ $0 == $1.passIndex }))
        
        do {
            var commandEncoders = [CommandEncoderInfo<Backend.RenderTargetDescriptor>]()
            var commandBufferIndex = 0
            
            let addEncoder = { (passRange: Range<Int>, usesWindowTexture: Bool) -> Void in
                let name: String
                if passRange.count <= 3 {
                    name = passes[passRange].lazy.map { $0.name }.joined(separator: ", ")
                } else {
                    name = "[\(passes[passRange.first!].name)...\(passes[passRange.last!].name)] (\(passRange.count) passes)"
                }
                
                let queueFamilyIndex = 0 // TODO: correctly compute this for Vulkan.
                
                if let previousEncoder = commandEncoders.last,
                   previousEncoder.usesWindowTexture != usesWindowTexture || previousEncoder.queueFamilyIndex != queueFamilyIndex {
                    commandBufferIndex += 1
                }
                
                commandEncoders.append(CommandEncoderInfo(name: name,
                                                          type: passes[passRange.first!].type,
                                                          renderTargetDescriptor: renderTargetDescriptors[passRange.lowerBound],
                                                          commandBufferIndex: commandBufferIndex,
                                                          queueFamilyIndex: queueFamilyIndex,
                                                          passRange: passRange,
                                                          commandRange: passes[passRange.first!].commandRange!.lowerBound..<passes[passRange.last!].commandRange!.upperBound,
                                                          queueCommandWaitIndices: QueueCommandIndices(repeating: 0),
                                                          usesWindowTexture: usesWindowTexture))
            }
            
            var encoderFirstPass = 0
            var encoderUsesWindowTexture = passes.first?.usesWindowTexture ?? false
            
            for (i, pass) in passes.enumerated().dropFirst() {
                let previousPass = passes[i - 1]
                assert(pass.passIndex != previousPass.passIndex)
                
                if (pass.type != .draw && !(pass.type == .blit && previousPass.type == .blit)) ||
                    renderTargetDescriptors[previousPass.passIndex] !== renderTargetDescriptors[pass.passIndex] {
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
    
    public func encoder(for passIndex: Int) -> CommandEncoderInfo<Backend.RenderTargetDescriptor> {
        return self.commandEncoders[self.encoderIndex(for: passIndex)]
    }
    
    public func encoder(for pass: RenderPassRecord) -> CommandEncoderInfo<Backend.RenderTargetDescriptor> {
        return self.encoder(for: pass.passIndex)
    }
    
    public func signalValue(commandBufferIndex: Int) -> UInt64 {
        return self.baseCommandBufferSignalValue + UInt64(commandBufferIndex)
    }
    
    // Generates a render target descriptor, if applicable, for each pass.
    // MetalRenderTargetDescriptor is a reference type, so we can check if two passes share a render target
    // (and therefore MTLRenderCommandEncoder)
    private static func generateRenderTargetDescriptors(passes: [RenderPassRecord], storedTextures: inout [Texture]) -> [Backend.RenderTargetDescriptor?] {
        var descriptors = [Backend.RenderTargetDescriptor?](repeating: nil, count: passes.count)
        
        var currentDescriptor : Backend.RenderTargetDescriptor? = nil
        for (i, passRecord) in passes.enumerated() {
            if passRecord.type == .draw {
                if let descriptor = currentDescriptor {
                    currentDescriptor = descriptor.descriptorMergedWithPass(passRecord, storedTextures: &storedTextures)
                } else {
                    currentDescriptor = Backend.RenderTargetDescriptor(renderPass: passRecord)
                }
            } else {
                currentDescriptor?.finalise(storedTextures: &storedTextures)
                currentDescriptor = nil
            }
            
            descriptors[i] = currentDescriptor
        }
        
        currentDescriptor?.finalise(storedTextures: &storedTextures)
        
        return descriptors
    }
}
