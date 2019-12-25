//
//  ResourceBindingPath.swift
//  SwiftFrameGraphPackageDescription
//
//  Created by Thomas Roughton on 2/03/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras
import SwiftFrameGraph

extension ResourceBindingPath {
    public static let setIndexRange = 56..<64
    public static let bindingRange = 32..<56
    public static let arrayIndexRange = 0..<32
    
    public static let pushConstantSet = UInt32(UInt8.max)
    public static let argumentBufferBinding = UInt32((1 << ResourceBindingPath.bindingRange.count) - 1)

    @inlinable
    public init(set: UInt32, binding: UInt32, arrayIndex: UInt32) {
        self = ResourceBindingPath(value: 0)
        
        self.set = set
        self.binding = binding
        self.arrayIndex = arrayIndex
    }

    @inlinable
    public init(argumentBuffer: UInt32) {
        self.init(set: argumentBuffer, binding: ResourceBindingPath.argumentBufferBinding, arrayIndex: 0)
    }
    
    @inlinable
    public var set : UInt32 {
        get {
            return UInt32(truncatingIfNeeded: self.value.bits(in: ResourceBindingPath.setIndexRange))
        }
        set {
            self.value.setBits(in: ResourceBindingPath.setIndexRange, to: UInt64(newValue))
        }
    }

    @inlinable
    public var binding : UInt32 {
        get {
            return UInt32(truncatingIfNeeded: self.value.bits(in: ResourceBindingPath.bindingRange))
        }
        set {
            self.value.setBits(in: ResourceBindingPath.bindingRange, to: UInt64(newValue))
        }
    }
    
    @inlinable
    public var isPushConstant : Bool {
        return self.set == ResourceBindingPath.pushConstantSet
    }

    @inlinable
    public var isArgumentBuffer : Bool {
        return self.binding == ResourceBindingPath.argumentBufferBinding
    }
}

#endif // canImport(Vulkan)
