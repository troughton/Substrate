//
//  ResourceBindingPath.swift
//  SwiftFrameGraphPackageDescription
//
//  Created by Thomas Roughton on 2/03/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras

extension ResourceBindingPath {
    fileprivate static let setIndexRange = 56..<64
    fileprivate static let bindingRange = 32..<56
    fileprivate static let arrayIndexRange = 0..<32
    
    fileprivate static let pushConstantSet = UInt32(UInt8.max)
    fileprivate static let argumentBufferBinding = UInt32((1 << ResourceBindingPath.bindingRange.count) - 1)
    
    fileprivate static let pushConstantPath = ResourceBindingPath(set: pushConstantSet, binding: 0, arrayIndex: 0)

    public init(set: UInt32, binding: UInt32, arrayIndex: UInt32) {
        self = ResourceBindingPath(value: 0)
        
        self.set = set
        self.binding = binding
        self.arrayIndexVulkan = arrayIndex
    }

    public init(argumentBuffer: UInt32) {
        self.init(set: argumentBuffer, binding: ResourceBindingPath.argumentBufferBinding, arrayIndex: 0)
    }
    
    public var set : UInt32 {
        get {
            return UInt32(truncatingIfNeeded: self.value.bits(in: ResourceBindingPath.setIndexRange))
        }
        set {
            self.value.setBits(in: ResourceBindingPath.setIndexRange, to: UInt64(newValue))
        }
    }

    public var binding : UInt32 {
        get {
            return UInt32(truncatingIfNeeded: self.value.bits(in: ResourceBindingPath.bindingRange))
        }
        set {
            self.value.setBits(in: ResourceBindingPath.bindingRange, to: UInt64(newValue))
        }
    }
    
    public var arrayIndexVulkan : UInt32 {
        get {
            return UInt32(truncatingIfNeeded: self.value.bits(in: ResourceBindingPath.arrayIndexRange))
        }
        set {
            self.value.setBits(in: ResourceBindingPath.arrayIndexRange, to: UInt64(newValue))
        }
    }
    
    public var isPushConstant : Bool {
        return self.set == ResourceBindingPath.pushConstantSet
    }

    public var isArgumentBuffer : Bool {
        return self.binding == ResourceBindingPath.argumentBufferBinding
    }
}

#endif // canImport(Vulkan)
