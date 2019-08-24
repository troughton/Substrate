//
//  HashableArray.swift
//  Utilities
//
//  Created by Thomas Roughton on 24/12/17.
//

import Swift

#if os(Windows) // supported in more recent toolchains than the one currently used on Windows

extension Array : Hashable where Element : Hashable { //FIXME: this can be made Hashable (allowing synthesized conformance in a few other places) once it's supported in the Swift compiler.
    public var hashValue: Int {
        var hash = 0
        for (i, element) in self.enumerated() {
            hash = hash &+ ((i + 1) &* element.hashValue)
        }
        return hash
    }
}

extension Optional : Hashable where Wrapped : Hashable {
    public var hashValue : Int {
        return self?.hashValue ?? 0
    }
}

#endif
