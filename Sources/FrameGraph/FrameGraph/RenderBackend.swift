//
//  RenderBackend.swift
//  CGRA 402
//
//  Created by Thomas Roughton on 10/03/17.
//  Copyright © 2017 Thomas Roughton. All rights reserved.
//

import Foundation

public protocol PipelineReflection : class {
    func bindingPath(argumentBuffer: _ArgumentBuffer, argumentName: String, arrayIndex: Int) -> ResourceBindingPath?
    func bindingPath(argumentName: String, arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath?
    func bindingPath(pathInOriginalArgumentBuffer: ResourceBindingPath, newArgumentBufferPath: ResourceBindingPath) -> ResourceBindingPath
    func argumentReflection(at path: ResourceBindingPath) -> ArgumentReflection?
    func bindingIsActive(at path: ResourceBindingPath) -> Bool
}

extension PipelineReflection {
    public func bindingIsActive(at path: ResourceBindingPath) -> Bool {
        return self.argumentReflection(at: path)?.isActive ?? false
    }
}

public protocol RenderBackendProtocol : class {
    
    func registerWindowTexture(texture: Texture, context: Any)
    
    func materialisePersistentTexture(_ texture: Texture)
    func materialisePersistentBuffer(_ buffer: Buffer)
    
    func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer
    func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>)
    
    func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int)
    func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int)
    func renderPipelineReflection(descriptor: _RenderPipelineDescriptor, renderTarget: _RenderTargetDescriptor) -> PipelineReflection
    func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> PipelineReflection
    
    func dispose(texture: Texture)
    func dispose(buffer: Buffer)
    func dispose(argumentBuffer: _ArgumentBuffer)
    
    func backingResource(_ resource: Resource) -> Any?
    
    var isDepth24Stencil8PixelFormatSupported : Bool { get }
    var threadExecutionWidth : Int { get }
    
    var renderDevice : Any { get }
    
    var maxInflightFrames : Int { get }
}

@_fixed_layout
public struct _CachedRenderBackend {
    public var registerWindowTexture : (Texture, Any) -> Void
    
    public var materialisePersistentTexture : (Texture) -> Void
    public var materialisePersistentBuffer : (Buffer) -> Void
    
    public var bufferContents : (Buffer, Range<Int>) -> UnsafeMutableRawPointer
    public var bufferDidModifyRange : (Buffer, Range<Int>) -> Void
    
    public var replaceTextureRegion : (Texture, Region, Int, UnsafeRawPointer,Int) -> Void
    public var replaceTextureRegionForSlice : (Texture, Region, Int, Int, UnsafeRawPointer, Int, Int) -> Void
   
    public var renderPipelineReflection : (_RenderPipelineDescriptor, _RenderTargetDescriptor) -> PipelineReflection
    
    public var computePipelineReflection : (ComputePipelineDescriptor) -> PipelineReflection
    
    public var disposeTexture : (Texture) -> Void
    public var disposeBuffer : (Buffer) -> Void
    public var disposeArgumentBuffer : (_ArgumentBuffer) -> Void
    public var disposeArgumentBufferArray : (_ArgumentBufferArray) -> Void
    
    public var backingResource : (Resource) -> Any?
    
    public var isDepth24Stencil8PixelFormatSupported : () -> Bool
    public var threadExecutionWidth : () -> Int
    
    public var renderDevice : () -> Any
    
    public var maxInflightFrames : () -> Int
    
    public init(registerWindowTexture: @escaping (Texture, Any) -> Void,
                materialisePersistentTexture: @escaping (Texture) -> Void,
                materialisePersistentBuffer: @escaping (Buffer) -> Void,
                bufferContents: @escaping (Buffer, Range<Int>) -> UnsafeMutableRawPointer,
                bufferDidModifyRange: @escaping (Buffer, Range<Int>) -> Void,
                replaceTextureRegion: @escaping (Texture, Region, Int, UnsafeRawPointer, Int) -> Void,
                replaceTextureRegionForSlice: @escaping (Texture, Region, Int, Int, UnsafeRawPointer, Int, Int) -> Void,
                renderPipelineReflection: @escaping (_RenderPipelineDescriptor, _RenderTargetDescriptor) -> PipelineReflection,
                computePipelineReflection: @escaping (ComputePipelineDescriptor) -> PipelineReflection,
                disposeTexture: @escaping (Texture) -> Void,
                disposeBuffer: @escaping (Buffer) -> Void,
                disposeArgumentBuffer: @escaping (_ArgumentBuffer) -> Void,
                disposeArgumentBufferArray: @escaping (_ArgumentBufferArray) -> Void,
                backingResource: @escaping (Resource) -> Any?,
                isDepth24Stencil8PixelFormatSupported: @escaping () -> Bool,
                threadExecutionWidth: @escaping () -> Int,
                renderDevice: @escaping () -> Any,
                maxInflightFrames: @escaping () -> Int) {
        self.registerWindowTexture = registerWindowTexture
        self.materialisePersistentTexture = materialisePersistentTexture
        self.materialisePersistentBuffer = materialisePersistentBuffer
        self.bufferContents = bufferContents
        self.bufferDidModifyRange = bufferDidModifyRange
        self.replaceTextureRegion = replaceTextureRegion
        self.replaceTextureRegionForSlice = replaceTextureRegionForSlice
        self.renderPipelineReflection = renderPipelineReflection
        self.computePipelineReflection = computePipelineReflection
        self.disposeTexture = disposeTexture
        self.disposeBuffer = disposeBuffer
        self.disposeArgumentBuffer = disposeArgumentBuffer
        self.disposeArgumentBufferArray = disposeArgumentBufferArray
        self.backingResource = backingResource
        self.isDepth24Stencil8PixelFormatSupported = isDepth24Stencil8PixelFormatSupported
        self.threadExecutionWidth = threadExecutionWidth
        self.renderDevice = renderDevice
        self.maxInflightFrames = maxInflightFrames
    }
    
    public static let nilBackend : _CachedRenderBackend = _CachedRenderBackend(registerWindowTexture: { _, _ in },
                                                                               materialisePersistentTexture: { _ in },
                                                                               materialisePersistentBuffer: { _ in },
                                                                               bufferContents: { _, _ in fatalError() },
                                                                               bufferDidModifyRange: { _, _ in },
                                                                               replaceTextureRegion: { _, _, _, _, _ in },
                                                                               replaceTextureRegionForSlice: { _, _, _, _, _, _, _ in },
                                                                               renderPipelineReflection: { _, _ in fatalError() },
                                                                               computePipelineReflection: { _ in fatalError() },
                                                                               disposeTexture: { _ in },
                                                                               disposeBuffer: { _ in },
                                                                               disposeArgumentBuffer: { _ in },
                                                                               disposeArgumentBufferArray: { _ in },
                                                                               backingResource: { _ in fatalError() },
                                                                               isDepth24Stencil8PixelFormatSupported: { false },
                                                                               threadExecutionWidth: { 0 },
                                                                               renderDevice: { fatalError() },
                                                                               maxInflightFrames: { 0 })
}

@_fixed_layout
public struct RenderBackend {
    public static var _cachedBackend = _CachedRenderBackend.nilBackend
    
    @inlinable
    public static var maxInflightFrames : Int {
        
        return _cachedBackend.maxInflightFrames()
    }
    
    @inlinable
    public static func materialisePersistentTexture(_ texture: Texture) {
        return _cachedBackend.materialisePersistentTexture(texture)
    }
    
    @inlinable
    public static func registerWindowTexture(texture: Texture, context: Any) {
        return _cachedBackend.registerWindowTexture(texture, context)
    }
    
    @inlinable
    public static func materialisePersistentBuffer(_ buffer: Buffer) {
        return _cachedBackend.materialisePersistentBuffer(buffer)
    }
    
    @inlinable
    public static func renderPipelineReflection(descriptor: _RenderPipelineDescriptor, renderTarget: _RenderTargetDescriptor) -> PipelineReflection {
        return _cachedBackend.renderPipelineReflection(descriptor, renderTarget)
    }
    
    @inlinable
    public static func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> PipelineReflection {
        return _cachedBackend.computePipelineReflection(descriptor)
    }
    
    @inlinable
    public static func dispose(texture: Texture) {
        return _cachedBackend.disposeTexture(texture)
    }
    
    @inlinable
    public static func dispose(buffer: Buffer) {
        return _cachedBackend.disposeBuffer(buffer)
    }
    
    @inlinable
    public static func dispose(argumentBuffer: _ArgumentBuffer) {
        return _cachedBackend.disposeArgumentBuffer(argumentBuffer)
    }
    
    @inlinable
    public static func dispose(argumentBufferArray: _ArgumentBufferArray) {
        return _cachedBackend.disposeArgumentBufferArray(argumentBufferArray)
    }
    
    @inlinable
    public static func backingResource<R : ResourceProtocol>(_ resource: R) -> Any? {
        return _cachedBackend.backingResource(Resource(resource))
    }
    
    @inlinable
    public static var isDepth24Stencil8PixelFormatSupported : Bool {
        return _cachedBackend.isDepth24Stencil8PixelFormatSupported()
    }
    
    @inlinable
    public static var threadExecutionWidth : Int {
        return _cachedBackend.threadExecutionWidth()
    }
    
    @inlinable
    public static func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer {
        return _cachedBackend.bufferContents(buffer, range)
    }
    
    @inlinable
    public static func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
        return _cachedBackend.bufferDidModifyRange(buffer, range)
    }
    
    @inlinable
    public static func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        return _cachedBackend.replaceTextureRegion(texture, region, mipmapLevel, bytes, bytesPerRow)
    }

    @inlinable
    public static func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        return _cachedBackend.replaceTextureRegionForSlice(texture, region, mipmapLevel, slice, bytes, bytesPerRow, bytesPerImage)
    }
    
    @inlinable
    public static var renderDevice : Any {
        return _cachedBackend.renderDevice()
    }
}

//@_fixed_layout
//public struct RenderBackend {
//
//    // This is going to go through a protocol lookup table every time for each method, which might be slow.
//    // However, we can cache the functions (the result of the lookup entry) within the types that call them
//    // if need be; e.g. let newTextureHandle = backend.newTextureHandle.
//    public static var backend : RenderBackendProtocol! = nil
//
//    @inlinable
//    public static var maxInflightFrames : Int {
//        return backend.maxInflightFrames
//    }
//
//    @inlinable
//    public static func materialisePersistentTexture(_ texture: Texture) {
//        return backend.materialisePersistentTexture(texture)
//    }
//
//    @inlinable
//    public static func registerWindowTexture(texture: Texture, context: Any) {
//        return backend.registerWindowTexture(texture: texture, context: context)
//    }
//
//    @inlinable
//    public static func materialisePersistentBuffer(_ buffer: Buffer) {
//        return backend.materialisePersistentBuffer(buffer)
//    }
//
//    @inlinable
//    public static func setReflectionRenderPipeline(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) {
//        return backend.setReflectionRenderPipeline(descriptor: descriptor, renderTarget: renderTarget)
//    }
//
//    @inlinable
//    public static func setReflectionComputePipeline(descriptor: ComputePipelineDescriptor) {
//        return backend.setReflectionComputePipeline(descriptor: descriptor)
//    }
//
//    @inlinable
//    public static func bindingPath(argumentBuffer: _ArgumentBuffer, argumentName: String, arrayIndex: Int) -> ResourceBindingPath? {
//        return backend.bindingPath(argumentBuffer: argumentBuffer, argumentName: argumentName, arrayIndex: arrayIndex)
//    }
//
//    @inlinable
//    public static func bindingPath(argumentName: String, arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath? {
//        return backend.bindingPath(argumentName: argumentName, arrayIndex: arrayIndex, argumentBufferPath: argumentBufferPath)
//    }
//
//    @inlinable
//    public static func bindingPath(pathInOriginalArgumentBuffer: ResourceBindingPath, newArgumentBufferPath: ResourceBindingPath) -> ResourceBindingPath {
//        return backend.bindingPath(pathInOriginalArgumentBuffer: pathInOriginalArgumentBuffer, newArgumentBufferPath: newArgumentBufferPath)
//    }
//
//    @inlinable
//    public static func argumentReflection(at path: ResourceBindingPath) -> ArgumentReflection? {
//        return backend.argumentReflection(at: path)
//    }
//
//    @inlinable
//    public static func bindingIsActive(at path: ResourceBindingPath) -> Bool {
//        return backend.bindingIsActive(at: path)
//    }
//
//    @inlinable
//    public static func dispose(texture: Texture) {
//        return backend.dispose(texture: texture)
//    }
//
//    @inlinable
//    public static func dispose(buffer: Buffer) {
//        return backend.dispose(buffer: buffer)
//    }
//
//    @inlinable
//    public static func dispose(argumentBuffer: _ArgumentBuffer) {
//        return backend.dispose(argumentBuffer: argumentBuffer)
//    }
//
//    @inlinable
//    public static var isDepth24Stencil8PixelFormatSupported : Bool {
//        return backend.isDepth24Stencil8PixelFormatSupported
//    }
//
//    @inlinable
//    public static var threadExecutionWidth : Int {
//        return backend.threadExecutionWidth
//    }
//
//    @inlinable
//    public static func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer {
//        return backend.bufferContents(for: buffer, range: range)
//    }
//
//    @inlinable
//    public static func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
//        return backend.buffer(buffer, didModifyRange: range)
//    }
//
//    @inlinable
//    public static func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
//        return backend.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
//    }
//
//    @inlinable
//    public static var renderDevice : Any {
//        return backend.renderDevice
//    }
//}


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
