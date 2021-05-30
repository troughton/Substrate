//
//  IntersectionFunctionTable.swift
//  
//
//  Created by Thomas Roughton on 29/05/21.
//

import Foundation

public struct IntersectionFunctionInputAttributes : OptionSet {
    public let rawValue: UInt
    
    @inlinable
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
    
    @inlinable
    public static var instancing: IntersectionFunctionInputAttributes { IntersectionFunctionInputAttributes(rawValue: 1 << 0) }
    
    @inlinable
    public static var triangleData: IntersectionFunctionInputAttributes { IntersectionFunctionInputAttributes(rawValue: 1 << 1) }
    
    @inlinable
    public static var worldSpaceData: IntersectionFunctionInputAttributes { IntersectionFunctionInputAttributes(rawValue: 1 << 2) }
}

public struct IntersectionFunctionTableDescriptor: Hashable, Equatable {
    public enum FunctionType {
        case defaultOpaqueFunction(inputAttributes: IntersectionFunctionInputAttributes)
        case function(FunctionDescriptor)
    }
    
    public enum BufferType {
        case buffer(Buffer, offset: Int)
        case functionTable([FunctionDescriptor?])
    }
    
    public var functions: [FunctionType?]
    public var buffers: [BufferType?]
}
