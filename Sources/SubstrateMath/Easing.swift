//
//  easing.swift
//  org.SwiftGFX.SwiftMath
//
//  Created by Andrey Volodin on 03.09.16.
//
//

import RealModule

// MARK: Linear
public func linear(_ time: Float) -> Float {
    return time
}

// MARK: Sine Ease
public func sineEaseIn(_ time: Float) -> Float {
    return -Float.cos(time * Float.pi * 0.5) + 1
}

public func sineEaseOut(_ time: Float) -> Float {
    return Float.sin(time *  Float.pi * 0.5)
}

public func sineEaseInOut(_ time: Float) -> Float {
    return -0.5 * (Float.cos(Float.pi * time) - 1)
}

// MARK: Quad Ease
public func quadEaseIn(_ time: Float) -> Float {
    return time * time
}

public func quadEaseOut(_ time: Float) -> Float {
    return -time * (time - 2)
}

public func quadEaseInOut(_ time: Float) -> Float {
    var time = time * 2
    if time < 1 {
        return 0.5 * time * time
    }
    time -= 1
    return -0.5 * (time * (time - 2) - 1)
}

// MARK: Cubic Ease
public func cubicEaseIn(_ time: Float) -> Float {
    return time * time * time
}

public func cubicEaseOut(_ time: Float) -> Float {
    var time = time
    time -= 1
    return (time * time * time + 1)
}

public func cubicEaseInOut(_ time: Float) -> Float {
    var time = time * 2
    if time < 1 {
        return 0.5 * time * time * time
    }
    time -= 2
    return 0.5 * (time * time * time + 2)
}

// MARK: Quart Ease
public func quartEaseIn(_ time: Float) -> Float {
    return time * time * time * time
}

public func quartEaseOut(_ time: Float) -> Float {
    var time = time
    time -= 1
    return -(time * time * time * time - 1)
}

public func quartEaseInOut(_ time: Float) -> Float {
    var time = time
    time = time * 2
    if time < 1 {
        return 0.5 * time * time * time * time
    }
    time -= 2
    return -0.5 * (time * time * time * time - 2)
}

// MARK: Quint Ease
public func quintEaseIn(_ time: Float) -> Float {
    return time * time * time * time * time
}

public func quintEaseOut(_ time: Float) -> Float {
    var time = time
    time -= 1
    return (time * time * time * time * time + 1)
}

public func quintEaseInOut(_ time: Float) -> Float {
    var time = time * 2
    if time < 1 {
        return 0.5 * time * time * time * time * time
    }
    time -= 2
    return 0.5 * (time * time * time * time * time + 2)
}

// MARK: Expo Ease
public func expoEaseIn(_ time: Float) -> Float {
    return time == 0 ? 0 : .pow(2, 10 * (time / 1 - 1)) - 1 * 0.001
}

public func expoEaseOut(_ time: Float) -> Float {
    return time == 1 ? 1 : (-.pow(2, -10 * time / 1) + 1)
}

public func expoEaseInOut(_ time: Float) -> Float {
    var time = time
    time /= 0.5
    if time < 1 {
        time = 0.5 * .pow(2, 10 * (time - 1))
    }
    else {
        time = 0.5 * (-.pow(2, -10 * (time - 1)) + 2)
    }
    return time
}

// MARK: Circ Ease
public func circEaseIn(_ time: Float) -> Float {
    return -((1 - time * time).squareRoot() - 1)
}

public func circEaseOut(_ time: Float) -> Float {
    var time = time
    time = time - 1
    return (1 - time * time).squareRoot()
}

public func circEaseInOut(_ time: Float) -> Float {
    var time = time
    time = time * 2
    if time < 1 {
        return -0.5 * ((1 - time * time).squareRoot() - 1)
    }
    time -= 2
    return 0.5 * ((1 - time * time).squareRoot() + 1)
}

// MARK: Elastic Ease
public func elasticEaseIn(_ time: Float, period: Float) -> Float {
    var time = time
    var newT: Float = 0
    if time == 0 || time == 1 {
        newT = time
    }
    else {
        let s: Float = period / 4
        time = time - 1
        newT = -.pow(2, 10 * time) * .sin((time - s) * 2 * Float.pi / period)
    }
    return newT
}

public func elasticEaseOut(_ time: Float, period: Float) -> Float {
    var newT: Float = 0
    if time == 0 || time == 1 {
        newT = time
    }
    else {
        let s: Float = period / 4
        newT = .pow(2, -10 * time) * .sin((time - s) * 2 * Float.pi / period) + 1
    }
    return newT
}

public func elasticEaseInOut(_ time: Float, period: Float) -> Float {
    var time = time
    var period = period
    var newT: Float = 0
    if time == 0 || time == 1 {
        newT = time
    }
    else {
        time = time * 2
        if period == 0.0 {
            period = 0.3 * 1.5
        }
        let s: Float = period / 4
        time = time - 1
        if time < 0 {
            newT = -0.5 * .pow(2, 10 * time) * .sin((time - s) * 2 * Float.pi / period)
        }
        else {
            newT = .pow(2, -10 * time) * .sin((time - s) * 2 * Float.pi / period) * 0.5 + 1
        }
    }
    return newT
}


// MARK: Back Ease
public func backEaseIn(_ time: Float, overshoot: Float) -> Float {
    let overshoot: Float = 1.70158
    return time * time * ((overshoot + 1) * time - overshoot)
}

public func backEaseOut(_ time: Float, overshoot: Float) -> Float {
    let overshoot: Float = 1.70158
    var time = time
    time = time - 1
    return time * time * ((overshoot + 1) * time + overshoot) + 1
}

public func backEaseInOut(_ time: Float, overshoot: Float) -> Float {
    let overshoot: Float = 1.70158 * 1.525
    var time = time
    time = time * 2
    if time < 1 {
        return (time * time * ((overshoot + 1) * time - overshoot)) / 2
    }
    else {
        time = time - 2
        time *= time
        time *= (overshoot + 1) * time + overshoot
        return time / 2 + 1
    }
}


// MARK: Bounce Ease
public func bounceTime(_ time: Float) -> Float {
    var time = time
    if time < 1 / 2.75 {
        return 7.5625 * time * time
    }
    else if time < 2 / 2.75 {
        time -= 1.5 / 2.75
        return 7.5625 * time * time + 0.75
    }
    else if time < 2.5 / 2.75 {
        time -= 2.25 / 2.75
        return 7.5625 * time * time + 0.9375
    }
    
    time -= 2.625 / 2.75
    return 7.5625 * time * time + 0.984375
}

public func bounceEaseIn(_ time: Float) -> Float {
    return 1 - bounceTime(1 - time)
}

public func bounceEaseOut(_ time: Float) -> Float {
    return bounceTime(time)
}

public func bounceEaseInOut(_ time: Float) -> Float {
    var time = time
    var newT: Float = 0
    if time < 0.5 {
        time = time * 2
        newT = (1 - bounceTime(1 - time)) * 0.5
    }
    else {
        newT = bounceTime(time * 2 - 1) * 0.5 + 0.5
    }
    return newT
}


// MARK: Custom Ease
public func customEase(_ time: Float, easingParam: [Float]) -> Float {
    guard easingParam.count == 8 else {
        print("WARNING: Wrong easing param")
        return time
    }
    let tt: Float = 1 - time
    return easingParam[1] * tt * tt * tt + 3 * easingParam[3] * time * tt * tt + 3 * easingParam[5] * time * time * tt + easingParam[7] * time * time * time
}

public func easeIn(_ time: Float, rate: Float) -> Float {
    return .pow(time, rate)
}

public func easeOut(_ time: Float, rate: Float) -> Float {
    return .pow(time, 1 / rate)
}

public func easeInOut(_ time: Float, rate: Float) -> Float {
    var time = time
    time *= 2
    if time < 1 {
        return 0.5 * .pow(time, rate)
    }
    else {
        return (1.0 - 0.5 * .pow(2 - time, rate))
    }
}

public func quadraticIn(_ time: Float) -> Float {
    return time * time
}

public func quadraticOut(_ time: Float) -> Float {
    return -time * (time - 2)
}

public func quadraticInOut(_ time: Float) -> Float {
    var time = time
    var resultTime: Float = time
    time = time * 2
    if time < 1 {
        resultTime = time * time * 0.5
    }
    else {
        time -= 1
        resultTime = -0.5 * (time * (time - 2) - 1)
    }
    return resultTime
}
