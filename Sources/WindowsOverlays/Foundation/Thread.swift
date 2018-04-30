import CDispatch

private let mainQueueKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
private let mainQueueValue = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

public enum Thread {

    private static let _staticInit : Bool = {
        // Associate a key-value pair with the main queue
        dispatch_queue_set_specific(
            dispatch_get_main_queue(), 
            mainQueueKey, 
            mainQueueValue, 
            nil
        )
        return true
    }()

    public static var isMainThread : Bool {
        _ = Thread._staticInit
        return dispatch_get_specific(mainQueueKey) == mainQueueValue
    }
}