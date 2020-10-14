//
//  FunctionConstantEncoder.swift
//  Renderer
//
//  Created by Thomas Roughton on 25/12/17.
//

public class FunctionConstantEncoder : Encoder {
    /// Contextual user-provided information for use during encoding.
    open var userInfo: [CodingUserInfoKey : Any] = [:]

    var constants = [String : FunctionConstantValue]()
    public var codingPath: [CodingKey] = []

    public init() {
    }

    // MARK: - Encoding Values

    public func encodeToDict<T : Encodable>(_ value: T) throws -> [String : FunctionConstantValue] {
        try value.encode(to: self)
        
        let result = self.constants
        self.constants = [:]
        return result
    }

    // MARK: - Encoder Methods
    public func container<Key>(keyedBy: Key.Type) -> KeyedEncodingContainer<Key> {
        let container = _FunctionConstantKeyedEncodingContainer<Key>(referencing: self, codingPath: self.codingPath)
        return KeyedEncodingContainer(container)
    }

    public func unkeyedContainer() -> UnkeyedEncodingContainer {
        fatalError("Unkeyed containers are unsupported.")
    }

    public func singleValueContainer() -> SingleValueEncodingContainer {
        return self
    }
}

extension FunctionConstantEncoder : SingleValueEncodingContainer {
    public func encodeNil() throws {
        self.constants[self.codingPath.last!.stringValue] = nil
    }
    
    public func encode(_ value: Bool) throws {
        self.constants[self.codingPath.last!.stringValue] = .bool(value)
    }
    public func encode(_ value: Int) throws {
        throw FunctionConstantEncodingError.unsupportedValue(value, "Use sized types rather than Ints.")
    }
    public func encode(_ value: Int8) throws {
        self.constants[self.codingPath.last!.stringValue] = .int8(value)
    }
    public func encode(_ value: Int16) throws {
        self.constants[self.codingPath.last!.stringValue] = .int16(value)
    }
    public func encode(_ value: Int32) throws {
        self.constants[self.codingPath.last!.stringValue] = .int32(value)
    }
    public func encode(_ value: Int64) throws {
        throw FunctionConstantEncodingError.unsupportedValue(value, "64-bit integers are unsupported.")
    }
    public func encode(_ value: UInt) throws {
        throw FunctionConstantEncodingError.unsupportedValue(value, "Use sized types rather than UInts.")
    }
    public func encode(_ value: UInt8) throws {
        self.constants[self.codingPath.last!.stringValue] = .uint8(value)
    }
    public func encode(_ value: UInt16) throws {
        self.constants[self.codingPath.last!.stringValue] = .uint16(value)
    }
    public func encode(_ value: UInt32) throws {
        self.constants[self.codingPath.last!.stringValue] = .uint32(value)
    }
    public func encode(_ value: UInt64) throws {
        throw FunctionConstantEncodingError.unsupportedValue(value, "64-bit integers are unsupported.")
    }
    public func encode(_ value: String) throws {
        throw FunctionConstantEncodingError.unsupportedValue(value, "Strings may not be encoded.")
    }
    public func encode(_ value: Float) throws {
        self.constants[self.codingPath.last!.stringValue] = .float(value)
    }
    
    public func encode(_ value: Double) throws {
        throw FunctionConstantEncodingError.unsupportedValue(value, "Doubles are unsupported.")
    }
    
    public func encode<T : Encodable & AnyObject>(_ value: T) throws {
        throw FunctionConstantEncodingError.unsupportedValue(value, "Encoded objects must be of value type.")
    }
    
    public func encode<T : Encodable>(_ value: T) throws {
        throw FunctionConstantEncodingError.unsupportedValue(value, "Encoded objects must be of value type.")
    }
}

// MARK: - Encoding Containers

fileprivate struct _FunctionConstantKeyedEncodingContainer<K : CodingKey> : KeyedEncodingContainerProtocol {
    typealias Key = K

    // MARK: Properties

    /// A reference to the encoder we're writing to.
    private let encoder: FunctionConstantEncoder

    /// The path of coding keys taken to get to this point in encoding.
    private(set) public var codingPath: [CodingKey]

    // MARK: - Initialization

    /// Initializes `self` with the given references.
    fileprivate init(referencing encoder: FunctionConstantEncoder, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
    }

    // MARK: - KeyedEncodingContainerProtocol Methods
    
    public mutating func encodeNil(forKey key: Key) throws {
        self.encoder.constants[key.stringValue] = nil
    }

    public mutating func encode(_ value: Bool, forKey key: Key) throws {
        self.encoder.constants[key.stringValue] = .bool(value)
    }
    public mutating func encode(_ value: Int, forKey key: Key) throws {
        throw FunctionConstantEncodingError.unsupportedValue(value, "Use sized types rather than Ints.")
    }
    public mutating func encode(_ value: Int8, forKey key: Key) throws {
        self.encoder.constants[key.stringValue] = .int8(value)
    }
    public mutating func encode(_ value: Int16, forKey key: Key) throws {
        self.encoder.constants[key.stringValue] = .int16(value)
    }
    public mutating func encode(_ value: Int32, forKey key: Key) throws {
        self.encoder.constants[key.stringValue] = .int32(value)
    }
    public mutating func encode(_ value: Int64, forKey key: Key) throws {
        throw FunctionConstantEncodingError.unsupportedValue(value, "64-bit integers are unsupported.")
    }
    public mutating func encode(_ value: UInt, forKey key: Key) throws {
        throw FunctionConstantEncodingError.unsupportedValue(value, "Use sized types rather than UInts.")
    }
    public mutating func encode(_ value: UInt8, forKey key: Key) throws {
        self.encoder.constants[key.stringValue] = .uint8(value)
    }
    public mutating func encode(_ value: UInt16, forKey key: Key) throws {
        self.encoder.constants[key.stringValue] = .uint16(value)
    }
    public mutating func encode(_ value: UInt32, forKey key: Key) throws {
        self.encoder.constants[key.stringValue] = .uint32(value)
    }
    public mutating func encode(_ value: UInt64, forKey key: Key) throws {
        throw FunctionConstantEncodingError.unsupportedValue(value, "64-bit integers are unsupported.")
    }
    public mutating func encode(_ value: String, forKey key: Key) throws {
        throw FunctionConstantEncodingError.unsupportedValue(value, "Strings may not be encoded.")
    }
    public mutating func encode(_ value: Float, forKey key: Key) throws {
        self.encoder.constants[key.stringValue] = .float(value)
    }

    public mutating func encode(_ value: Double, forKey key: Key) throws {
        throw FunctionConstantEncodingError.unsupportedValue(value, "Doubles are unsupported.")
    }

    public mutating func encode<T : Encodable & AnyObject>(_ value: T, forKey key: Key) throws {
        throw FunctionConstantEncodingError.unsupportedValue(value, "Encoded objects must be of value type.")
    }

    public mutating func encode<T : Encodable>(_ value: T, forKey key: Key) throws {
        self.encoder.codingPath.append(key)
        try value.encode(to: self.encoder)
        self.encoder.codingPath.removeLast()
    }

    public mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        fatalError("Nested keyed containers are unsupported.")
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

public enum FunctionConstantEncodingError<T> : Error {
    case unsupportedValue(T, String)
    case invalidKey(CodingKey)
}

