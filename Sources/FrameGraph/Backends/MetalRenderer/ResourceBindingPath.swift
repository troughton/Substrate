//
//  ResourceBindingPath.swift
//  InterdimensionalLlamaPackageDescription
//
//  Created by Thomas Roughton on 2/03/18.
//

import RenderAPI
import Metal
import Utilities

public struct MetalResourceBindingPath {
    private static let vertexStageFlag : UInt64 = (1 << 63)
    private static let fragmentStageFlag : UInt64 = (1 << 62)
    
    private static let textureTypeFlag : UInt64 = (1 << 61)
    private static let bufferTypeFlag : UInt64 = (1 << 60)
    private static let samplerTypeFlag : UInt64 = (1 << 59)
    
    private static let argumentBufferNone = (1 << 5) - 1 // all bits in the argumentBufferIndexRange set.
    private static let argumentBufferIndexRange = 54..<59
    private static let indexRange = 32..<54
    private static let arrayIndexRange = 0..<32
    
    var value : UInt64 = 0
    
    public init(_ path: ResourceBindingPath) {
        self.value = path.value
    }
    
    public init(stages: MTLRenderStages, type: MTLDataType, argumentBufferIndex: Int?, index: Int) {
        let argType : MTLArgumentType
        switch type {
        case .texture:
            argType = .texture
        case .sampler:
            argType = .sampler
        default:
            argType = .buffer
        }
        self.init(stages: stages, type: argType, argumentBufferIndex: argumentBufferIndex, index: index)
    }
    
    public init(stages: MTLRenderStages, type: MTLArgumentType, argumentBufferIndex: Int?, index: Int) {
        self.value = 0
        
        self.value.setBits(in: MetalResourceBindingPath.indexRange, to: UInt64(index))
        
        self.stages = stages
        
        let argBufferBits = argumentBufferIndex ?? MetalResourceBindingPath.argumentBufferNone
        self.value.setBits(in: MetalResourceBindingPath.argumentBufferIndexRange, to: UInt64(argBufferBits))
        
        switch type {
        case .buffer:
            self.value |= MetalResourceBindingPath.bufferTypeFlag
        case .texture:
            self.value |= MetalResourceBindingPath.textureTypeFlag
        case .sampler:
            self.value |= MetalResourceBindingPath.samplerTypeFlag
        default:
            fatalError()
        }
    }
    
    public var stages : MTLRenderStages {
        get {
            var stages : MTLRenderStages = MTLRenderStages(rawValue: 0)
            if self.value & MetalResourceBindingPath.vertexStageFlag != 0 {
                stages.formUnion(.vertex)
            }
            if self.value & MetalResourceBindingPath.fragmentStageFlag != 0 {
                stages.formUnion(.fragment)
            }
            return stages
        }
        set {
            self.value &= ~(MetalResourceBindingPath.vertexStageFlag | MetalResourceBindingPath.fragmentStageFlag)
            if newValue.contains(.vertex) {
                self.value |= MetalResourceBindingPath.vertexStageFlag
            }
            if newValue.contains(.fragment) {
                self.value |= MetalResourceBindingPath.fragmentStageFlag
            }
        }
    }
    
    public var argumentBufferIndex : Int? {
        let argBufferIndex = Int(self.value.bits(in: MetalResourceBindingPath.argumentBufferIndexRange))
        return argBufferIndex == MetalResourceBindingPath.argumentBufferNone ? nil : argBufferIndex
    }
    
    public var index : Int {
        get {
            return Int(self.value.bits(in: MetalResourceBindingPath.indexRange))
        }
        set {
            self.value.setBits(in: MetalResourceBindingPath.indexRange, to: UInt64(newValue))
        }
    }
    
    public var arrayIndex : Int {
        get {
            return Int(self.value.bits(in: MetalResourceBindingPath.arrayIndexRange))
        }
        set {
            self.value.setBits(in: MetalResourceBindingPath.arrayIndexRange, to: UInt64(newValue))
        }
    }
    
    public var bindIndex : Int {
        return self.index + self.arrayIndex
    }
}

extension ResourceBindingPath {
    public init(_ path: MetalResourceBindingPath) {
        self = ResourceBindingPath(value: path.value)
    }
}
