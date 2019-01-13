//
//  File.swift
//  org.SwiftGFX.SwiftMath
//
//  Created by Andrey Volodin on 10.08.16.
//
//

public typealias Point = Vector2f
public typealias p2d = Point

extension Rect {
    @inlinable
    public nonmutating func contains(point: Point) -> Bool {
        let x = point.x
        let y = point.y
        return x >= minX && x <= maxX && y >= minY && y <= maxY
    }
}
