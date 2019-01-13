//
//  Splines.swift
//  swift4bug
//
//  Created by Thomas Roughton on 10/06/17.
//  Copyright © 2017 troughton. All rights reserved.
//

import Foundation

public struct CubicPolynomial<T: Vector> {
    private var _length : Float! = nil
    public var length : Float {
        return _length
    }
    
    public let a : T
    public let b : T
    public let c : T
    public let d : T
    
    public init(_ a: T, _ b: T, _ c: T, _ d: T) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self._length = self.calculateLength()
    }
    
    public init(pointA: T, tangentA: T, pointB: T, tangentB: T) {
        let c0 = pointA
        let c1 = tangentA
        
        var c2 = -3 * pointA + 3 * pointB
        c2 += -2 * tangentA - tangentB
        var c3 = (2 * pointA)
        c3 -= (2 * pointB)
        c3 += tangentA + tangentB
        
        self.init(c3, c2, c1, c0)
    }
    
    public init(uniformPoints p0: T, _ p1: T, _ p2: T, _ p3: T) {
        self.init(p0, p2, 0.5 * (p2 - p0), 0.5 * (p3 - p1))
    }
    
    public init(nonUniformWithP0 p0: T, p1: T, p2: T, p3: T, dt0: Float, dt1: Float, dt2: Float) {
        var t1 = (p1 - p0) / dt0
        t1 -= (p2 - p0) / (dt0 + dt1)
        t1 += (p2 - p1) / dt1
        
        var t2 = (p2 - p1) / dt1
        t2 -= (p3 - p1) / (dt1 + dt2)
        t2 += (p3 - p2) / dt2
        
        self.init(pointA: p1, tangentA: t1 * dt1, pointB: p2, tangentB: t2 * dt2)
    }
    
    public init(centripetalCatmullRomWithPoints p0: T, _ p1: T, _ p2: T, _ p3: T) {
        var dt0 = powf((p1 - p0).lengthSquared, 0.25)
        var dt1 = powf((p2 - p1).lengthSquared, 0.25)
        var dt2 = powf((p3 - p2).lengthSquared, 0.25)
        
        if dt1 < 1e-4 {
            dt1 = 1.0
        }
        
        if dt0 < 1e-4 {
            dt0 = dt1
        }
        
        if dt2 < 1e-4 {
            dt2 = dt1
        }
        
        self.init(nonUniformWithP0: p0, p1: p1, p2: p2, p3: p3, dt0: dt0, dt1: dt1, dt2: dt2)
    }
    
    private func calculateLength(iterations: Int = 100) -> Float {
        let stride = 1.0 / Float(iterations)
        
        var total = 0.0 as Float
        
        for i in 0..<iterations {
            let lowT = Float(i) * stride
            let highT = Float(i + 1) * stride
            let low = self.evaluate(at: lowT)
            let high = self.evaluate(at: highT)
            
            total += (low - high).length
        }
        
        return total
    }
    
    public func evaluate(at t: Float) -> T {
        let t2 = t * t
        let t3 = t * t2
        
        var result = d + (c * t)
        result += b * t2
        result += a * t3
        return result
    }
    
    public func evaluateDerivative(at t: Float) -> T {
        let t2 = t * t
        var result = c
        result += 2 * b * t
        result += 3 * a * t2
        return result
    }
    
    public func estimateInverse(`for` value: Float, component: Int) -> Float {
        let minVal = self.evaluate(at: 0)[component]
        let maxVal = self.evaluate(at: 1)[component]
        
        var estimatedT = (value - minVal) / (maxVal - minVal)
        for _ in 0..<5 {
            estimatedT = estimatedT - self.evaluate(at: estimatedT)[component]/self.evaluateDerivative(at: estimatedT)[component]
        }
        return estimatedT
    }
}

public struct CatmullRomSpline<T : Vector> {
    public let polynomials : [CubicPolynomial<T>]
    public let length : Float
    
    public init(points: [T]) {
        assert(points.count > 1)
        
        var polynomials = [CubicPolynomial<T>]()
        var length = 0.0 as Float
        
        //Construct a first and last point
        
        let p0 = 2 * points[0] - points[1]
        let p3 = (points.count > 2) ? points[2] : (2 * points[1] - points[0])
        
        let firstPoly = CubicPolynomial(centripetalCatmullRomWithPoints: p0, points[0], points[1], p3);
        polynomials.append(firstPoly)
        length += firstPoly.length
        
        var i = 0
        while i < points.count - 3 {
            let poly = CubicPolynomial(centripetalCatmullRomWithPoints: points[i], points[i + 1], points[i + 2], points[i + 3]);
                polynomials.append(poly)
                length += poly.length
            i += 1
        }
        
        
        if points.count > 2 {
            let pN = 2 * points.last! - points[points.count - 2]
            
            let lastPoly = CubicPolynomial(centripetalCatmullRomWithPoints: points[points.count - 3], points[points.count - 2], points.last!, pN)
            polynomials.append(lastPoly)
            length += lastPoly.length
        }
        
        self.polynomials = polynomials
        self.length = length
    }
    
    public func evaluate(at t: Float) -> T {
        return self.evaluate(at: t, derivative: false)
    }
    
    public func evaluateDerivative(at t: Float) -> T {
        return self.evaluate(at: t, derivative: true)
    }
    
    private func evaluate(at t: Float, derivative: Bool) -> T {
        let polyIndexAndT = self.polynomialIndexAndT(at: t)
        let index = polyIndexAndT.0
        let polyT = polyIndexAndT.1
        
        let poly = self.polynomials[index]
        
        if derivative {
            return poly.evaluate(at: polyT)
        } else {
            return poly.evaluate(at: polyT)
        }
    }
    
    public func polynomialIndexAndT(at t: Float) -> (Int, Float) {
        let length = self.length * t

        var lengthSoFar = 0.0 as Float
        var index : Int = 0
        var polyT : Float = 0.0

        while index < self.polynomials.count {
            let polyLength = self.polynomials[index].length
            
            let nextTotalLength = lengthSoFar + polyLength;
            if nextTotalLength >= length {
                polyT = (length - lengthSoFar) / polyLength;
                break;
            } else {
                lengthSoFar += polyLength;
                index += 1;
            }
        }
        
        return (index, polyT)
    }
    
    public func estimateValue(`for` value: Float, component: Int) -> T {
        let divisions = 200
        let step = 1.0 / Float(divisions)
        
        var min = self.evaluate(at: 0)
        
        for i in 0...divisions {
            let max = self.evaluate(at: Float(i) * step)
            
            if min[component] < value && max[component] > value {
                return (min + max) * 0.5
            } else {
                min = max
            }
        }
        
        return min
    }
}
