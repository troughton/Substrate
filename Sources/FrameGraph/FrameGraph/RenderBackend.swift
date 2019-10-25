//
//  RenderBackend.swift
//  CGRA 402
//
//  Created by Thomas Roughton on 10/03/17.
//  Copyright © 2017 Thomas Roughton. All rights reserved.
//

import Foundation

@usableFromInline
protocol PipelineReflection : class {
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

@usableFromInline
protocol RenderBackendProtocol : class {
    func registerExternalResource(_ resource: Resource, backingResource: Any)
    func registerWindowTexture(texture: Texture, context: Any)
    
    func materialisePersistentTexture(_ texture: Texture)
    func materialisePersistentBuffer(_ buffer: Buffer)
    func materialiseHeap(_ heap: Heap)
    
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
    func dispose(argumentBufferArray: _ArgumentBufferArray)
    func dispose(heap: Heap)
    
    func backingResource(_ resource: Resource) -> Any?
    
    func argumentBufferPath(at index: Int, stages: RenderStages) -> ResourceBindingPath
    
    var isDepth24Stencil8PixelFormatSupported : Bool { get }
    var threadExecutionWidth : Int { get }
    
    var renderDevice : Any { get }
    
    var maxInflightFrames : Int { get }
}

public struct RenderBackend {
    @usableFromInline static var backend : RenderBackendProtocol! = nil
    
    @inlinable
    public static var maxInflightFrames : Int {
        return backend.maxInflightFrames
    }
    
    @inlinable
    public static func materialisePersistentTexture(_ texture: Texture) {
        return backend.materialisePersistentTexture(texture)
    }

    @inlinable
    public static func registerExternalResource(_ resource: Resource, backingResource: Any) {
        return backend.registerExternalResource(resource, backingResource: backingResource)
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
    public static func materialiseHeap(_ heap: Heap) {
        return backend.materialiseHeap(heap)
    }
    
    @inlinable
    static func renderPipelineReflection(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) -> PipelineReflection? {
        return backend.renderPipelineReflection(descriptor: descriptor, renderTarget: renderTarget)
    }
    
    @inlinable
    static func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> PipelineReflection? {
        return backend.computePipelineReflection(descriptor: descriptor)
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
    public static func dispose(argumentBuffer: _ArgumentBuffer) {
        return backend.dispose(argumentBuffer: argumentBuffer)
    }
    
    @inlinable
    public static func dispose(argumentBufferArray: _ArgumentBufferArray) {
        return backend.dispose(argumentBufferArray: argumentBufferArray)
    }
    
    @inlinable
    public static func dispose(heap: Heap) {
        return backend.dispose(heap: heap)
    }
    
    @inlinable
    public static func backingResource<R : ResourceProtocol>(_ resource: R) -> Any? {
        return backend.backingResource(Resource(resource))
    }
    
    @inlinable
    public static var isDepth24Stencil8PixelFormatSupported : Bool {
        return backend.isDepth24Stencil8PixelFormatSupported
    }
    
    @inlinable
    public static var threadExecutionWidth : Int {
        return backend.threadExecutionWidth
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
    public static func copyTextureBytes(from texture: Texture, to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int) {
        return backend.copyTextureBytes(from: texture, to: bytes, bytesPerRow: bytesPerRow, region: region, mipmapLevel: mipmapLevel)
    }
    
    @inlinable
    public static func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        return backend.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }

    @inlinable
    public static func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        return backend.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
    }
    
    @inlinable
    public static var renderDevice : Any {
        return backend.renderDevice
    }
    
    public static var pushConstantPath : ResourceBindingPath = ResourceBindingPath.nil
    
     /// There are eight binding slots for argument buffers; this maps from a binding index to the ResourceBindingPath that identifies that index in the backend.
    @inlinable
    public static func argumentBufferPath(at index: Int, stages: RenderStages) -> ResourceBindingPath {
        assert(index < 8)
        return backend.argumentBufferPath(at: index, stages: stages)
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
