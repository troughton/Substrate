//
//  RenderBackend.swift
//  Llama 402
//
//  Created by Thomas Roughton on 10/03/17.
//  Copyright © 2017 Thomas Roughton. All rights reserved.
//

import Foundation

public protocol RenderBackendProtocol {
    
    func registerWindowTexture(texture: Texture, context: Any)
    
    func materialisePersistentTexture(_ texture: Texture)
    func materialisePersistentBuffer(_ buffer: Buffer)
    
    func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer
    func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>)
    
    func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int)
    
    func setReflectionRenderPipeline(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor)
    func setReflectionComputePipeline(descriptor: ComputePipelineDescriptor)
    
    func bindingPath(argumentBuffer: ArgumentBuffer, argumentName: String) -> ResourceBindingPath?
    func bindingPath(argumentName: String, arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath?
    func argumentReflection(at path: ResourceBindingPath) -> ArgumentReflection?
    func bindingIsActive(at path: ResourceBindingPath) -> Bool
    
    func dispose(texture: Texture)
    func dispose(buffer: Buffer)
    func dispose(argumentBuffer: ArgumentBuffer)
    
    var isDepth24Stencil8PixelFormatSupported : Bool { get }
    
    var renderDevice : Any { get }
    
    var maxInflightFrames : Int { get }
}

public struct RenderBackend {
    
    // This is going to go through a protocol lookup table every time for each method, which might be slow.
    // However, we can cache the functions (the result of the lookup entry) within the types that call them
    // if need be; e.g. let newTextureHandle = backend.newTextureHandle.
    public static var backend : RenderBackendProtocol! = nil

    @inlinable
    public static var maxInflightFrames : Int {
        return backend.maxInflightFrames
    }
    
    @inlinable
    public static func materialisePersistentTexture(_ texture: Texture) {
        return backend.materialisePersistentTexture(texture)
    }
    
    @inlinable
    public static func registerWindowTexture(texture: Texture, context: Any) {
        return backend.registerWindowTexture(texture: texture, context: context)
    }
    
    @inlinable
    public static func materialisePersistentBuffer(_ buffer: Buffer) {
        return backend.materialisePersistentBuffer(buffer)
    }
    
    @inlinable
    public static func setReflectionRenderPipeline(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) {
        return backend.setReflectionRenderPipeline(descriptor: descriptor, renderTarget: renderTarget)
    }
    
    @inlinable
    public static func setReflectionComputePipeline(descriptor: ComputePipelineDescriptor) {
        return backend.setReflectionComputePipeline(descriptor: descriptor)
    }

    @inlinable
    public static func bindingPath(argumentBuffer: ArgumentBuffer, argumentName: String) -> ResourceBindingPath? {
        return backend.bindingPath(argumentBuffer: argumentBuffer, argumentName: argumentName)
    }
    
    @inlinable
    public static func bindingPath(argumentName: String, arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath? {
        return backend.bindingPath(argumentName: argumentName, arrayIndex: arrayIndex, argumentBufferPath: argumentBufferPath)
    }
    
    @inlinable
    public static func argumentReflection(at path: ResourceBindingPath) -> ArgumentReflection? {
        return backend.argumentReflection(at: path)
    }
    
    @inlinable
    public static func bindingIsActive(at path: ResourceBindingPath) -> Bool {
        return backend.bindingIsActive(at: path)
    }
    
    @inlinable
    public static func dispose(texture: Texture) {
        return backend.dispose(texture: texture)
    }
    
    @inlinable
    public static func dispose(buffer: Buffer) {
        return backend.dispose(buffer: buffer)
    }
    
    @inlinable
    public static func dispose(argumentBuffer: ArgumentBuffer) {
        return backend.dispose(argumentBuffer: argumentBuffer)
    }
    
    @inlinable
    public static var isDepth24Stencil8PixelFormatSupported : Bool {
        return backend.isDepth24Stencil8PixelFormatSupported
    }
    
    @inlinable
    public static func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer {
        return backend.bufferContents(for: buffer, range: range)
    }
    
    @inlinable
    public static func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
        return backend.buffer(buffer, didModifyRange: range)
    }
    
    @inlinable
    public static func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        return backend.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }
    
    @inlinable
    public static var renderDevice : Any {
        return backend.renderDevice
    }
}

/*!
 @enum FunctionType
 @abstract An identifier for a top-level function.
 @discussion Each location in the API where a program is used requires a function written for that specific usage.
 
 @constant FunctionTypeVertex
 A vertex shader, usable for a RenderPipelineState.
 
 @constant FunctionTypeFragment
 A fragment shader, usable for a RenderPipelineState.
 
 @constant FunctionTypeKernel
 A compute kernel, usable to create a ComputePipelineState.
 */
public enum FunctionType : UInt {
    case vertex
    case fragment
    case kernel
}

public protocol VertexAttribute : class {
    
    var name: String? { get }
    
    var attributeIndex: Int { get }
    
    var attributeType: DataType { get }
    
    var isActive: Bool { get }
    
    var isPatchData: Bool { get }
    
    var isPatchControlPointData: Bool { get }
}

public protocol Attribute : class {
    
    var name: String? { get }
    
    var attributeIndex: Int { get }
    
    var attributeType: DataType { get }
    
    var isActive: Bool { get }
    
    var isPatchData: Bool { get }
    
    var isPatchControlPointData: Bool { get }
}

/*!
 @interface FunctionConstantReflection
 @abstract describe an uberShader constant used by the function
 */
public struct FunctionConstantReflection {
    
    let name: String
    
    let type: DataType
    
    let index: Int
    
    let required: Bool
    
    public init(name: String, type: DataType, index: Int, required: Bool) {
        self.name = name
        self.type = type
        self.index = index
        self.required = required
    }
}

public enum FunctionConstantValue : Hashable {
    case int8(Int8)
    case int16(Int16)
    case int32(Int32)
    
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case bool(Bool)
    case float(Float)
}

public typealias FunctionConstants = Encodable & Hashable

public struct AnyFunctionConstants : FunctionConstants {
    private let constants : AnyHashable
    
    public init<T : FunctionConstants>(_ constants: T) {
        self.constants = constants
    }
    
    public func encode(to encoder: Encoder) throws {
        try (self.constants.base as! Encodable).encode(to: encoder)
    }
    
    public var hashValue: Int {
        return self.constants.hashValue
    }
    
    public static func == (lhs: AnyFunctionConstants, rhs: AnyFunctionConstants) -> Bool {
        return lhs.constants == rhs.constants
    }
}

public enum VertexStepFunction : UInt {
    case constant
    
    case perVertex
    
    case perInstance
    
    case perPatch
    
    case perPatchControlPoint
}
