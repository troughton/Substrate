
extension Stream {
    public struct PropertyKey : RawRepresentable, Equatable, Hashable {
        public private(set) var rawValue: String
        
        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }
        
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
        
        public var hashValue: Int {
            return rawValue.hashValue
        }
        
        public static func ==(lhs: Stream.PropertyKey, rhs: Stream.PropertyKey) -> Bool {
            return lhs.rawValue == rhs.rawValue
        }
    }
    
    public enum Status : UInt {
        
        case notOpen
        case opening
        case open
        case reading
        case writing
        case atEnd
        case closed
        case error
    }

    public struct Event : OptionSet {
        public let rawValue : UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        // NOTE: on darwin these are vars
        public static let openCompleted = Event(rawValue: 1 << 0)
        public static let hasBytesAvailable = Event(rawValue: 1 << 1)
        public static let hasSpaceAvailable = Event(rawValue: 1 << 2)
        public static let errorOccurred = Event(rawValue: 1 << 3)
        public static let endEncountered = Event(rawValue: 1 << 4)
    }
}



// Stream is an abstract class encapsulating the common API to InputStream and OutputStream.
// Subclassers of InputStream and OutputStream must also implement these methods.
open class Stream: NSObject {

    public override init() {

    }
    
    open func open() {
        NSRequiresConcreteImplementation()
    }
    
    open func close() {
        NSRequiresConcreteImplementation()
    }
    
    open weak var delegate: StreamDelegate?
    // By default, a stream is its own delegate, and subclassers of InputStream and OutputStream must maintain this contract. [someStream setDelegate:nil] must restore this behavior. As usual, delegates are not retained.
    
    open func property(forKey key: PropertyKey) -> AnyObject? {
        NSUnimplemented()
    }
    
    open func setProperty(_ property: AnyObject?, forKey key: PropertyKey) -> Bool {
        NSUnimplemented()
    }
    
    open var streamStatus: Status {
        NSRequiresConcreteImplementation()
    }
    
    open var streamError: Error? {
        NSRequiresConcreteImplementation()
    }
}

// InputStream is an abstract class representing the base functionality of a read stream.
// Subclassers are required to implement these methods.
open class InputStream: Stream {

    private var currentIndex = 0
    private let data : Data
        
    @discardableResult public func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        let length = min(len, self.data.count - self.currentIndex)
        
        let bufferPtr = UnsafeMutableBufferPointer(start: buffer, count: len)
        let copied = self.data.copyBytes(to: bufferPtr, from: currentIndex..<currentIndex + length)
        
        self.currentIndex += length
        return copied
    }
        
    public init(data: Data) {
        self.data = data
        super.init()
    }
    
    // returns in O(1) a pointer to the buffer in 'buffer' and by reference in 'len' how many bytes are available. This buffer is only valid until the next stream operation. Subclassers may return NO for this if it is not appropriate for the stream type. This may return NO if the buffer is not available.
    open func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, length len: UnsafeMutablePointer<Int>) -> Bool {
        buffer.pointee = data._backing.mutableBytes?.assumingMemoryBound(to: UInt8.self)
        len.pointee = data.count - self.currentIndex
        return true
    }
    
    // returns YES if the stream has bytes available or if it impossible to tell without actually doing the read.
    open var hasBytesAvailable: Bool {
        return self.currentIndex < data.count
    }
    
    public convenience init?(url: URL) {       
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    public convenience init?(fileAtPath path: String) {
        self.init(url: URL(fileURLWithPath: path))
    }

    open override func open() {
    }
    
    open override func close() {
    }
    
    open override var streamStatus: Status {
        NSUnimplemented()
    }
    
    open override var streamError: Error? {
        return nil
    }
}

// OutputStream is an abstract class representing the base functionality of a write stream.
// Subclassers are required to implement these methods.
// Currently this is left as named OutputStream due to conflicts with the standard library's text streaming target protocol named OutputStream (which ideally should be renamed)
open class OutputStream : Stream {
    
    // writes the bytes from the specified buffer to the stream up to len bytes. Returns the number of bytes actually written.
    open func write(_ buffer: UnsafePointer<UInt8>, maxLength len: Int) -> Int {
        NSUnimplemented()
    }
    
    // returns YES if the stream can be written to or if it is impossible to tell without actually doing the write.
    open var hasSpaceAvailable: Bool {
        NSUnimplemented()
    }
    // NOTE: on Darwin this is     'open class func toMemory() -> Self'
    required public init(toMemory: ()) {
    }

    // TODO: this should use the real buffer API
    public init(toBuffer buffer: UnsafeMutablePointer<UInt8>, capacity: Int) {
        NSUnimplemented()
    }
    
    public init?(url: URL, append shouldAppend: Bool) {
        NSUnimplemented()
    }
    
    public convenience init?(toFileAtPath path: String, append shouldAppend: Bool) {
        self.init(url: URL(fileURLWithPath: path), append: shouldAppend)
    }
    
    open override func open() {
        NSUnimplemented()
    }
    
    open override func close() {
        NSUnimplemented()
    }
    
    open override var streamStatus: Status {
        NSUnimplemented()
    }
    
    open class func toMemory() -> Self {
        return self.init(toMemory: ())
    }
    
    open override func property(forKey key: PropertyKey) -> AnyObject? {
        NSUnimplemented()
    }
    
    open  override func setProperty(_ property: AnyObject?, forKey key: PropertyKey) -> Bool {
        NSUnimplemented()
    }
    
    open override var streamError: Error? {
        NSUnimplemented()
    }
}

// Discussion of this API is ongoing for its usage of AutoreleasingUnsafeMutablePointer
#if false
extension Stream {
    open class func getStreamsToHost(withName hostname: String, port: Int, inputStream: AutoreleasingUnsafeMutablePointer<InputStream?>?, outputStream: AutoreleasingUnsafeMutablePointer<OutputStream?>?) {
        NSUnimplemented()
    }
}

extension Stream {
    open class func getBoundStreams(withBufferSize bufferSize: Int, inputStream: AutoreleasingUnsafeMutablePointer<InputStream?>?, outputStream: AutoreleasingUnsafeMutablePointer<OutputStream?>?) {
        NSUnimplemented()
    }
}
#endif

extension StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) { }
}

public protocol StreamDelegate : class {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event)
}

// MARK: -
extension Stream.PropertyKey {
    public static let socketSecurityLevelKey = Stream.PropertyKey(rawValue: "kCFStreamPropertySocketSecurityLevel")
    public static let socksProxyConfigurationKey = Stream.PropertyKey(rawValue: "kCFStreamPropertySOCKSProxy")
    public static let dataWrittenToMemoryStreamKey = Stream.PropertyKey(rawValue: "kCFStreamPropertyDataWritten")
    public static let fileCurrentOffsetKey = Stream.PropertyKey(rawValue: "kCFStreamPropertyFileCurrentOffset")
    public static let networkServiceType = Stream.PropertyKey(rawValue: "kCFStreamNetworkServiceType")
}

// MARK: -
public struct StreamSocketSecurityLevel : RawRepresentable, Equatable, Hashable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    public var hashValue: Int {
        return rawValue.hashValue
    }
    public static func ==(lhs: StreamSocketSecurityLevel, rhs: StreamSocketSecurityLevel) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
}
extension StreamSocketSecurityLevel {
    public static let none = StreamSocketSecurityLevel(rawValue: "kCFStreamSocketSecurityLevelNone")
    public static let ssLv2 = StreamSocketSecurityLevel(rawValue: "NSStreamSocketSecurityLevelSSLv2")
    public static let ssLv3 = StreamSocketSecurityLevel(rawValue: "NSStreamSocketSecurityLevelSSLv3")
    public static let tlSv1 = StreamSocketSecurityLevel(rawValue: "kCFStreamSocketSecurityLevelTLSv1")
    public static let negotiatedSSL = StreamSocketSecurityLevel(rawValue: "kCFStreamSocketSecurityLevelNegotiatedSSL")
}


// MARK: -
public struct StreamSOCKSProxyConfiguration : RawRepresentable, Equatable, Hashable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    public var hashValue: Int {
        return rawValue.hashValue
    }
    public static func ==(lhs: StreamSOCKSProxyConfiguration, rhs: StreamSOCKSProxyConfiguration) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
}
extension StreamSOCKSProxyConfiguration {
    public static let hostKey = StreamSOCKSProxyConfiguration(rawValue: "NSStreamSOCKSProxyKey")
    public static let portKey = StreamSOCKSProxyConfiguration(rawValue: "NSStreamSOCKSPortKey")
    public static let versionKey = StreamSOCKSProxyConfiguration(rawValue: "kCFStreamPropertySOCKSVersion")
    public static let userKey = StreamSOCKSProxyConfiguration(rawValue: "kCFStreamPropertySOCKSUser")
    public static let passwordKey = StreamSOCKSProxyConfiguration(rawValue: "kCFStreamPropertySOCKSPassword")
}


// MARK: -
public struct StreamSOCKSProxyVersion : RawRepresentable, Equatable, Hashable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    public var hashValue: Int {
        return rawValue.hashValue
    }
    public static func ==(lhs: StreamSOCKSProxyVersion, rhs: StreamSOCKSProxyVersion) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
}
extension StreamSOCKSProxyVersion {
    public static let version4 = StreamSOCKSProxyVersion(rawValue: "kCFStreamSocketSOCKSVersion4")
    public static let version5 = StreamSOCKSProxyVersion(rawValue: "kCFStreamSocketSOCKSVersion5")
}


// MARK: - Supported network service types
public struct StreamNetworkServiceTypeValue : RawRepresentable, Equatable, Hashable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    public var hashValue: Int {
        return rawValue.hashValue
    }
    public static func ==(lhs: StreamNetworkServiceTypeValue, rhs: StreamNetworkServiceTypeValue) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
}
extension StreamNetworkServiceTypeValue {
    public static let voIP = StreamNetworkServiceTypeValue(rawValue: "kCFStreamNetworkServiceTypeVoIP")
    public static let video = StreamNetworkServiceTypeValue(rawValue: "kCFStreamNetworkServiceTypeVideo")
    public static let background = StreamNetworkServiceTypeValue(rawValue: "kCFStreamNetworkServiceTypeBackground")
    public static let voice = StreamNetworkServiceTypeValue(rawValue: "kCFStreamNetworkServiceTypeVoice")
    public static let callSignaling = StreamNetworkServiceTypeValue(rawValue: "kCFStreamNetworkServiceTypeVoice")
}




// MARK: - Error Domains
// String constants for error domains.
public let NSStreamSocketSSLErrorDomain: String = "NSStreamSocketSSLErrorDomain"
// SSL errors are to be interpreted via <Security/SecureTransport.h>
public let NSStreamSOCKSErrorDomain: String = "NSStreamSOCKSErrorDomain"

