//
//  File.swift
//  
//
//  Created by Thomas Roughton on 10/01/23.
//

import Foundation

@resultBuilder
public struct ResourceUsageListBuilder {
    /// The type of individual statement expressions in the transformed function,
    /// which defaults to Component if buildExpression() is not provided.
    public typealias Expression = ResourceUsage?
    
    /// The type of a partial result, which will be carried through all of the
    /// build methods.
    public typealias Component = [ResourceUsage]
    
    public typealias FinalResult = [ResourceUsage]
    
    /// Required by every result builder to build combined results from
    /// statement blocks.
    @inlinable public static func buildBlock(_ components: Component...) -> Component {
        return buildArray(components)
    }
    
    /// If declared, provides contextual type information for statement
    /// expressions to translate them into partial results.
    @inlinable public static func buildExpression(_ expression: Expression) -> Component {
        return expression.map { [$0] } ?? []
    }
    
    /// Enables support for `if` statements that do not have an `else`.
    @inlinable public static func buildOptional(_ component: Component?) -> Component {
        return component.map { $0 } ?? []
    }
    
    /// With buildEither(second:), enables support for 'if-else' and 'switch'
    /// statements by folding conditional results into a single result.
    @inlinable public static func buildEither(first component: Component) -> Component {
        return component
    }
    
    /// With buildEither(first:), enables support for 'if-else' and 'switch'
    /// statements by folding conditional results into a single result.
    @inlinable public static func buildEither(second component: Component) -> Component {
        return component
    }
    
    /// Enables support for 'for..in' loops by combining the
    /// results of all iterations into a single result.
    @inlinable public static func buildArray(_ components: [Component]) -> Component {
        var result = [ResourceUsage]()
        for component in components {
            if result.isEmpty {
                result = component
            } else {
                result.append(contentsOf: component)
            }
        }
        return result
    }
    
    /// If declared, this will be called on the partial result of an 'if
    /// #available' block to allow the result builder to erase type
    /// information.
    @inlinable public static func buildLimitedAvailability(_ component: Component) -> Component {
        return component
    }
    
    /// If declared, this will be called on the partial result from the outermost
    /// block statement to produce the final returned result.
    @inlinable public static func buildFinalResult(_ component: Component) -> FinalResult {
        return component
    }
}
