//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// Random access for String.UTF16View, only when Foundation is
// imported.  Making this API dependent on Foundation decouples the
// Swift core from a UTF16 representation.
extension String.UTF16View.Index {
    public func advanced(by n: Int) -> String.UTF16View.Index {
        return String.UTF16View.Index(encodedOffset: encodedOffset.advanced(by: n))
    }
}

extension String {
    public struct CompareOptions : OptionSet {
        public let rawValue : UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        
        public static let caseInsensitive = CompareOptions(rawValue: 1)
        public static let literal = CompareOptions(rawValue: 2)
        public static let backwards = CompareOptions(rawValue: 4)
        public static let anchored = CompareOptions(rawValue: 8)
        public static let numeric = CompareOptions(rawValue: 64)
        public static let diacriticInsensitive = CompareOptions(rawValue: 128)
        public static let widthInsensitive = CompareOptions(rawValue: 256)
        public static let forcedOrdering = CompareOptions(rawValue: 512)
        public static let regularExpression = CompareOptions(rawValue: 1024)
    }
}

extension StringProtocol where Index == String.Index {

    // self can be a Substring so we need to subtract/add this offset when
    // passing _ns to the Foundation APIs. Will be 0 if self is String.
    @_inlineable
    @_versioned
    internal var _substringOffset: Int {
        return self.startIndex.encodedOffset
    }

    @_inlineable
    @_versioned
    internal func _toRelativeNSRange(_ r: Range<String.Index>) -> NSRange {
        return NSRange(
        location: r.lowerBound.encodedOffset - _substringOffset,
        length: r.upperBound.encodedOffset - r.lowerBound.encodedOffset)
    }


  /// Return an `Index` corresponding to the given offset in our UTF-16
  /// representation.
  func _index(_ utf16Index: Int) -> Index {
    return Index(encodedOffset: utf16Index + _substringOffset)
  }
  
  /// Return a `Range<Index>` corresponding to the given `NSRange` of
  /// our UTF-16 representation.
  func _range(_ r: NSRange) -> Range<Index> {
    return _index(r.location)..<_index(r.location + r.length)
  }

  /// Invoke `body` on an `Int` buffer.  If `index` was converted from
  /// non-`nil`, convert the buffer to an `Index` and write it into the
  /// memory referred to by `index`
  func _withOptionalOutParameter<Result>(
    _ index: UnsafeMutablePointer<Index>?,
    _ body: (UnsafeMutablePointer<Int>?) -> Result
  ) -> Result {
    var utf16Index: Int = 0
    let result = (index != nil ? body(&utf16Index) : body(nil))
    index?.pointee = _index(utf16Index)
    return result
  }

  /// Invoke `body` on an `NSRange` buffer.  If `range` was converted
  /// from non-`nil`, convert the buffer to a `Range<Index>` and write
  /// it into the memory referred to by `range`
  func _withOptionalOutParameter<Result>(
    _ range: UnsafeMutablePointer<Range<Index>>?,
    _ body: (UnsafeMutablePointer<NSRange>?) -> Result
  ) -> Result {
    var nsRange = NSRange(location: 0, length: 0)
    let result = (range != nil ? body(&nsRange) : body(nil))
    range?.pointee = self._range(nsRange)
    return result
  }

    public func hasPrefix(_ prefix: String) -> Bool {
        return self.starts(with: prefix)
    }

    public func hasSuffix(_ suffix: String) -> Bool {
        return self.reversed().starts(with: suffix.reversed())
    }

    public func components(separatedBy separator: String) -> [String] {
        let len = self.count
        var lrange = range(of: separator, options: [], range: NSRange(location: 0, length: len))
        if lrange.length == 0 {
            return [String(self)]
        } else {
            var array = [String]()
            var srange = NSRange(location: 0, length: len)
            while true {
                let trange = NSRange(location: srange.location, length: lrange.location - srange.location)
                let lowerBound = self.index(self.startIndex, offsetBy: trange.location)
                let substring = self[lowerBound..<self.index(lowerBound, offsetBy: trange.length)]
                array.append(String(substring))
                srange.location = lrange.location + lrange.length
                srange.length = len - srange.location
                lrange = range(of: separator, options: [], range: srange)
                if lrange.length == 0 {
                    break
                }
            }
            let lowerBound = self.index(self.startIndex, offsetBy: srange.location)
            let substring = self[lowerBound..<self.index(lowerBound, offsetBy: srange.length)]
            array.append(String(substring))
            return array
        }
    }
    
    public func components(separatedBy separator: CharacterSet) -> [String] {
        let len = self.count
        var range = rangeOfCharacter(from: separator, options: [], range: NSRange(location: 0, length: len))
        if range.length == 0 {
            return [String(self)]
        } else {
            var array = [String]()
            var srange = NSRange(location: 0, length: len)
            while true {
                let trange = NSRange(location: srange.location, length: range.location - srange.location)
                let lowerBound = self.index(self.startIndex, offsetBy: trange.location)
                let substring = self[lowerBound..<self.index(lowerBound, offsetBy: trange.length)]
                array.append(String(substring))
                srange.location = range.location + range.length
                srange.length = len - srange.location
                range = rangeOfCharacter(from: separator, options: [], range: srange)
                if range.length == 0 {
                    break
                }
            }
            let lowerBound = self.index(self.startIndex, offsetBy: srange.location)
            let substring = self[lowerBound..<self.index(lowerBound, offsetBy: srange.length)]
            array.append(String(substring))
            return array
        }
    }
    
    public func trimmingCharacters(in set: CharacterSet) -> String {
        var substring = self[self.startIndex..<self.endIndex]
        while let first = substring.first, set.contains(first) {
            substring = substring.dropFirst()
        }
        while let last = substring.last, set.contains(last) {
            substring = substring.dropLast()
        }
        return String(substring)
    }

    public func range(of searchString: String) -> NSRange {
        return range(of: searchString, options: [], range: NSRange(location: 0, length: self.count))
    }
    
    public func range(of searchString: String, options mask: String.CompareOptions = []) -> NSRange {
        return range(of: searchString, options: mask, range: NSRange(location: 0, length: self.count))
    }
    
    public func range(of searchString: String, options mask: String.CompareOptions = [], range searchRange: NSRange) -> NSRange {
        let findStrLen = searchString.count
        let len = self.count
        
        precondition(searchRange.length <= len && searchRange.location <= len - searchRange.length, "Bounds Range {\(searchRange.location), \(searchRange.length)} out of bounds; string length \(len)")
        
        if mask.contains(.regularExpression) {
            NSUnimplemented()
        }
        
        if searchRange.length == 0 || findStrLen == 0 { // ??? This last item can't be here for correct Unicode compares
            return NSRange(location: NSNotFound, length: 0)
        }

        let startIndex = self.index(self.startIndex, offsetBy: searchRange.location)
        let endIndex = self.index(self.endIndex, offsetBy: -searchString.count)

        for (intIndex, i) in self[startIndex..<endIndex].indices.enumerated() {
            if self[i..<self.index(i, offsetBy: searchString.count)] == searchString {
                return NSRange(location: intIndex, length: searchString.count)
            }
        }

        return NSRange(location: NSNotFound, length: 0)
    }
    
    public func rangeOfCharacter(from searchSet: CharacterSet) -> NSRange {
        return rangeOfCharacter(from: searchSet, options: [], range: NSRange(location: 0, length: self.count))
    }
    
    public func rangeOfCharacter(from searchSet: CharacterSet, options mask: String.CompareOptions = []) -> NSRange {
        return rangeOfCharacter(from: searchSet, options: mask, range: NSRange(location: 0, length: self.count))
    }
    
    public func rangeOfCharacter(from searchSet: CharacterSet, options mask: String.CompareOptions = [], range searchRange: NSRange) -> NSRange {
        let len = self.count
        
        precondition(searchRange.length <= len && searchRange.location <= len - searchRange.length, "Bounds Range {\(searchRange.location), \(searchRange.length)} out of bounds; string length \(len)")
        
        for (i, character) in self.enumerated() {
            if searchSet.contains(character) {
                return NSRange(location: i, length: 1)
            }
        }

        return NSRange(location: NSNotFound, length: 0)
    }

    public func replacingOccurrences(of: String, with: String) -> String {
        return self.components(separatedBy: of).joined(separator: with)
    }
}


internal func isALineSeparatorTypeCharacter(_ ch: UInt16) -> Bool {
    if ch > 0x0d && ch < 0x0085 { /* Quick test to cover most chars */
        return false
    }
    return ch == 0x0a || ch == 0x0d || ch == 0x0085 || ch == 0x2028 || ch == 0x2029
}

internal func isAParagraphSeparatorTypeCharacter(_ ch: UInt16) -> Bool {
    if ch > 0x0d && ch < 0x2029 { /* Quick test to cover most chars */
        return false
    }
    return ch == 0x0a || ch == 0x0d || ch == 0x2029
}


internal struct _NSStringBuffer {
    var bufferLen: Int
    var bufferLoc: Int
    var string: String
    var stringLen: Int
    var _stringLoc: Int
    var buffer = Array<UInt16>(repeating: 0, count: 32)
    var curChar: UInt16?
    
    static let EndCharacter = UInt16(0xffff)
    
    init(string: String, start: Int, end: Int) {
        self.string = string
        _stringLoc = start
        stringLen = end
    
        if _stringLoc < stringLen {
            bufferLen = min(32, stringLen - _stringLoc)
            let range = NSRange(location: _stringLoc, length: bufferLen)
            bufferLoc = 1

            string.withCString(encodedAs: UTF16.self, { stringBuffer in
                buffer.withUnsafeMutableBufferPointer { buffer in
                    buffer.baseAddress?.assign(from: stringBuffer.advanced(by: range.lowerBound), count: range.length)
                }
            })
            curChar = buffer[0]
        } else {
            bufferLen = 0
            bufferLoc = 1
            curChar = _NSStringBuffer.EndCharacter
        }
    }
    
    var currentCharacter: UInt16 {
        return curChar!
    }
    
    var isAtEnd: Bool {
        return curChar == _NSStringBuffer.EndCharacter
    }
    
    mutating func fill() {
        bufferLen = min(32, stringLen - _stringLoc)
        let range = NSRange(location: _stringLoc, length: bufferLen)
        string.withCString(encodedAs: UTF16.self, { stringBuffer in
            buffer.withUnsafeMutableBufferPointer { buffer in
                buffer.baseAddress?.assign(from: stringBuffer.advanced(by: range.lowerBound), count: range.length)
            }
        })
        bufferLoc = 1
        curChar = buffer[0]
    }
    
    mutating func advance() {
        if bufferLoc < bufferLen { /*buffer is OK*/
            curChar = buffer[bufferLoc]
            bufferLoc += 1
        } else if (_stringLoc + bufferLen < stringLen) { /* Buffer is empty but can be filled */
            _stringLoc += bufferLen
            fill()
        } else { /* Buffer is empty and we're at the end */
            bufferLoc = bufferLen + 1
            curChar = _NSStringBuffer.EndCharacter
        }
    }
    
    mutating func rewind() {
        if bufferLoc > 1 { /* Buffer is OK */
            bufferLoc -= 1
            curChar = buffer[bufferLoc - 1]
        } else if _stringLoc > 0 { /* Buffer is empty but can be filled */
            bufferLoc = min(32, _stringLoc)
            bufferLen = bufferLoc
            _stringLoc -= bufferLen
            let range = NSRange(location: _stringLoc, length: bufferLen)
            
            string.withCString(encodedAs: UTF16.self, { stringBuffer in
                buffer.withUnsafeMutableBufferPointer { buffer in
                    buffer.baseAddress?.assign(from: stringBuffer.advanced(by: range.lowerBound), count: range.length)
                }
            })
            curChar = buffer[bufferLoc - 1]
        } else {
            bufferLoc = 0
            curChar = _NSStringBuffer.EndCharacter
        }
    }
    
    mutating func skip(_ skipSet: CharacterSet?) {
        if let set = skipSet {
            while set.contains(Unicode.Scalar(currentCharacter)!) && !isAtEnd {
                advance()
            }
        }
    }
    
    var location: Int {
        get {
            return _stringLoc + bufferLoc - 1
        }
        mutating set {
            if newValue < _stringLoc || newValue >= _stringLoc + bufferLen {
                if newValue < 16 { /* Get the first NSStringBufferSize chars */
                    _stringLoc = 0
                } else if newValue > stringLen - 16 { /* Get the last NSStringBufferSize chars */
                    _stringLoc = stringLen < 32 ? 0 : stringLen - 32
                } else {
                    _stringLoc = newValue - 16 /* Center around loc */
                }
                fill()
            }
            bufferLoc = newValue - _stringLoc
            curChar = buffer[bufferLoc]
            bufferLoc += 1
        }
    }
}


extension String {
    internal func _getBlockStart(_ startPtr: UnsafeMutablePointer<Int>?, end endPtr: UnsafeMutablePointer<Int>?, contentsEnd contentsEndPtr: UnsafeMutablePointer<Int>?, forRange range: NSRange, stopAtLineSeparators line: Bool) {
        let len = self.utf16.count
        var ch: UInt16
        
        precondition(range.length <= len && range.location < len - range.length, "Range {\(range.location), \(range.length)} is out of bounds of length \(len)")
        
        if range.location == 0 && range.length == len && contentsEndPtr == nil { // This occurs often
            startPtr?.pointee = 0
            endPtr?.pointee = range.length
            return
        }
        /* Find the starting point first */
        if let startPtr = startPtr {
            var start: Int = 0
            if range.location == 0 {
                start = 0
            } else {
                var buf = _NSStringBuffer(string: self, start: range.location, end: len)
                /* Take care of the special case where start happens to fall right between \r and \n */
                ch = buf.currentCharacter
                buf.rewind()
                if ch == 0x0a && buf.currentCharacter == 0x0d {
                    buf.rewind()
                }
                
                while true {
                    if line ? isALineSeparatorTypeCharacter(buf.currentCharacter) : isAParagraphSeparatorTypeCharacter(buf.currentCharacter) {
                        start = buf.location + 1
                        break
                    } else if buf.location <= 0 {
                        start = 0
                        break
                    } else {
                        buf.rewind()
                    }
                }
                startPtr.pointee = start
            }
        }

        if (endPtr != nil || contentsEndPtr != nil) {
            var endOfContents = 1
            var lineSeparatorLength = 1
            var buf = _NSStringBuffer(string: self, start: NSMaxRange(range) - (range.length > 0 ? 1 : 0), end: len)
            /* First look at the last char in the range (if the range is zero length, the char after the range) to see if we're already on or within a end of line sequence... */
            ch = buf.currentCharacter
            if ch == 0x0a {
                endOfContents = buf.location
                buf.rewind()
                if buf.currentCharacter == 0x0d {
                    lineSeparatorLength = 2
                    endOfContents -= 1
                }
            } else {
                while true {
                    if line ? isALineSeparatorTypeCharacter(ch) : isAParagraphSeparatorTypeCharacter(ch) {
                        endOfContents = buf.location /* This is actually end of contentsRange */
                        buf.advance() /* OK for this to go past the end */
                        if ch == 0x0d && buf.currentCharacter == 0x0a {
                            lineSeparatorLength = 2
                        }
                        break
                    } else if buf.location == len {
                        endOfContents = len
                        lineSeparatorLength = 0
                        break
                    } else {
                        buf.advance()
                        ch = buf.currentCharacter
                    }
                }
            }
            
            contentsEndPtr?.pointee = endOfContents
            endPtr?.pointee = endOfContents + lineSeparatorLength
        }
    }
    
    public func getLineStart(_ startPtr: UnsafeMutablePointer<Int>?, end lineEndPtr: UnsafeMutablePointer<Int>?, contentsEnd contentsEndPtr: UnsafeMutablePointer<Int>?, for range: NSRange) {
        _getBlockStart(startPtr, end: lineEndPtr, contentsEnd: contentsEndPtr, forRange: range, stopAtLineSeparators: true)
    }

     // - (void)
    //     getLineStart:(NSUInteger *)startIndex
    //     end:(NSUInteger *)lineEndIndex
    //     contentsEnd:(NSUInteger *)contentsEndIndex
    //     forRange:(NSRange)aRange

    /// Returns by reference the beginning of the first line and
    /// the end of the last line touched by the given range.
    public func getLineStart<
        R : RangeExpression
    >(
        _ start: UnsafeMutablePointer<Index>,
        end: UnsafeMutablePointer<Index>,
        contentsEnd: UnsafeMutablePointer<Index>,
        for range: R
    ) where R.Bound == Index {
        _withOptionalOutParameter(start) {
        start in self._withOptionalOutParameter(end) {
            end in self._withOptionalOutParameter(contentsEnd) {
            contentsEnd in self.getLineStart(
                start, end: end,
                contentsEnd: contentsEnd,
                for: _toRelativeNSRange(range.relative(to: self)))
            }
        }
        }
    }

    public init?(data: Data, encoding: String.Encoding) {
        switch encoding {
            case .utf8, .ascii:
                let collection = UnsafeBufferPointer(start: data._backing.bytes?.assumingMemoryBound(to: UInt8.self), count: data.count)
                self = String(decoding: collection, as: UTF8.self)
            case .utf16:
                let collection = UnsafeBufferPointer(start: data._backing.bytes?.assumingMemoryBound(to: UInt16.self), count: data.count / 2)
                self = String(decoding: collection, as: UTF16.self)
            default:
                return nil
        }
    }

    public func data(using encoding: String.Encoding) -> Data? {
        switch encoding {
            case .utf8, .ascii:
                return Data(bytes: self.utf8CString)
            case .utf16, .utf16LittleEndian:
                return self.withCString(encodedAs: UTF16.self) { buffer in
                    let length = Int(wcslen(buffer))
                    return Data(bytes: buffer, count: length * MemoryLayout<UInt16>.size)
                }
            default:
                return nil
        }
    }

    public func write(toFile path: String, atomically: Bool = false, encoding: String.Encoding) throws {
        let data = self.data(using: encoding)!
        try data.write(toFile: path, options: atomically ? .atomic : [])
    }

    public init(contentsOf url: URL, encoding enc: String.Encoding = .utf8) throws {
        let readResult = try Data(contentsOf: url, options: [])

        guard let string = String(data: readResult, encoding: enc) else {
            fatalError("Unable to decode string at \(url) with encoding \(enc).")
        }
        
        self = string
    }

    public init(contentsOfFile path: String, encoding enc: String.Encoding = .utf8) throws {
        try self.init(contentsOf: URL(fileURLWithPath: path), encoding: enc)
    }
}