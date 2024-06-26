//
//  VertexDescriptor.swift
//  Substrate
//
//  Created by Thomas Roughton on 7/04/17.
//
//

import SubstrateUtilities

public struct VertexBufferLayoutDescriptor : Hashable, Sendable {
    @usableFromInline var _stride: UInt16
    public var stepFunction: VertexStepFunction
    @usableFromInline var _stepRate: UInt32
    
    @inlinable
    public var stride: Int {
        get {
            return Int(self._stride)
        } set {
            self._stride = UInt16(newValue)
        }
    }
    
    @inlinable
    public var stepRate: Int {
        get {
            return Int(self._stepRate)
        }
        set {
            self._stepRate = UInt32(self._stepRate)
        }
    }
    
    @inlinable
    public init(stride: Int = 0, stepFunction: VertexStepFunction = .constant, stepRate: Int = 1) {
        self._stride = UInt16(stride)
        self.stepFunction = stepFunction
        self._stepRate = UInt32(stepRate)
    }
}


public struct VertexAttributeDescriptor : Hashable, Sendable {
    public var format: VertexFormat
    @usableFromInline var _offset: UInt16
    @usableFromInline var _bufferIndex: UInt16
    
    @inlinable
    public var offset: Int {
        get {
            return Int(self._offset)
        } set {
            self._offset = UInt16(newValue)
        }
    }
    
    @inlinable
    public var bufferIndex: Int {
        get {
            return Int(self._bufferIndex)
        }
        set {
            self._bufferIndex = UInt16(newValue)
        }
    }
    
    @inlinable
    public init(format: VertexFormat, offset: Int, bufferIndex: Int) {
        self.format = format
        self._offset = UInt16(offset)
        self._bufferIndex = UInt16(bufferIndex)
    }
}

public struct VertexDescriptor : Hashable, Sendable {
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
