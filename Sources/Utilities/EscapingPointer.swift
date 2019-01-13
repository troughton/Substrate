//
//  EscapingPointer.swift
//  CGRAGame
//
//  Created by Thomas Roughton on 21/05/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

@inlinable
public func escapingPointer<T>(to: inout T) -> UnsafePointer<T> {
    return withUnsafePointer(to: &to, {
        return $0
    })
}

@inlinable
public func escapingMutablePointer<T>(to: inout T) -> UnsafeMutablePointer<T> {
    return withUnsafeMutablePointer(to: &to, {
        return $0
    })
}

@inlinable
public func escapingCastPointer<T, U>(to: inout T) -> UnsafePointer<U> {
    return withUnsafePointer(to: &to, {
        return UnsafeRawPointer($0).assumingMemoryBound(to: U.self)
    })
}

@inlinable
public func escapingCastMutablePointer<T, U>(to: inout T) -> UnsafeMutablePointer<U> {
    return withUnsafeMutablePointer(to: &to, {
        return UnsafeMutableRawPointer($0).assumingMemoryBound(to: U.self)
    })
}
