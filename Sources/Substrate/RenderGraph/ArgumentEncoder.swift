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
    
    var isDirty: Bool = false
    @usableFromInline var _buffer: OffsetView<Buffer>?
    
    public var buffer : OffsetView<Buffer>? {
        mutating get {
            if self.isDirty {
                self.updateBuffer()
            }
            return self._buffer
        }
    }
    
    public init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
        self._buffer = nil
        self.isDirty = wrappedValue != nil
    }
    
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

extension Buffer : Encodable {
    public func encode(to encoder: Encoder) throws {
        assertionFailure("Buffer.encode(to:) should never be called directly.")
    }
}

extension Texture : Encodable {
    public func encode(to encoder: Encoder) throws {
        assertionFailure("Texture.encode(to:) should never be called directly.")
    }
}

open class FunctionArgumentEncoder<CE : ResourceBindingEncoder> : Encoder {
    /// Contextual user-provided information for use during encoding.
    open var userInfo: [CodingUserInfoKey : Any] = [:]
    
    let commandEncoder : CE
    public var codingPath: [CodingKey] = []
    
    public init(commandEncoder: CE) {
        self.commandEncoder = commandEncoder
    }
    
    // MARK: - Encoding Values
    
    open func encode<T : Encodable>(_ value: T) throws {
        try value.encode(to: self)
    }
    
    // MARK: - Encoder Methods
    public func container<Key>(keyedBy: Key.Type) -> KeyedEncodingContainer<Key> {
        let container = _FunctionArgumentKeyedEncodingContainer<Key, CE>(referencing: self, codingPath: self.codingPath)
        return KeyedEncodingContainer(container)
    }
    
    public func unkeyedContainer() -> UnkeyedEncodingContainer {
        fatalError("Unkeyed containers are unsupported.")
    }
    
    public func singleValueContainer() -> SingleValueEncodingContainer {
        fatalError()
    }
}

// MARK: - Encoding Containers

fileprivate struct _FunctionArgumentKeyedEncodingContainer<K : CodingKey, CE : ResourceBindingEncoder> : KeyedEncodingContainerProtocol {
    typealias Key = K
    
    // MARK: Properties
    
    /// A reference to the encoder we're writing to.
    private let encoder: FunctionArgumentEncoder<CE>
    private let commandEncoder : CE
    
    /// The path of coding keys taken to get to this point in encoding.
    private(set) public var codingPath: [CodingKey]
    
    // MARK: - Initialization
    
    /// Initializes `self` with the given references.
    fileprivate init(referencing encoder: FunctionArgumentEncoder<CE>, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
        self.commandEncoder = self.encoder.commandEncoder
    }
    
    func functionArgumentKey(_ key: K) -> FunctionArgumentKey {
        if let key = key as? FunctionArgumentKey {
            return key
        }
        return key.stringValue
    }
    
    // MARK: - KeyedEncodingContainerProtocol Methods
    
    public mutating func encodeNil(forKey key: Key) throws {
        // Do nothing; setting nil for an argument doesn't have any practical use.
    }
    
    public mutating func encode(_ value: Bool, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    
    public mutating func encode(_ value: Int, forKey key: Key) throws {
        throw ArgumentEncodingError.unsupportedValue(value, "Use sized types rather than Ints.")
    }
    public mutating func encode(_ value: Int8, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    public mutating func encode(_ value: Int16, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    public mutating func encode(_ value: Int32, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    public mutating func encode(_ value: Int64, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    public mutating func encode(_ value: UInt, forKey key: Key) throws {
        throw ArgumentEncodingError.unsupportedValue(value, "Use sized types rather than UInts.")
    }
    public mutating func encode(_ value: UInt8, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    public mutating func encode(_ value: UInt16, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    public mutating func encode(_ value: UInt32, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    public mutating func encode(_ value: UInt64, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    public mutating func encode(_ value: String, forKey key: Key) throws {
        throw ArgumentEncodingError.unsupportedValue(value, "Strings may not be encoded.")
    }
    public mutating func encode(_ value: Float, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    
    public mutating func encode(_ value: Double, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    
    public mutating func encode<T : Encodable>(_ value: T, forKey key: Key) throws {
        switch value {
        case let texture as Texture:
            self.commandEncoder.setTexture(texture, key: functionArgumentKey(key))
        case let buffer as Buffer:
            self.commandEncoder.setBuffer(buffer, offset: 0, key: functionArgumentKey(key))
        case let sampler as SamplerDescriptor:
            self.commandEncoder.setSampler(sampler, key: functionArgumentKey(key))
        default:
            self.commandEncoder.setValue(value, key: functionArgumentKey(key))
        }
    }
    
    public mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        fatalError("Nested keyed containers are unsupported. Use argument buffers instead.")
    }
    
    public mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        fatalError("Unkeyed containers are unsupported.")
    }
    
    public mutating func superEncoder() -> Encoder {
        fatalError("Unimplemented.")
    }
    
    public mutating func superEncoder(forKey key: Key) -> Encoder {
        fatalError("Unimplemented.")
    }
}

public enum ArgumentEncodingError<T> : Error {
    case unsupportedValue(T, String)
    case invalidKey(CodingKey)
}

