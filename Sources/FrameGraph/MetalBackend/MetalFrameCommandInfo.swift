//
//  MetalFrameCommandInfo.swift
//  
//
//  Created by Thomas Roughton on 28/03/20.
//

import Foundation


struct MetalFrameCommandInfo {
    
    struct CommandEncoderInfo {
        var name: String
        var type: RenderPassType
        
        var renderTargetDescriptor: MetalRenderTargetDescriptor?
        var commandBufferIndex: Int
        
        var passRange: Range<Int>
        var commandRange: Range<Int>
        
        var queueCommandWaitIndices: QueueCommandIndices // NOT YET INITIALISED
        
        var usesWindowTexture: Bool
    }
    
    let baseCommandBufferSignalValue: UInt64
    
    var commandEncoders: [CommandEncoderInfo]
    
    // storedTextures contain all textures that are stored to (i.e. textures that aren't eligible to be memoryless on iOS).
    var storedTextures: [Texture]
    
    init(passes: [RenderPassRecord], resourceUsages: ResourceUsages, initialCommandBufferSignalValue: UInt64) {
        self.baseCommandBufferSignalValue = initialCommandBufferSignalValue
        
        var storedTextures = [Texture]()
        let renderTargetDescriptors = MetalFrameCommandInfo.generateRenderTargetDescriptors(passes: passes, resourceUsages: resourceUsages, storedTextures: &storedTextures)
        self.storedTextures = storedTextures
        
        assert(passes.enumerated().allSatisfy({ $0 == $1.passIndex }))
        
        do {
            var commandEncoders = [CommandEncoderInfo]()
            var commandBufferIndex = 0
            
            let addEncoder = { (passRange: Range<Int>, usesWindowTexture: Bool) -> Void in
                let name: String
                if passRange.count <= 3 {
                    name = passes[passRange].lazy.map { $0.pass.name }.joined(separator: ", ")
                } else {
                    name = "[\(passes[passRange.first!].pass.name)...\(passes[passRange.last!].pass.name)] (\(passRange.count) passes)"
                }
                
                let type = passes[passRange.first!].pass.passType
                
                if let previousEncoder = commandEncoders.last,
                previousEncoder.usesWindowTexture != usesWindowTexture || previousEncoder.type != type {
                    commandBufferIndex += 1
                }
                
                commandEncoders.append(CommandEncoderInfo(name: name,
                                                          type: passes[passRange.first!].pass.passType,
                                                          renderTargetDescriptor: renderTargetDescriptors[passRange.lowerBound],
                                                          commandBufferIndex: commandBufferIndex,
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
                
                if pass.pass.passType != .draw || renderTargetDescriptors[previousPass.passIndex] !== renderTargetDescriptors[pass.passIndex] {
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
        }
    }
    
    public var commandBufferCount: Int {
        return self.commandEncoders.last.map { $0.commandBufferIndex + 1 } ?? 0
    }

    public func encoderIndex(for passIndex: Int) -> Int {
        for (i, encoder) in self.commandEncoders.enumerated() {
            if encoder.passRange.contains(passIndex) {
                return i
            }
        }
        fatalError()
    }
    
    public func encoderIndex(for pass: RenderPassRecord) -> Int {
        return self.encoderIndex(for: pass.passIndex)
    }
    
    public func encoder(for passIndex: Int) -> CommandEncoderInfo {
        for encoder in self.commandEncoders {
            if encoder.passRange.contains(passIndex) {
                return encoder
            }
        }
        fatalError()
    }
    
    public func encoder(for pass: RenderPassRecord) -> CommandEncoderInfo {
        return self.encoder(for: pass.passIndex)
    }
    
    public func signalValue(commandBufferIndex: Int) -> UInt64 {
        return self.baseCommandBufferSignalValue + UInt64(commandBufferIndex)
    }
    
    // Generates a render target descriptor, if applicable, for each pass.
    // MetalRenderTargetDescriptor is a reference type, so we can check if two passes share a render target
    // (and therefore MTLRenderCommandEncoder)
    private static func generateRenderTargetDescriptors(passes: [RenderPassRecord], resourceUsages: ResourceUsages, storedTextures: inout [Texture]) -> [MetalRenderTargetDescriptor?] {
        var descriptors = [MetalRenderTargetDescriptor?](repeating: nil, count: passes.count)
        
        var currentDescriptor : MetalRenderTargetDescriptor? = nil
        for (i, passRecord) in passes.enumerated() {
            if let renderPass = passRecord.pass as? DrawRenderPass {
                if let descriptor = currentDescriptor {
                    currentDescriptor = descriptor.descriptorMergedWithPass(renderPass, resourceUsages: resourceUsages, storedTextures: &storedTextures)
                } else {
                    currentDescriptor = MetalRenderTargetDescriptor(renderPass: renderPass)
                }
            } else {
                currentDescriptor?.finalise(resourceUsages: resourceUsages, storedTextures: &storedTextures)
                currentDescriptor = nil
            }
            
            descriptors[i] = currentDescriptor
        }
        
        currentDescriptor?.finalise(resourceUsages: resourceUsages, storedTextures: &storedTextures)
        
        return descriptors
    }
}
