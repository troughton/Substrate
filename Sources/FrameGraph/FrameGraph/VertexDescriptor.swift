//
//  VertexDescriptor.swift
//  SwiftFrameGraph
//
//  Created by Thomas Roughton on 7/04/17.
//
//

import Utilities

public struct VertexBufferLayoutDescriptor : Hashable {
    
    public var stride: Int = 0
    
    public var stepFunction: VertexStepFunction = .constant
    
    public var stepRate: Int = 1
}


public struct VertexAttributeDescriptor : Hashable {
    
    public var format: VertexFormat = .invalid
    
    public var offset: Int = 0
    
    public var bufferIndex: Int = 0
}

public struct VertexDescriptor : Hashable {
    
    public init() {
        self._hashValue =  CachedValue(constructor: self.calculateHashValue)
    }
    
    private var _hashValue : CachedValue<Int>! = nil
    
    public var layouts = [VertexBufferLayoutDescriptor](repeating: VertexBufferLayoutDescriptor(), count: 8) {
        didSet {
            self._hashValue.reset()
        }
    }
    
    public var attributes = [VertexAttributeDescriptor](repeating: VertexAttributeDescriptor(), count: 16) {
        didSet {
            self._hashValue.reset()
        }
    }
    
    private func calculateHashValue() -> Int {
        return self.layouts.hashValue &+ self.attributes.hashValue &* 17
    }
    
    public var hashValue: Int {
        return _hashValue.value
    }
    
    public static func ==(lhs: VertexDescriptor, rhs: VertexDescriptor) -> Bool {
        return lhs.layouts == rhs.layouts && lhs.attributes == rhs.attributes
    }
}
