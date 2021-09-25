//
//  File.swift
//  File
//
//  Created by Thomas Roughton on 25/09/21.
//

import Foundation
import Atomics
#if canImport(OSLog)
import OSLog
#endif

public struct SignpostID: RawRepresentable {
    public let rawValue: UInt64
    
    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
    
    /// Represents the null (absent) signpost ID. It is used by the signpost subsystem when a given signpost is disabled.
    public static var null: SignpostID { return SignpostID(rawValue: 0) }

    /// Represents an invalid signpost ID, which signals that an error has occurred.
    public static var invalid: SignpostID { return SignpostID(rawValue: 0) }
    
    /// A convenience value for signpost intervals that will never occur concurrently.
    public static var exclusive: SignpostID { return SignpostID(rawValue: 0xEEEEB0B5B2B2EEEE) }
    
#if canImport(OSLog)
    public var osID: OSSignpostID {
        return OSSignpostID(rawValue)
    }
#endif
}

public struct SignpostMetadata: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    var message: String
    
    @inlinable
    public init(stringLiteral value: StringLiteralType) {
        self.message = value
    }
    
    @inlinable
    public init(stringInterpolation: DefaultStringInterpolation) {
        self.message = .init(stringInterpolation: stringInterpolation)
    }
}

public struct Signposter {
#if canImport(OSLog)
    public var signposter: Any? // OSSignposter
#endif
    
    public var isEnabled: Bool {
#if canImport(OSLog)
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            return (self.signposter as! OSSignposter).isEnabled
        }
#endif
        return false
    }
    
    public init(subsystem: String, category: String) {
#if canImport(OSLog)
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            self.signposter = OSSignposter(subsystem: subsystem, category: category)
        } else {
            self.signposter = nil
        }
#else
        self.signposter = nil
#endif
    }

    public func emitEvent(_ name: StaticString, id: SignpostID = .exclusive, _ message: SignpostMetadata) {
#if canImport(OSLog)
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            (self.signposter as! OSSignposter).emitEvent(name, id: id.osID, "\(message.message)")
        }
#endif
    }

    public func emitEvent(_ name: StaticString, id: SignpostID = .exclusive) {
#if canImport(OSLog)
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            (self.signposter as! OSSignposter).emitEvent(name, id: id.osID)
        }
#endif
    }

    public func beginInterval(_ name: StaticString, id: SignpostID = .exclusive, _ message: SignpostMetadata) -> SignpostIntervalState {
#if canImport(OSLog)
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            return SignpostIntervalState(state: (self.signposter as! OSSignposter).beginInterval(name, id: id.osID, "\(message.message)"))
        }
#endif
        return SignpostIntervalState(state: nil)
    }

    public func beginInterval(_ name: StaticString, id: SignpostID = .exclusive) -> SignpostIntervalState {
#if canImport(OSLog)
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            return SignpostIntervalState(state: (self.signposter as! OSSignposter).beginInterval(name, id: id.osID))
        }
#endif
        return SignpostIntervalState(state: nil)
    }

    public func endInterval(_ name: StaticString, _ state: SignpostIntervalState, _ message: SignpostMetadata) {
#if canImport(OSLog)
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            (self.signposter as! OSSignposter).endInterval(name, state.state as! OSSignpostIntervalState, "\(message.message)")
        }
#endif
    }

    public func endInterval(_ name: StaticString, _ state: SignpostIntervalState) {
#if canImport(OSLog)
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            (self.signposter as! OSSignposter).endInterval(name, state.state as! OSSignpostIntervalState)
        }
#endif
    }

    @inlinable
    public func withIntervalSignpost<T>(_ name: StaticString, id: SignpostID = .exclusive, _ message: SignpostMetadata, around task: () async throws -> T) reasync rethrows -> T {
        let state = self.beginInterval(name, id: id, message)
        let result = try await task()
        self.endInterval(name, state, message)
        return result
    }

    public func withIntervalSignpost<T>(_ name: StaticString, id: SignpostID = .exclusive, around task: () async throws -> T) reasync rethrows -> T {
        let state = self.beginInterval(name, id: id)
        let result = try await task()
        self.endInterval(name, state)
        return result
    }

    @inlinable public func makeSignpostID() -> SignpostID {
#if canImport(OSLog)
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            return SignpostID(rawValue: (self.signposter as! OSSignposter).makeSignpostID().rawValue)
        }
#endif
        return .exclusive
    }

    @inlinable public func makeSignpostID(from object: AnyObject) -> SignpostID {
#if canImport(OSLog)
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            return SignpostID(rawValue: (self.signposter as! OSSignposter).makeSignpostID(from: object).rawValue)
        }
#endif
        return SignpostID(rawValue: UInt64(UInt(bitPattern: Unmanaged.passUnretained(object).toOpaque())))
    }
}

/// A type that tracks the state of an interval. The state is used in runtime sanity checks.
public class SignpostIntervalState : Codable {
    let state: AnyObject?
    
    public static func beginState(id: SignpostID) -> SignpostIntervalState {
#if canImport(OSLog)
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            return SignpostIntervalState(state: OSSignpostIntervalState.beginState(id: id.osID))
        }
#endif
        return SignpostIntervalState(state: nil)
    }
    
    required init(state: AnyObject?) {
        self.state = state
    }
    
    required public init(from decoder: Decoder) throws {
#if canImport(OSLog)
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            self.state = try OSSignpostIntervalState(from: decoder)
        } else {
            self.state = nil
        }
#else
        self.state = nil
#endif
    }
    
    public func encode(to encoder: Encoder) throws {
#if canImport(OSLog)
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            try unsafeDowncast(self.state!, to: OSSignpostIntervalState.self).encode(to: encoder)
        }
#endif
    }
}
