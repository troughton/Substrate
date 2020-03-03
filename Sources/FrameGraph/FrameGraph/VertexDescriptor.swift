//
//  VertexDescriptor.swift
//  SwiftFrameGraph
//
//  Created by Thomas Roughton on 7/04/17.
//
//

import FrameGraphUtilities

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
    @inlinable
    public init() {
        
    }
    public var layouts = [VertexBufferLayoutDescriptor](repeating: VertexBufferLayoutDescriptor(), count: 8)
    public var attributes = [VertexAttributeDescriptor](repeating: VertexAttributeDescriptor(format: .invalid, offset: 0, bufferIndex: 0), count: 16)
    
    public static func ==(lhs: VertexDescriptor, rhs: VertexDescriptor) -> Bool {
        return lhs.layouts == rhs.layouts && lhs.attributes == rhs.attributes
    }
}
