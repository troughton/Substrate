import CFoundationExtras

extension NSRegularExpression {
    public struct Options : OptionSet {
        public let rawValue : UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        
        public static let caseInsensitive = Options(rawValue: 1 << 0) /* Match letters in the pattern independent of case. */
        public static let allowCommentsAndWhitespace = Options(rawValue: 1 << 1) /* Ignore whitespace and #-prefixed comments in the pattern. */
        public static let ignoreMetacharacters = Options(rawValue: 1 << 2) /* Treat the entire pattern as a literal string. */
        public static let dotMatchesLineSeparators = Options(rawValue: 1 << 3) /* Allow . to match any character, including line separators. */
        public static let anchorsMatchLines = Options(rawValue: 1 << 4) /* Allow ^ and $ to match the start and end of lines. */
        public static let useUnixLineSeparators = Options(rawValue: 1 << 5) /* Treat only \n as a line separator (otherwise, all standard line separators are used). */
        public static let useUnicodeWordBoundaries = Options(rawValue: 1 << 6) /* Use Unicode TR#29 to specify word boundaries (otherwise, traditional regular expression word boundaries are used). */
    }
}

extension NSRegularExpression {

    public struct MatchingOptions : OptionSet {
        public let rawValue : UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        public static let reportProgress = MatchingOptions(rawValue: 1 << 0) /* Call the block periodically during long-running match operations. */
        public static let reportCompletion = MatchingOptions(rawValue: 1 << 1) /* Call the block once after the completion of any matching. */
        public static let anchored = MatchingOptions(rawValue: 1 << 2) /* Limit matches to those at the start of the search range. */
        public static let withTransparentBounds = MatchingOptions(rawValue: 1 << 3) /* Allow matching to look beyond the bounds of the search range. */
        public static let withoutAnchoringBounds = MatchingOptions(rawValue: 1 << 4) /* Prevent ^ and $ from automatically matching the beginning and end of the search range. */
        internal static let OmitResult = MatchingOptions(rawValue: 1 << 13)
    }

    public struct MatchingFlags : OptionSet {
        public let rawValue : UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        public static let progress = MatchingFlags(rawValue: 1 << 0) /* Set when the block is called to report progress during a long-running match operation. */
        public static let completed = MatchingFlags(rawValue: 1 << 1) /* Set when the block is called after completion of any matching. */
        public static let hitEnd = MatchingFlags(rawValue: 1 << 2) /* Set when the current match operation reached the end of the search range. */
        public static let requiredEnd = MatchingFlags(rawValue: 1 << 3) /* Set when the current match depended on the location of the end of the search range. */
        public static let internalError = MatchingFlags(rawValue: 1 << 4) /* Set when matching failed due to an internal error. */
    }
}


/* NSTextCheckingType in this project is limited to regular expressions. */
extension NSTextCheckingResult {
    public struct CheckingType : OptionSet {
        public let rawValue: UInt64
        public init(rawValue: UInt64) { self.rawValue = rawValue }
        
        public static let RegularExpression = CheckingType(rawValue: 1 << 10) // regular expression matches
    }
}

open class NSTextCheckingResult: NSObject, NSCopying {
    
    public override init() {
        if type(of: self) == NSTextCheckingResult.self {
            NSRequiresConcreteImplementation()
        }
    }
    
    open class func regularExpressionCheckingResultWithRanges(_ ranges: NSRangePointer, count: Int, regularExpression: NSRegularExpression) -> NSTextCheckingResult {
        return _NSRegularExpressionNSTextCheckingResultResult(ranges: ranges, count: count, regularExpression: regularExpression)
    }
    
    open override func copy() -> Any {
        return copy(with: nil)
    }
    
    open func copy(with zone: NSZone? = nil) -> Any {
        return self
    }
    
    /* Mandatory properties, used with all types of results. */
    open var resultType: CheckingType { NSRequiresConcreteImplementation() }
    open var range: NSRange { return range(at: 0) }
    /* A result must have at least one range, but may optionally have more (for example, to represent regular expression capture groups).  The range at index 0 always matches the range property.  Additional ranges, if any, will have indexes from 1 to numberOfRanges-1. */
    open func range(at idx: Int) -> NSRange { NSRequiresConcreteImplementation() }
    open var regularExpression: NSRegularExpression? { return nil }
    open var numberOfRanges: Int { return 1 }
}

internal class _NSRegularExpressionNSTextCheckingResultResult : NSTextCheckingResult {
    var _ranges = [NSRange]()
    let _regularExpression: NSRegularExpression
    
    init(ranges: NSRangePointer, count: Int, regularExpression: NSRegularExpression) {
        _regularExpression = regularExpression
        super.init()
        let notFound = NSRange(location: NSNotFound,length: 0)
        for i in 0..<count {
            ranges[i].location == NSNotFound ? _ranges.append(notFound) : _ranges.append(ranges[i])
        }  
    }
    
    override var resultType: CheckingType { return .RegularExpression }
    override func range(at idx: Int) -> NSRange { return _ranges[idx] }
    override var numberOfRanges: Int { return _ranges.count }
    override var regularExpression: NSRegularExpression? { return _regularExpression }
}

extension NSTextCheckingResult {
    
    public func adjustingRanges(offset: Int) -> NSTextCheckingResult {
        let count = self.numberOfRanges
        var newRanges = [NSRange]()
        for idx in 0..<count {
           let currentRange = self.range(at: idx)
           if (currentRange.location == NSNotFound) {
              newRanges.append(currentRange)
           } else if ((offset > 0 && NSNotFound - currentRange.location <= offset) || (offset < 0 && currentRange.location < -offset)) {
              NSInvalidArgument(" \(offset) invalid offset for range {\(currentRange.location), \(currentRange.length)}")
           } else {
              newRanges.append(NSRange(location: currentRange.location + offset,length: currentRange.length))
           }
        }
        let result = NSTextCheckingResult.regularExpressionCheckingResultWithRanges(&newRanges, count: count, regularExpression: self.regularExpression!)
        return result
    }
}


public final class NSRegularExpression {
    public let pattern : String
    public let options : Options

    public init(pattern: String, options: Options = []) throws {
        self.pattern = pattern
        self.options = options
    }

    public func enumerateMatches(in string: String, options: NSRegularExpression.MatchingOptions = [], range: NSRange, using block: @escaping (NSTextCheckingResult?, NSRegularExpression.MatchingFlags, UnsafeMutablePointer<Bool>) -> Swift.Void) {
        NSUnimplemented()
    }

    // public func firstMatch(in string: String, options: NSRegularExpression.MatchingOptions = [], range: NSRange) -> NSTextCheckingResult? {
    //     var first: NSTextCheckingResult?
    //     enumerateMatches(in: string, options: options.subtracting(.reportProgress).subtracting(.reportCompletion), range: range) { (result: NSTextCheckingResult?, flags: NSRegularExpression.MatchingFlags, stop: UnsafeMutablePointer<Bool>) in
    //         first = result
    //         stop.pointee = true
    //     }
    //     return first
    // }

    // Hacky version that only sets whether the location was not NSNotFound.
    public func firstMatch(in string: String, options: NSRegularExpression.MatchingOptions = [], range: NSRange) -> NSTextCheckingResult? {
        let matched = string.withCString(encodedAs: UTF16.self) { string in
            pattern.withCString(encodedAs: UTF16.self) { pattern in
                return regexSearch(pattern, string);
            }
        }

        guard matched else {
            return nil
        }

        var range = NSRange(location: 0, length: 1)
        let result = _NSRegularExpressionNSTextCheckingResultResult(ranges: &range, count: 1, regularExpression: self)

        return result
    }

}