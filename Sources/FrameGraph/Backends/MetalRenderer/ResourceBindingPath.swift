//
//  ResourceBindingPath.swift
//  SwiftFrameGraphPackageDescription
//
//  Created by Thomas Roughton on 2/03/18.
//

import SwiftFrameGraph
import Metal
import Utilities

@_fixed_layout
public struct MetalResourceBindingPath : Hashable {
    public static let vertexStageFlag : UInt64 = (1 << 63)
    public static let fragmentStageFlag : UInt64 = (1 << 62)
    
    public static let textureTypeFlag : UInt64 = (1 << 61)
    public static let bufferTypeFlag : UInt64 = (1 << 60)
    public static let samplerTypeFlag : UInt64 = (1 << 59)
    
    public static let argumentBufferNone = (1 << 5) - 1 // all bits in the argumentBufferIndexRange set.
    public static let argumentBufferIndexRange = 54..<59
    public static let argumentBufferIndexClearMask = UInt64.maskForClearingBits(in: argumentBufferIndexRange)
    public static let indexRange = 32..<54
    public static let indexClearMask = UInt64.maskForClearingBits(in: indexRange)
    public static let arrayIndexRange = 0..<32
    public static let arrayIndexClearMask = UInt64.maskForClearingBits(in: arrayIndexRange)
    
    public var value : UInt64 = 0
    
    @inlinable
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
        
        self.value.setBits(in: MetalResourceBindingPath.indexRange, to: UInt64(index), clearMask: MetalResourceBindingPath.indexClearMask)
        
        self.stages = stages
        
        let argBufferBits = argumentBufferIndex ?? MetalResourceBindingPath.argumentBufferNone
        self.value.setBits(in: MetalResourceBindingPath.argumentBufferIndexRange, to: UInt64(truncatingIfNeeded: argBufferBits), clearMask: MetalResourceBindingPath.argumentBufferIndexClearMask)
        
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
        get {
            let argBufferIndex = Int(truncatingIfNeeded: self.value.bits(in: MetalResourceBindingPath.argumentBufferIndexRange))
            return argBufferIndex == MetalResourceBindingPath.argumentBufferNone ? nil : argBufferIndex
        }
        set {
            if let newValue = newValue {
                self.value.setBits(in: MetalResourceBindingPath.argumentBufferIndexRange, to: UInt64(truncatingIfNeeded: newValue), clearMask: MetalResourceBindingPath.argumentBufferIndexClearMask)
            } else {
                self.value.setBits(in: MetalResourceBindingPath.argumentBufferIndexRange, to: UInt64(truncatingIfNeeded: MetalResourceBindingPath.argumentBufferNone), clearMask: MetalResourceBindingPath.argumentBufferIndexClearMask)
            }
        }
    }
    
    public var type : MTLArgumentType {
        if self.value & MetalResourceBindingPath.bufferTypeFlag != 0 {
            return .buffer
        }
        if self.value & MetalResourceBindingPath.textureTypeFlag != 0 {
            return .texture
        }
        if self.value & MetalResourceBindingPath.samplerTypeFlag != 0 {
            return .sampler
        }
        fatalError()
    }
    
    public var index : Int {
        get {
            return Int(truncatingIfNeeded: self.value.bits(in: MetalResourceBindingPath.indexRange))
        }
        set {
            self.value.setBits(in: MetalResourceBindingPath.indexRange, to: UInt64(truncatingIfNeeded: newValue), clearMask: MetalResourceBindingPath.indexClearMask)
        }
    }
    
    // NOTE: When argumentBufferIndex is not nil, this refers to the array index of the _argument buffer_, and not this element within it.
    public var arrayIndex : Int {
        get {
            return Int(truncatingIfNeeded: self.value.bits(in: MetalResourceBindingPath.arrayIndexRange))
        }
        set {
            self.value.setBits(in: MetalResourceBindingPath.arrayIndexRange, to: UInt64(truncatingIfNeeded: newValue), clearMask: MetalResourceBindingPath.arrayIndexClearMask)
        }
    }
    
    public var bindIndex : Int {
        return self.index &+ self.arrayIndex
    }
    
    @inlinable
    public static func ==(lhs: MetalResourceBindingPath, rhs: MetalResourceBindingPath) -> Bool {
        return lhs.value == rhs.value
    }
}

extension MetalResourceBindingPath : CustomHashable {
    public var customHashValue : Int {
        return Int(truncatingIfNeeded: self.value &* 39)
    }
}

extension ResourceBindingPath {
    public init(_ path: MetalResourceBindingPath) {
        self = ResourceBindingPath(value: path.value)
    }
}
