//
//  ReasyncCompatibility.swift
//  
//
//  Created by Thomas Roughton on 5/11/21.
//

import Foundation

extension Optional {
    @inlinable
    public func map<U>(_ transform: (Wrapped) async throws -> U) async rethrows -> U? {
        switch self {
        case .some(let element):
            return try await transform(element)
        case .none:
            return nil
        }
    }
    
    @inlinable
    public func flatMap<U>(_ transform: (Wrapped) async throws -> U?) async rethrows -> U? {
        switch self {
        case .some(let element):
            return try await transform(element)
        case .none:
            return nil
        }
    }
}
