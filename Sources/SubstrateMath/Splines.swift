//
//  Splines.swift
//  swift4bug
//
//  Created by Thomas Roughton on 10/06/17.
//  Copyright © 2017 troughton. All rights reserved.
//

import RealModule

@frozen
public struct CubicPolynomial<V: BinaryFloatingPoint> {
    public let a : V
    public let b : V
    public let c : V
    public let d : V
    
    @inlinable
    public init(_ a: V, _ b: V, _ c: V, _ d: V) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }
    
    @inlinable
    public init(uniformPoints p0: V, _ p1: V, _ p2: V, _ p3: V) {
        self.init(p0, p2, (0.5 as V) * (p2 - p0), (0.5 as V) * (p3 - p1))
    }

    @inlinable
    public init(pointA: V, tangentA: V, pointB: V, tangentB: V) {
        let c0 = pointA
        let c1 = tangentA

        var c2 : V = -3 * pointA
        c2 += 3 * pointB
        c2 += -2 * tangentA
        c2 -= tangentB
        var c3 : V = 2 * pointA
        c3 -= (2 * pointB)
        c3 += tangentA + tangentB

        self.init(c3, c2, c1, c0)
    }

    @inlinable
    public init(nonUniformWithP0 p0: V, p1: V, p2: V, p3: V, dt0: V, dt1: V, dt2: V) {
        var t1 = (p1 - p0) / dt0
        t1 -= (p2 - p0) / (dt0 + dt1)
        t1 += (p2 - p1) / dt1

        var t2 = (p2 - p1) / dt1
        t2 -= (p3 - p1) / (dt1 + dt2)
        t2 += (p3 - p2) / dt2

        self.init(pointA: p1, tangentA: t1 * dt1, pointB: p2, tangentB: t2 * dt2)
    }

    @inlinable
    public init(centripetalCatmullRomWithPoints p0: V, _ p1: V, _ p2: V, _ p3: V) {
        var dt0 = abs(p1 - p0).squareRoot()
        var dt1 = abs(p2 - p1).squareRoot()
        var dt2 = abs(p3 - p2).squareRoot()

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

    @usableFromInline
    func calculateLength(iterations: Int = 100) -> V {
        let stride = 1.0 / V(iterations)

        var total = 0.0 as V

        for i in 0..<iterations {
            let lowT = V(i) * stride
            let highT = V(i + 1) * stride
            let low = self.evaluate(at: lowT)
            let high = self.evaluate(at: highT)

            total += abs(low - high)
        }

        return total
    }

    @inlinable
    public var length: V {
        return self.calculateLength()
    }

    @inlinable
    public func evaluate(at t: V) -> V {
        let t2 = t * t
        let t3 = t * t2

        var result = d + (c * t)
        result += b * t2
        result += a * t3
        return result
    }

    @inlinable
    public func evaluateDerivative(at t: V) -> V {
        let t2 = t * t
        var result = c
        result += 2 * b * t
        result += 3 * a * t2
        return result
    }

    @inlinable
    public func estimateInverse(`for` value: V) -> V {
        let minVal = self.evaluate(at: 0)
        let maxVal = self.evaluate(at: 1)

        var estimatedT = value - minVal
        estimatedT /= maxVal - minVal

        for _ in 0..<5 {
            estimatedT -= self.evaluate(at: estimatedT) / self.evaluateDerivative(at: estimatedT)
        }
        return estimatedT
    }
}


@frozen
public struct SIMDCubicPolynomial<V: SIMD> where V.Scalar: BinaryFloatingPoint & Real {
    public let a : V
    public let b : V
    public let c : V
    public let d : V
    
    @inlinable
    public init(_ a: V, _ b: V, _ c: V, _ d: V) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }
    
    @inlinable
    public init(uniformPoints p0: V, _ p1: V, _ p2: V, _ p3: V) {
        self.init(p0, p2, (0.5 as V.Scalar) * (p2 - p0), (0.5 as V.Scalar) * (p3 - p1))
    }

    @inlinable
    public init(pointA: V, tangentA: V, pointB: V, tangentB: V) {
        let c0 = pointA
        let c1 = tangentA

        var c2 : V = -3 * pointA
        c2 += 3 * pointB
        c2 += -2 * tangentA
        c2 -= tangentB
        var c3 : V = 2 * pointA
        c3 -= (2 * pointB)
        c3 += tangentA + tangentB

        self.init(c3, c2, c1, c0)
    }

    @inlinable
    public init(nonUniformWithP0 p0: V, p1: V, p2: V, p3: V, dt0: V.Scalar, dt1: V.Scalar, dt2: V.Scalar) {
        var t1 = (p1 - p0) / dt0
        t1 -= (p2 - p0) / (dt0 + dt1)
        t1 += (p2 - p1) / dt1

        var t2 = (p2 - p1) / dt1
        t2 -= (p3 - p1) / (dt1 + dt2)
        t2 += (p3 - p2) / dt2

        self.init(pointA: p1, tangentA: t1 * dt1, pointB: p2, tangentB: t2 * dt2)
    }

    @inlinable
    public init(centripetalCatmullRomWithPoints p0: V, _ p1: V, _ p2: V, _ p3: V) {
        var dt0 = V.Scalar.pow((p1 - p0).lengthSquared, 0.25)
        var dt1 = V.Scalar.pow((p2 - p1).lengthSquared, 0.25)
        var dt2 = V.Scalar.pow((p3 - p2).lengthSquared, 0.25)

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

    @usableFromInline
    func calculateLength(iterations: Int = 100) -> V.Scalar {
        let stride = 1.0 / V.Scalar(iterations)

        var total = 0.0 as V.Scalar

        for i in 0..<iterations {
            let lowT = V.Scalar(i) * stride
            let highT = V.Scalar(i + 1) * stride
            let low = self.evaluate(at: lowT)
            let high = self.evaluate(at: highT)

            total += (low - high).length
        }

        return total
    }

    @inlinable
    public var length: V.Scalar {
        return self.calculateLength()
    }

    @inlinable
    public func evaluate(at t: V.Scalar) -> V {
        let t2 = t * t
        let t3 = t * t2

        var result = d + (c * t)
        result += b * t2
        result += a * t3
        return result
    }

    @inlinable
    public func evaluateDerivative(at t: V.Scalar) -> V {
        let t2 = t * t
        var result = c
        result += 2 * b * t
        result += 3 * a * t2
        return result
    }

    @inlinable
    public func estimateInverse(`for` value: V.Scalar, component: Int) -> V.Scalar {
        let minVal = self.evaluate(at: 0)[component]
        let maxVal = self.evaluate(at: 1)[component]

        var estimatedT = value - minVal
        estimatedT /= maxVal - minVal

        for _ in 0..<5 {
            estimatedT -= self.evaluate(at: estimatedT)[component] / self.evaluateDerivative(at: estimatedT)[component]
        }
        return estimatedT
    }
}

public struct CatmullRomSpline<V: BinaryFloatingPoint> {
    public let polynomials : [CubicPolynomial<V>]
    public let polynomialLengths : [V]
    public let length : V
    
    @inlinable
    public init(points: [V]) {
        assert(points.count > 1)
        
        var polynomials = [CubicPolynomial<V>]()
        var polynomialLengths = [V]()
        
        // Construct a first and last point
        
        let p0 = 2 * points[0] - points[1]
        let p3 = (points.count > 2) ? points[2] : (2 * points[1] - points[0])
        
        let firstPoly = CubicPolynomial(centripetalCatmullRomWithPoints: p0, points[0], points[1], p3);
        polynomials.append(firstPoly)
        polynomialLengths.append(firstPoly.length)
        
        var i = 0
        while i < points.count - 3 {
            let poly = CubicPolynomial(centripetalCatmullRomWithPoints: points[i], points[i + 1], points[i + 2], points[i + 3])
            polynomials.append(poly)
            polynomialLengths.append(poly.length)
            i += 1
        }
        
        if points.count > 2 {
            let pN = 2 * points[points.count - 1] - points[points.count - 2]
            
            let lastPoly = CubicPolynomial(centripetalCatmullRomWithPoints: points[points.count - 3], points[points.count - 2], points[points.count - 1], pN)
            polynomials.append(lastPoly)
            polynomialLengths.append(lastPoly.length)
        }
        
        self.polynomials = polynomials
        self.polynomialLengths = polynomialLengths
        self.length = polynomialLengths.reduce(0.0, +)
    }
    
    @inlinable
    public func evaluate(at t: V) -> V {
        return self.evaluate(at: t, derivative: false)
    }
    
    @inlinable
    public func evaluateDerivative(at t: V) -> V {
        return self.evaluate(at: t, derivative: true)
    }
    
    @inlinable
    func evaluate(at t: V, derivative: Bool) -> V {
        let polyIndexAndT = self.polynomialIndexAndT(at: t)
        let index = polyIndexAndT.0
        let polyT = polyIndexAndT.1
        
        let poly = self.polynomials[index]
        
        if derivative {
            return poly.evaluateDerivative(at: polyT)
        } else {
            return poly.evaluate(at: polyT)
        }
    }
    
    @inlinable
    public func estimateValue(`for` value: V) -> V {
        let divisions = 200
        let step = 1.0 / V(divisions)
        
        var min = self.evaluate(at: 0)
        
        for i in 0...divisions {
            let max = self.evaluate(at: V(i) * step)
            
            if min < value && max > value {
                return (min + max) * 0.5
            } else {
                min = max
            }
        }
        
        return min
    }
    
    @inlinable
    public func polynomialIndexAndT(at t: V) -> (Int, V) {
        let length = self.length * t

        var lengthSoFar = 0.0 as V
        var index = 0
        var polyT = 0.0 as V

        while index < self.polynomials.count {
            let polyLength = self.polynomialLengths[index]
            
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
    
}

public struct SIMDCatmullRomSpline<V: SIMD> where V.Scalar: BinaryFloatingPoint & Real {
    public let polynomials : [SIMDCubicPolynomial<V>]
    public let polynomialLengths : [V.Scalar]
    public let length : V.Scalar
    
    @inlinable
    public init(points: [V]) {
        assert(points.count > 1)
        
        var polynomials = [SIMDCubicPolynomial<V>]()
        var polynomialLengths = [V.Scalar]()
        
        //Construct a first and last point
        
        let p0 = 2 * points[0] - points[1]
        let p3 = (points.count > 2) ? points[2] : (2 * points[1] - points[0])
        
        let firstPoly = SIMDCubicPolynomial(centripetalCatmullRomWithPoints: p0, points[0], points[1], p3);
        polynomials.append(firstPoly)
        polynomialLengths.append(firstPoly.length)
        
        var i = 0
        while i < points.count - 3 {
            let poly = SIMDCubicPolynomial(centripetalCatmullRomWithPoints: points[i], points[i + 1], points[i + 2], points[i + 3])
            polynomials.append(poly)
            polynomialLengths.append(poly.length)
            i += 1
        }
        
        if points.count > 2 {
            let pN = 2 * points[points.count - 1] - points[points.count - 2]
            
            let lastPoly = SIMDCubicPolynomial(centripetalCatmullRomWithPoints: points[points.count - 3], points[points.count - 2], points[points.count - 1], pN)
            polynomials.append(lastPoly)
            polynomialLengths.append(lastPoly.length)
        }
        
        self.polynomials = polynomials
        self.polynomialLengths = polynomialLengths
        self.length = polynomialLengths.reduce(0.0, +)
    }
    
    @inlinable
    public func evaluate(at t: V.Scalar) -> V {
        return self.evaluate(at: t, derivative: false)
    }
    
    @inlinable
    public func evaluateDerivative(at t: V.Scalar) -> V {
        return self.evaluate(at: t, derivative: true)
    }
    
    @inlinable
    func evaluate(at t: V.Scalar, derivative: Bool) -> V {
        let polyIndexAndT = self.polynomialIndexAndT(at: t)
        let index = polyIndexAndT.0
        let polyT = polyIndexAndT.1
        
        let poly = self.polynomials[index]
        
        if derivative {
            return poly.evaluateDerivative(at: polyT)
        } else {
            return poly.evaluate(at: polyT)
        }
    }
    
    @inlinable
    public func estimateValue(`for` value: V.Scalar, component: Int) -> V {
        let divisions = 200
        let step = 1.0 / V.Scalar(divisions)
        
        var min = self.evaluate(at: 0)
        
        for i in 0...divisions {
            let max = self.evaluate(at: V.Scalar(i) * step)
            
            if min[component] < value && max[component] > value {
                return (min + max) * 0.5
            } else {
                min = max
            }
        }
        
        return min
    }
    
    @inlinable
    public func polynomialIndexAndT(at t: V.Scalar) -> (Int, V.Scalar) {
        let length = self.length * t

        var lengthSoFar = 0.0 as V.Scalar
        var index = 0
        var polyT = 0.0 as V.Scalar

        while index < self.polynomials.count {
            let polyLength = self.polynomialLengths[index]
            
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
}
