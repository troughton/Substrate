//
//  ArgumentEncoder.swift
//  RenderGraph
//
//  Created by Thomas Roughton on 19/12/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

/// `OffsetView` represents a byte offset into a resource.
@propertyWrapper
public struct OffsetView<Wrapped> {
    public typealias T = Wrapped
    
    public var wrappedValue : Wrapped
    public var offset : Int
    
    @inlinable
    public init(wrappedValue: Wrapped) {
        self.wrappedValue = wrappedValue
        self.offset = 0
    }
    
    @inlinable
    public init(value: Wrapped, offset: Int) {
        self.wrappedValue = value
        self.offset = offset
    }
    
    @inlinable
    public var projectedValue : OffsetView<Wrapped> {
        get {
            return self
        }
        set {
            self = newValue
        }
    }
}

extension OffsetView: Sendable where Wrapped: Sendable {}

/// `BufferBacked` is a property wrapper that materialises a `shared` `Buffer` from a provided value.
@propertyWrapper
public struct BufferBacked<T> {
    @usableFromInline var _wrappedValue: T?
    @usableFromInline var isDirty: Bool = false
    @usableFromInline var _buffer: OffsetView<Buffer>?
    
    @inlinable
    public var wrappedValue : T? {
        get {
            return self._wrappedValue
        } set {
            self._wrappedValue = newValue
            self.isDirty = true
        }
    }
    
    @inlinable
    public var buffer : OffsetView<Buffer>? {
        mutating get {
            if self.isDirty {
                self.updateBuffer()
            }
            return self._buffer
        }
        set {
            self._buffer = newValue
            self.isDirty = false
        }
    }
    
    @inlinable
    public init(wrappedValue: T?) {
        precondition(_isPOD(T.self))
        self.wrappedValue = wrappedValue
        self._buffer = nil
        self.isDirty = wrappedValue != nil
    }
    
    @inlinable
    public mutating func updateBuffer() {
        if let value = self.wrappedValue {
            let buffer = Buffer(length: MemoryLayout<T>.size, storageMode: .shared)
            buffer.withMutableContents(range: buffer.range, { [value] memory, _ in
                withUnsafeBytes(of: value) { valueBytes in
                    memory.copyMemory(from: valueBytes)
                }
            })
            self._buffer = OffsetView(value: buffer, offset: 0)
        }
    }
    
    @inlinable
    public var projectedValue : BufferBacked<T> {
        get {
            return self
        }
        set {
            self = newValue
        }
    }
}

/// `BufferBacked` is a property wrapper that materialises a `shared` `ArgumentBuffer` from a provided value.
@propertyWrapper
public struct ArgumentBufferBacked<T: ArgumentBufferEncodable> {
    @usableFromInline let flags: ResourceFlags
    @usableFromInline var _wrappedValue: T
    @usableFromInline var isDirty: Bool = false
    @usableFromInline var _buffer: ArgumentBuffer?
    @usableFromInline var renderGraph: RenderGraph?
    
    @inlinable
    public init(wrappedValue: T, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        self.flags = flags
        self._wrappedValue = wrappedValue
        self._buffer = nil
        self.renderGraph = renderGraph
        self.isDirty = true
    }
    
    public mutating func dispose() {
        self._buffer?.dispose()
        self._buffer = nil
        self.isDirty = true
    }
    
    @inlinable
    public var wrappedValue : T {
        get {
            return self._wrappedValue
        } set {
            self._wrappedValue = newValue
            self.isDirty = true
        }
    }
    
    public var label: String? {
        get {
            return self._buffer?.label
        }
        set {
            if let newValue = newValue {
                self.setBufferIfNeeded()
                self._buffer!.label = newValue
            }
        }
    }
    
    @usableFromInline mutating func setBufferIfNeeded() {
        if self._buffer == nil {
            self._buffer = ArgumentBuffer(descriptor: T.argumentBufferDescriptor, renderGraph: self.renderGraph, flags: self.flags)
        }
    }
    
    @inlinable
    public var argumentBuffer : ArgumentBuffer {
        mutating get async {
            if self.isDirty {
                await self.updateArgumentBuffer()
            }
            return self._buffer!
        }
    }
    
    @inlinable
    public mutating func updateArgumentBuffer() async {
        self.setBufferIfNeeded()
        await self._wrappedValue.encode(into: self._buffer!)
    }
    
    @inlinable
    public var projectedValue : ArgumentBufferBacked<T> {
        get {
            return self
        }
        set {
            self = newValue
        }
    }
}
