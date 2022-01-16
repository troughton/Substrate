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
    public var wrappedValue : T? {
        didSet {
            self.isDirty = true
        }
    }
    
    @usableFromInline var isDirty: Bool = false
    @usableFromInline var _buffer: OffsetView<Buffer>?
    
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
    
    public mutating func updateBuffer() {
        if var value = self.wrappedValue {
            self._buffer = OffsetView(value: Buffer(length: MemoryLayout<T>.size, storageMode: .shared, bytes: &value), offset: 0)
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
