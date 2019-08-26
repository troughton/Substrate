//
//  VertexDescriptor.swift
//  SwiftFrameGraph
//
//  Created by Thomas Roughton on 7/04/17.
//
//

import FrameGraphUtilities

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
    @inlinable
    public init() {
        
    }
    public var layouts = [VertexBufferLayoutDescriptor](repeating: VertexBufferLayoutDescriptor(), count: 8)
    public var attributes = [VertexAttributeDescriptor](repeating: VertexAttributeDescriptor(), count: 16)
    
    public static func ==(lhs: VertexDescriptor, rhs: VertexDescriptor) -> Bool {
        return lhs.layouts == rhs.layouts && lhs.attributes == rhs.attributes
    }
}
