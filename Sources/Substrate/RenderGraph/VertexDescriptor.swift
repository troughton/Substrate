//
//  VertexDescriptor.swift
//  Substrate
//
//  Created by Thomas Roughton on 7/04/17.
//
//

import SubstrateUtilities

public struct VertexBufferLayoutDescriptor : Hashable {
    public var stride: Int
    public var stepFunction: VertexStepFunction
    public var stepRate: Int
    
    @inlinable
    public init(stride: Int = 0, stepFunction: VertexStepFunction = .constant, stepRate: Int = 1) {
        self.stride = stride
        self.stepFunction = stepFunction
        self.stepRate = stepRate
    }
}


public struct VertexAttributeDescriptor : Hashable {
    public var format: VertexFormat
    public var offset: Int
    public var bufferIndex: Int
    
    @inlinable
    public init(format: VertexFormat, offset: Int, bufferIndex: Int) {
        self.format = format
        self.offset = offset
        self.bufferIndex = bufferIndex
    }
}

public struct VertexDescriptor : Hashable {
    public var layouts = Array8<VertexBufferLayoutDescriptor>(repeating: VertexBufferLayoutDescriptor())
    public var attributes = Array16<VertexAttributeDescriptor>(repeating: VertexAttributeDescriptor(format: .invalid, offset: 0, bufferIndex: 0))
    
    @inlinable
    public init() {
        
    }
    
    @inlinable
    public func hash(into hasher: inout Hasher) {
        var usedBuffers = Array8<Bool>(repeating: false)
        
        for attribute in self.attributes {
            if attribute.format != .invalid {
                hasher.combine(attribute)
                usedBuffers[attribute.bufferIndex] = true
            } else {
                hasher.combine(attribute.format)
            }
        }
        
        for i in self.layouts.indices where usedBuffers[i] {
            hasher.combine(self.layouts[i])
        }
    }
    
    @inlinable
    public static func ==(lhs: VertexDescriptor, rhs: VertexDescriptor) -> Bool {
        var usedBuffers = Array8<Bool>(repeating: false)
        
        for i in lhs.attributes.indices {
            let a = lhs.attributes[i]
            let b = lhs.attributes[i]
            if a != b && (a.format != .invalid || b.format != .invalid) {
                return false
            }
            usedBuffers[a.bufferIndex] = true
        }
        
        for i in lhs.layouts.indices where usedBuffers[i] {
            if lhs.layouts[i] != rhs.layouts[i] {
                return false
            }
        }
        return true
    }
}
