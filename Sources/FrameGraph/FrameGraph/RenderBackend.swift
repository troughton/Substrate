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
    
    func argumentBufferEncoder(at path: ResourceBindingPath) -> UnsafeRawPointer?
}

extension PipelineReflection {
    public func bindingIsActive(at path: ResourceBindingPath) -> Bool {
        return self.argumentReflection(at: path)?.isActive ?? false
    }
}

public protocol RenderBackendProtocol : class {
    
    func registerExternalResource(_ resource: Resource, backingResource: Any)
    func registerWindowTexture(texture: Texture, context: Any)
    
    func materialisePersistentTexture(_ texture: Texture)
    func materialisePersistentBuffer(_ buffer: Buffer)
    
    func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer
    func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>)
    
    func copyTextureBytes(from texture: Texture, to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int)
    func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int)
    func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int)
    
    // Note: The pipeline reflection functions may return nil if reflection information could not be created for the pipeline.
    func renderPipelineReflection(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) -> PipelineReflection?
    func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> PipelineReflection?
    
    func dispose(texture: Texture)
    func dispose(buffer: Buffer)
    func dispose(argumentBuffer: _ArgumentBuffer)
    
    func backingResource(_ resource: Resource) -> Any?
    
    func argumentBufferPath(at index: Int, stages: RenderStages) -> ResourceBindingPath
    
    var isDepth24Stencil8PixelFormatSupported : Bool { get }
    var threadExecutionWidth : Int { get }
    
    var renderDevice : Any { get }
    
    var maxInflightFrames : Int { get }
}

public struct _CachedRenderBackend {
    public var registerExternalResource : (Resource, Any) -> Void
    public var registerWindowTexture : (Texture, Any) -> Void
    
    public var materialisePersistentTexture : (Texture) -> Void
    public var materialisePersistentBuffer : (Buffer) -> Void
    
    public var bufferContents : (Buffer, Range<Int>) -> UnsafeMutableRawPointer
    public var bufferDidModifyRange : (Buffer, Range<Int>) -> Void
   
    public var copyTextureBytes : (Texture, UnsafeMutableRawPointer, Int, Region, Int) -> Void
    
    public var replaceTextureRegion : (Texture, Region, Int, UnsafeRawPointer,Int) -> Void
    public var replaceTextureRegionForSlice : (Texture, Region, Int, Int, UnsafeRawPointer, Int, Int) -> Void
   
    public var renderPipelineReflection : (RenderPipelineDescriptor,RenderTargetDescriptor) -> PipelineReflection?
    
    public var computePipelineReflection : (ComputePipelineDescriptor) -> PipelineReflection?
    
    public var disposeTexture : (Texture) -> Void
    public var disposeBuffer : (Buffer) -> Void
    public var disposeArgumentBuffer : (_ArgumentBuffer) -> Void
    public var disposeArgumentBufferArray : (_ArgumentBufferArray) -> Void
    
    public var backingResource : (Resource) -> Any?
    
    public var isDepth24Stencil8PixelFormatSupported : () -> Bool
    public var threadExecutionWidth : () -> Int
    
    public var renderDevice : () -> Any
    
    public var maxInflightFrames : () -> Int
    
    public var argumentBufferPath : (Int, RenderStages) -> ResourceBindingPath
    
    public init(registerExternalResource: @escaping (Resource, Any) -> Void,
                registerWindowTexture: @escaping (Texture, Any) -> Void,
                materialisePersistentTexture: @escaping (Texture) -> Void,
                materialisePersistentBuffer: @escaping (Buffer) -> Void,
                bufferContents: @escaping (Buffer, Range<Int>) -> UnsafeMutableRawPointer,
                bufferDidModifyRange: @escaping (Buffer, Range<Int>) -> Void,
                copyTextureBytes: @escaping (Texture, UnsafeMutableRawPointer, Int, Region, Int) -> Void,
                replaceTextureRegion: @escaping (Texture, Region, Int, UnsafeRawPointer, Int) -> Void,
                replaceTextureRegionForSlice: @escaping (Texture, Region, Int, Int, UnsafeRawPointer, Int, Int) -> Void,
                renderPipelineReflection: @escaping (RenderPipelineDescriptor,RenderTargetDescriptor) -> PipelineReflection?,
                computePipelineReflection: @escaping (ComputePipelineDescriptor) -> PipelineReflection?,
                disposeTexture: @escaping (Texture) -> Void,
                disposeBuffer: @escaping (Buffer) -> Void,
                disposeArgumentBuffer: @escaping (_ArgumentBuffer) -> Void,
                disposeArgumentBufferArray: @escaping (_ArgumentBufferArray) -> Void,
                backingResource: @escaping (Resource) -> Any?,
                isDepth24Stencil8PixelFormatSupported: @escaping () -> Bool,
                threadExecutionWidth: @escaping () -> Int,
                renderDevice: @escaping () -> Any,
                maxInflightFrames: @escaping () -> Int,
                argumentBufferPath: @escaping (Int, RenderStages) -> ResourceBindingPath) {
        self.registerExternalResource = registerExternalResource
        self.registerWindowTexture = registerWindowTexture
        self.materialisePersistentTexture = materialisePersistentTexture
        self.materialisePersistentBuffer = materialisePersistentBuffer
        self.bufferContents = bufferContents
        self.bufferDidModifyRange = bufferDidModifyRange
        self.copyTextureBytes = copyTextureBytes
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
        self.argumentBufferPath = argumentBufferPath
    }
    
    public static let nilBackend : _CachedRenderBackend = _CachedRenderBackend(registerExternalResource: { _, _ in },
                                                                               registerWindowTexture: { _, _ in },
                                                                               materialisePersistentTexture: { _ in },
                                                                               materialisePersistentBuffer: { _ in },
                                                                               bufferContents: { _, _ in fatalError() },
                                                                               bufferDidModifyRange: { _, _ in },
                                                                               copyTextureBytes: { _, _, _, _, _ in },
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
                                                                               maxInflightFrames: { 0 },
                                                                               argumentBufferPath: { _,_ in fatalError() })
}

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
    public static func registerExternalResource(_ resource: Resource, backingResource: Any) {
        return _cachedBackend.registerExternalResource(resource, backingResource)
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
    public static func renderPipelineReflection(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) -> PipelineReflection? {
        return _cachedBackend.renderPipelineReflection(descriptor, renderTarget)
    }
    
    @inlinable
    public static func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> PipelineReflection? {
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
    public static func copyTextureBytes(from texture: Texture, to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int) {
        return _cachedBackend.copyTextureBytes(texture, bytes, bytesPerRow, region, mipmapLevel)
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
    
    
    public static var pushConstantPath : ResourceBindingPath = ResourceBindingPath.nil
    
     /// There are eight binding slots for argument buffers; this maps from a binding index to the ResourceBindingPath that identifies that index in the backend.
    @inlinable
    public static func argumentBufferPath(at index: Int, stages: RenderStages) -> ResourceBindingPath {
        assert(index < 8)
        return _cachedBackend.argumentBufferPath(index, stages)
    }
}

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

public typealias FunctionConstantCodable = Encodable & Hashable

public protocol FunctionConstantEncodable : NoArgConstructable, Equatable {
    func encode(into constants: inout FunctionConstants)
}

public struct FunctionConstants : Hashable {
    public struct IndexedConstant : Hashable {
        public var index : Int
        public var value : FunctionConstantValue
        
        public init(index: Int, value: FunctionConstantValue) {
            self.index = index
            self.value = value
        }
    }
    
    public var indexedConstants : [IndexedConstant] = []
    public var namedConstants : [String : FunctionConstantValue] = [:]
    
    public init<T : FunctionConstantCodable>(_ constants: T) throws {
        let encoder = FunctionConstantEncoder()
        try constants.encode(to: encoder)
        self.namedConstants = encoder.constants
    }
    
    @inlinable
    public init<T : FunctionConstantEncodable>(_ constants: T) {
        self.init()
        constants.encode(into: &self)
    }
    
    @inlinable
    public init() {
        
    }
    
    // Indexed constants
    
    @inlinable
    public mutating func setConstant(_ constant: Int8, at index: Int) {
        self.indexedConstants.append(FunctionConstants.IndexedConstant(index: index, value: .int8(constant)))
    }
    
    @inlinable
    public mutating func setConstant(_ constant: Int16, at index: Int) {
        self.indexedConstants.append(FunctionConstants.IndexedConstant(index: index, value: .int16(constant)))
    }
    
    @inlinable
    public mutating func setConstant(_ constant: Int32, at index: Int) {
        self.indexedConstants.append(FunctionConstants.IndexedConstant(index: index, value: .int32(constant)))
    }
    
    @inlinable
    public mutating func setConstant(_ constant: UInt8, at index: Int) {
        self.indexedConstants.append(FunctionConstants.IndexedConstant(index: index, value: .uint8(constant)))
    }
    
    @inlinable
    public mutating func setConstant(_ constant: UInt16, at index: Int) {
        self.indexedConstants.append(FunctionConstants.IndexedConstant(index: index, value: .uint16(constant)))
    }
    
    @inlinable
    public mutating func setConstant(_ constant: UInt32, at index: Int) {
        self.indexedConstants.append(FunctionConstants.IndexedConstant(index: index, value: .uint32(constant)))
    }
    
    @inlinable
    public mutating func setConstant(_ constant: Float, at index: Int) {
        self.indexedConstants.append(FunctionConstants.IndexedConstant(index: index, value: .float(constant)))
    }
    
    @inlinable
    public mutating func setConstant(_ constant: Bool, at index: Int) {
        self.indexedConstants.append(FunctionConstants.IndexedConstant(index: index, value: .bool(constant)))
    }
    
    // Named constants
    
    @inlinable
    public mutating func setConstant(_ constant: Int8, for name: String) {
        self.namedConstants[name] = .int8(constant)
    }
    
    @inlinable
    public mutating func setConstant(_ constant: Int16, for name: String) {
        self.namedConstants[name] = .int16(constant)
    }
    
    @inlinable
    public mutating func setConstant(_ constant: Int32, for name: String) {
        self.namedConstants[name] = .int32(constant)
    }
    
    @inlinable
    public mutating func setConstant(_ constant: UInt8, for name: String) {
        self.namedConstants[name] = .uint8(constant)
    }
    
    @inlinable
    public mutating func setConstant(_ constant: UInt16, for name: String) {
        self.namedConstants[name] = .uint16(constant)
    }
    
    @inlinable
    public mutating func setConstant(_ constant: UInt32, for name: String) {
        self.namedConstants[name] = .uint32(constant)
    }
    
    @inlinable
    public mutating func setConstant(_ constant: Float, for name: String) {
        self.namedConstants[name] = .float(constant)
    }
    
    @inlinable
    public mutating func setConstant(_ constant: Bool, for name: String) {
        self.namedConstants[name] = .bool(constant)
    }
}

public enum VertexStepFunction : UInt {
    case constant
    
    case perVertex
    
    case perInstance
    
    case perPatch
    
    case perPatchControlPoint
}
