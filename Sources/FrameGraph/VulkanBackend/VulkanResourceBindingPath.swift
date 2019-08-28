//
//  ResourceBindingPath.swift
//  SwiftFrameGraphPackageDescription
//
//  Created by Thomas Roughton on 2/03/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras

@_fixed_layout
public struct VulkanResourceBindingPath : Hashable {
    fileprivate var _set : UInt16 = 0
    fileprivate var _binding : UInt16 = 0 
    var arrayIndex : UInt32 = 0
    
    public init(_ path: ResourceBindingPath) {
        self._set = UInt16(path.value >> 48)
        self._binding = UInt16((path.value >> 32) & 0xFFFF)
        self.arrayIndex = UInt32(path.value & 0xFFFFFFFF)
    }
    
    public init(set: UInt32, binding: UInt32, arrayIndex: UInt32) {
        self._set = UInt16(set) 
        self._binding = UInt16(binding)
        self.arrayIndex = arrayIndex
    }

     public init(argumentBuffer: UInt32) {
        self._set = UInt16(argumentBuffer) 
        self._binding = UInt16.max
        self.arrayIndex = 0
    }
    
    var set : UInt32 {
        get {
            return UInt32(self._set)
        }
        set {
            self._set = UInt16(newValue)
        }
    }

    var binding : UInt32 {
        get {
            return UInt32(self._binding)
        }
        set {
            self._binding = UInt16(newValue)
        }
    }

    var value : UInt64 {
        return unsafeBitCast(self, to: UInt64.self)
    }

    public func hash(into hasher: inout Hasher) {
        self._set.hash(into: &hasher)
        self._binding.hash(into: &hasher)
        self.arrayIndex.hash(into: &hasher)
        
    }
    
    public var isPushConstant : Bool {
        return self.set == BindingIndexSetPushConstant
    }

    public var isArgumentBuffer : Bool {
        return self.binding == UInt16.max
    }
}

extension ResourceBindingPath {
    public init(_ path: VulkanResourceBindingPath) {
        self = ResourceBindingPath(value: (UInt64(path._set) << 48) | (UInt64(path._binding) << 32) | UInt64(path.arrayIndex))
    }
}

#endif // canImport(Vulkan)
