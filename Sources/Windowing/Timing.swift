import Dispatch

@_fixed_layout
public struct Timing {
    public static var deltaTime : Double = 0.0
    
    public static let launchTime = DispatchTime.now().uptimeNanoseconds
    
    public static var currentRealTime : Double {
        return Double(DispatchTime.now().uptimeNanoseconds) * 1e-9
    }
    
    public static var currentGameplayFrame : UInt64 = 0
    
    public static var timeSinceLaunch : Double {
        let launchTime = Timing.launchTime //Need to retrieve this first so it's less than the next DispatchTime.now() call.
        return Double(DispatchTime.now().uptimeNanoseconds - launchTime) * 1e-9
    }
}

