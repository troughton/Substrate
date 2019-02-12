//
//  Collection+OutOfBounds.swift
//  Utilities
//
//  Created by Thomas Roughton on 11/02/19.
//

import Foundation

extension Collection {
    @inlinable
    public subscript(index: Index, default default: @autoclosure () -> Element) -> Element {
        guard self.indices.contains(index) else {
            return `default`()
        }
        return self[index]
    }
}
