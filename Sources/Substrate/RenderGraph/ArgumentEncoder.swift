//
//  ArgumentEncoder.swift
//  RenderGraph
//
//  Created by Thomas Roughton on 19/12/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

@propertyWrapper
public struct OffsetView<T> {
    public var wrappedValue : T
    public var offset : Int
    
    @inlinable
    public init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
        self.offset = 0
    }
    
    @inlinable
    public init(value: T, offset: Int) {
        self.wrappedValue = value
        self.offset = offset
    }
    
    @inlinable
    public var projectedValue : OffsetView<T> {
        get {
            return self
        }
        set {
            self = newValue
        }
    }
}

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
    }
    
    @inlinable
    public init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
        self._buffer = nil
        self.isDirty = wrappedValue != nil
    }
    
    @inlinable
    public mutating func updateBuffer() {
        if let value = self.wrappedValue {
            self._buffer = withUnsafeBytes(of: value) {
                OffsetView(value: Buffer(length: MemoryLayout<T>.size, storageMode: .shared, bytes: $0.baseAddress), offset: 0)
            }
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
