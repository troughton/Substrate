//
//  ResourceBindingPath.swift
//  SubstratePackageDescription
//
//  Created by Thomas Roughton on 2/03/18.
//

#if canImport(Metal)

@preconcurrency import Metal
import SubstrateUtilities

extension ResourceBindingPath {
    fileprivate static let vertexStageFlag : UInt64 = (1 << 63)
    fileprivate static let fragmentStageFlag : UInt64 = (1 << 62)
    
    fileprivate static let textureTypeFlag : UInt64 = (1 << 61)
    fileprivate static let bufferTypeFlag : UInt64 = (1 << 60)
    fileprivate static let samplerTypeFlag : UInt64 = (1 << 59)
    
    fileprivate static let argumentBufferNone = (1 << 5) - 1 // all bits in the argumentBufferIndexRange set.
    fileprivate static let argumentBufferIndexRange = 54..<59
    fileprivate static let argumentBufferIndexClearMask = UInt64.maskForClearingBits(in: argumentBufferIndexRange)
    fileprivate static let indexRange = 32..<54
    fileprivate static let indexClearMask = UInt64.maskForClearingBits(in: indexRange)
    fileprivate static let arrayIndexRange = 0..<32
    fileprivate static let arrayIndexClearMask = UInt64.maskForClearingBits(in: arrayIndexRange)

    public init(type: ResourceType, index: Int, argumentBufferIndex: Int? = nil, stages: RenderStages) {
        let argType : MTLArgumentType
        switch type {
        case .texture:
            argType = .texture
        case .sampler:
            argType = .sampler
        default:
            argType = .buffer
        }
        self.init(type: argType, index: index, argumentBufferIndex: argumentBufferIndex, stages: MTLRenderStages(stages))
    }
    
    @_disfavoredOverload
    public init(type: MTLDataType, index: Int, argumentBufferIndex: Int?, stages: MTLRenderStages) {
        let argType : MTLArgumentType
        switch type {
        case .texture:
            argType = .texture
        case .sampler:
            argType = .sampler
        default:
            argType = .buffer
        }
        self.init(type: argType, index: index, argumentBufferIndex: argumentBufferIndex, stages: stages)
    }
    
    @_disfavoredOverload
    public init(type: MTLArgumentType, index: Int, argumentBufferIndex: Int? = nil, stages: MTLRenderStages) {
        self = ResourceBindingPath(value: 0)
        
        self.value.setBits(in: ResourceBindingPath.indexRange, to: UInt64(index), clearMask: ResourceBindingPath.indexClearMask)
        
        self.stages = stages
        
        let argBufferBits = argumentBufferIndex ?? ResourceBindingPath.argumentBufferNone
        self.value.setBits(in: ResourceBindingPath.argumentBufferIndexRange, to: UInt64(truncatingIfNeeded: argBufferBits), clearMask: ResourceBindingPath.argumentBufferIndexClearMask)
        
        switch type {
        case .texture:
            self.value |= ResourceBindingPath.textureTypeFlag
        case .sampler:
            self.value |= ResourceBindingPath.samplerTypeFlag
        default:
            self.value |= ResourceBindingPath.bufferTypeFlag
        }
    }
    
    public var stageTypeAndArgBufferMask : UInt64 {
        return self.value & (ResourceBindingPath.indexClearMask & ResourceBindingPath.arrayIndexClearMask)
    }

    public var stages : MTLRenderStages {
        get {
            var stages : MTLRenderStages = MTLRenderStages(rawValue: 0)
            if self.value & ResourceBindingPath.vertexStageFlag != 0 {
                stages.formUnion(.vertex)
            }
            if self.value & ResourceBindingPath.fragmentStageFlag != 0 {
                stages.formUnion(.fragment)
            }
            return stages
        }
        set {
            self.value &= ~(ResourceBindingPath.vertexStageFlag | ResourceBindingPath.fragmentStageFlag)
            if newValue.contains(.vertex) {
                self.value |= ResourceBindingPath.vertexStageFlag
            }
            if newValue.contains(.fragment) {
                self.value |= ResourceBindingPath.fragmentStageFlag
            }
        }
    }
    
    public var argumentBufferIndex : Int? {
        get {
            let argBufferIndex = Int(truncatingIfNeeded: self.value.bits(in: ResourceBindingPath.argumentBufferIndexRange))
            return argBufferIndex == ResourceBindingPath.argumentBufferNone ? nil : argBufferIndex
        }
        set {
            if let newValue = newValue {
                self.value.setBits(in: ResourceBindingPath.argumentBufferIndexRange, to: UInt64(truncatingIfNeeded: newValue), clearMask: ResourceBindingPath.argumentBufferIndexClearMask)
            } else {
                self.value.setBits(in: ResourceBindingPath.argumentBufferIndexRange, to: UInt64(truncatingIfNeeded: ResourceBindingPath.argumentBufferNone), clearMask: ResourceBindingPath.argumentBufferIndexClearMask)
            }
        }
    }
    
    public var type : MTLArgumentType {
        if self.value & ResourceBindingPath.bufferTypeFlag != 0 {
            return .buffer
        }
        if self.value & ResourceBindingPath.textureTypeFlag != 0 {
            return .texture
        }
        if self.value & ResourceBindingPath.samplerTypeFlag != 0 {
            return .sampler
        }
        fatalError()
    }
    
    public var index : Int {
        get {
            return Int(truncatingIfNeeded: self.value.bits(in: ResourceBindingPath.indexRange))
        }
        set {
            self.value.setBits(in: ResourceBindingPath.indexRange, to: UInt64(truncatingIfNeeded: newValue), clearMask: ResourceBindingPath.indexClearMask)
        }
    }
    
    // NOTE: When argumentBufferIndex is not nil, this refers to the array index of the _argument buffer_, and not this element within it.
    public var arrayIndexMetal : Int {
        get {
            return Int(truncatingIfNeeded: self.value.bits(in: ResourceBindingPath.arrayIndexRange))
        }
        set {
            self.value.setBits(in: ResourceBindingPath.arrayIndexRange, to: UInt64(truncatingIfNeeded: newValue), clearMask: ResourceBindingPath.arrayIndexClearMask)
        }
    }
    
    @inlinable
    public var bindIndex : Int {
        return self.index &+ self.arrayIndexMetal
    }
}

extension ResourceBindingPath {
    @inlinable
    public init(resourceSetIndex: Int = 0, index: Int, type: MTLArgumentType) {
        self.init(type: type, index: index, argumentBufferIndex: resourceSetIndex + 1, stages: []) // Push constants go at index 0.
    }
}

#endif // canImport(Metal)
