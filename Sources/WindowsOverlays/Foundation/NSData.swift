// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//


import CFoundationExtras

#if os(OSX) || os(iOS)
import Darwin
#elseif os(Linux) || CYGWIN
import Glibc
#endif

#if DEPLOYMENT_ENABLE_LIBDISPATCH
import Dispatch
#endif

extension Data {
    public struct ReadingOptions : OptionSet {
        public let rawValue : UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        
        public static let mappedIfSafe = ReadingOptions(rawValue: UInt(1 << 0))
        public static let uncached = ReadingOptions(rawValue: UInt(1 << 1))
        public static let alwaysMapped = ReadingOptions(rawValue: UInt(1 << 2))
    }

    public struct WritingOptions : OptionSet {
        public let rawValue : UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        
        public static let atomic = WritingOptions(rawValue: UInt(1 << 0))
        public static let withoutOverwriting = WritingOptions(rawValue: UInt(1 << 1))
    }

    public struct SearchOptions : OptionSet {
        public let rawValue : UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        
        public static let backwards = SearchOptions(rawValue: UInt(1 << 0))
        public static let anchored = SearchOptions(rawValue: UInt(1 << 1))
    }

    public struct Base64EncodingOptions : OptionSet {
        public let rawValue : UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        
        public static let lineLength64Characters = Base64EncodingOptions(rawValue: UInt(1 << 0))
        public static let lineLength76Characters = Base64EncodingOptions(rawValue: UInt(1 << 1))
        public static let endLineWithCarriageReturn = Base64EncodingOptions(rawValue: UInt(1 << 4))
        public static let endLineWithLineFeed = Base64EncodingOptions(rawValue: UInt(1 << 5))
    }

    public struct Base64DecodingOptions : OptionSet {
        public let rawValue : UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        
        public static let ignoreUnknownCharacters = Base64DecodingOptions(rawValue: UInt(1 << 0))
    }
}

private final class _DataDeallocator {
    var handler: (UnsafeMutableRawPointer, Int) -> Void = {_,_ in }
}

extension Data : CustomStringConvertible, CustomDebugStringConvertible {

    /// Initializes a data object with the contents of the file at a given path.
    public init(contentsOfFile path: String, options readOptionsMask: ReadingOptions = []) throws {
        let readResult = try Data.readBytesFromFileWithExtendedAttributes(path, options: readOptionsMask)
        self.init(bytes: readResult.bytes, length: readResult.length, copy: false, deallocator: readResult.deallocator, offset: 0)
    }

    /// Initializes a data object with the contents of the file at a given path.
    public init?(contentsOfFile path: String) {
        do {
           let readResult = try Data.readBytesFromFileWithExtendedAttributes(path, options: [])
           self.init(bytes: readResult.bytes, length: readResult.length, copy: false, deallocator: readResult.deallocator, offset: 0)
        } catch {
            return nil
        }
    }


    /// Initializes a data object with the data from the location specified by a given URL.
    public init(contentsOf url: URL, options readOptionsMask: ReadingOptions = []) throws {
        let readResult = try Data._contentsOf(url: url, options: readOptionsMask)
         self.init(bytes: readResult.bytes, length: readResult.length, copy: false, deallocator: readResult.deallocator, offset: 0)
    }

    /// Initializes a data object with the data from the location specified by a given URL.
    public init(contentsOf url: URL) throws {
        let readResult = try Data._contentsOf(url: url)
        self.init(bytes: readResult.bytes, length: readResult.length, copy: false, deallocator: readResult.deallocator, offset: 0)
    }

    /// Initializes a data object with the data from the location specified by a given URL.
    private static func _contentsOf(url: URL, options readOptionsMask: ReadingOptions = []) throws -> DataReadResult {
        if url.isFileURL {
            return try Data.readBytesFromFileWithExtendedAttributes(url.path, options: readOptionsMask)
        } else {
            NSUnimplemented()
        }
    }

    /// Initializes a data object with the given Base64 encoded string.
    public init?(base64Encoded base64String: String, options: Base64DecodingOptions = []) {
        let encodedBytes = Array(base64String.utf8)
        guard let decodedBytes = Data.base64DecodeBytes(encodedBytes, options: options) else {
            return nil
        }
        self.init(bytes: UnsafeMutableRawPointer(mutating: decodedBytes), length: decodedBytes.count, copy: true)
    }

    /// Initializes a data object with the given Base64 encoded data.
    public init?(base64Encoded base64Data: Data, options: Base64DecodingOptions = []) {
        var encodedBytes = [UInt8](repeating: 0, count: base64Data.count)
        base64Data.copyBytes(to: &encodedBytes, count: encodedBytes.count)
        guard let decodedBytes = Data.base64DecodeBytes(encodedBytes, options: options) else {
            return nil
        }
        self.init(bytes: UnsafeMutableRawPointer(mutating: decodedBytes), length: decodedBytes.count, copy: true)
    }
    
    private func byteDescription(limit: Int? = nil) -> String {
        var s = ""
        var i = 0
        while i < self.count {
            if i > 0 && i % 4 == 0 {
                // if there's a limit, and we're at the barrier where we'd add the ellipses, don't add a space.
                if let limit = limit, self.count > limit && i == self.count - (limit / 2) { /* do nothing */ }
                else { s += " " }
            }
            let byte = _backing.bytes!.load(fromByteOffset: i, as: UInt8.self)
            var byteStr = String(byte, radix: 16, uppercase: false)
            if byte <= 0xf { byteStr = "0\(byteStr)" }
            s += byteStr
            // if we've hit the midpoint of the limit, skip to the last (limit / 2) bytes.
            if let limit = limit, self.count > limit && i == (limit / 2) - 1 {
                s += " ... "
                i = self.count - (limit / 2)
            } else {
                i += 1
            }
        }
        return s
    }
    
    public var debugDescription: String {
        return "<\(byteDescription(limit: 1024))>"
    }

    /// A string that contains a hexadecimal representation of the data object’s contents in a property list format.
    public var description: String {
        return "<\(byteDescription())>"
    }

    // MARK: - IO
    internal struct DataReadResult {
        var bytes: UnsafeMutableRawPointer
        var length: Int
        var deallocator: ((_ buffer: UnsafeMutableRawPointer, _ length: Int) -> Void)?
    }
    
    enum FileReadingError : Error {
        case noSuchFile(String)
        case fileMappingError(String)
    }

    internal static func readBytesFromFileWithExtendedAttributes(_ path: String, options: ReadingOptions) throws -> DataReadResult {
#if os(Windows)

    if options.intersection([.alwaysMapped, .mappedIfSafe]) != [] {
        let file = path.withCString(encodedAs: UTF16.self) { (path) -> HANDLE? in
            let path = path as LPCWSTR?
            return CreateFileW(path, GENERIC_READ, DWORD(FILE_SHARE_READ), nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
         }
         if file == INVALID_HANDLE_VALUE {
            throw FileReadingError.noSuchFile(path)
         }

         let length = GetFileSize(file, nil)

         let fileMapping = CreateFileMappingW(file, nil, DWORD(PAGE_READONLY), 0, 0, nil)
         if fileMapping == nil {
             throw FileReadingError.fileMappingError(path)
         }

         let data = MapViewOfFile(fileMapping, DWORD(FILE_MAP_READ), 0, 0, 0)

          return DataReadResult(bytes: data!, length: Int(length)) { buffer, length in
            UnmapViewOfFile(data)
            CloseHandle(file)
        }
    }

#endif

        let fd = path.withCString(encodedAs: UTF16.self) { _wopenNoMode($0, O_RDONLY) }
        if fd < 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(getErrno()), userInfo: nil)
        }
        defer {
            _close(fd)
        }

        var info = stat()
        let ret = withUnsafeMutablePointer(to: &info) { infoPointer -> Bool in
            if fstat(fd, infoPointer) < 0 {
                return false
            }
            return true
        }
        
        if !ret {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(getErrno()), userInfo: nil)
        }
        
        let length = Int(info.st_size)
        if length == 0 && (info.st_mode & UInt16(S_IFMT) == S_IFREG) {
            return try readZeroSizeFile(fd)
        }

#if !os(Windows)
        if options.contains(.alwaysMapped) {
            let data = mmap(nil, length, PROT_READ, MAP_PRIVATE, fd, 0)
            
            // Swift does not currently expose MAP_FAILURE
            if data != UnsafeMutableRawPointer(bitPattern: -1) {
                return DataReadResult(bytes: data!, length: length) { buffer, length in
                    munmap(buffer, length)
                }
            }
            
        }
#endif
        
        let data = malloc(length)!
        var remaining = length
        var total = 0
        while remaining > 0 {
            let amt = Int(_read(fd, data.advanced(by: total), UInt32(remaining)))
            if amt < 0 {
                break
            }
            remaining -= amt
            total += amt
        }

        if remaining != 0 {
            free(data)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(getErrno()), userInfo: nil)
        }
        
        return DataReadResult(bytes: data, length: length) { buffer, length in
            free(buffer)
        }
    }

    internal static func readZeroSizeFile(_ fd: Int32) throws -> DataReadResult {
        let blockSize = 1024 * 1024 // 1MB
        var data: UnsafeMutableRawPointer? = nil
        var bytesRead = 0
        var amt = 0

        repeat {
            data = realloc(data, bytesRead + blockSize)
            amt = Int(_read(fd, data!.advanced(by: bytesRead), UInt32(blockSize)))

            // Dont continue on EINTR or EAGAIN as the file position may not
            // have changed, see read(2).
            if amt < 0 {
                free(data!)
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(getErrno()), userInfo: nil)
            }
            bytesRead += amt
        } while amt > 0

        if bytesRead == 0 {
            free(data!)
            data = malloc(0)
        } else {
            data = realloc(data, bytesRead) // shrink down the allocated block.
        }

        return DataReadResult(bytes: data!, length: bytesRead) { buffer, length in
            free(buffer)
        }
    }
    
    internal func makeTemporaryFile(inDirectory dirPath: String) throws -> (Int32, String) {
        var tempFileName = [UInt16](repeating: 0, count: Int(MAX_PATH))
        let _ = dirPath.withCString(encodedAs: UTF16.self) { dirPath in 
            "tmp".withCString(encodedAs: UTF16.self) { tmpPrefix in
                GetTempFileNameW(dirPath, tmpPrefix, 0, &tempFileName)
            }
        }
        let fd = _wopenWithMode(tempFileName, _O_CREAT | _O_TRUNC | _O_WRONLY, _S_IREAD | _S_IWRITE)
        let tempFilePath = String(decodingCString: tempFileName, as: UTF16.self) // FileManager.default.string(withFileSystemRepresentation:buf, length: Int(strlen(buf)))
        return (fd, tempFilePath) 
    }

    internal static func write(toFileDescriptor fd: Int32, path: String? = nil, buf: UnsafeRawPointer, length: Int) throws {
        var bytesRemaining = length
        while bytesRemaining > 0 {
            var bytesWritten : Int
            repeat {
                bytesWritten = Int(_write(fd, buf.advanced(by: length - bytesRemaining), UInt32(bytesRemaining)))
            } while (bytesWritten < 0 && getErrno() == EINTR)
            if bytesWritten <= 0 {
                throw _NSErrorWithErrno(getErrno(), reading: false, path: path)
            } else {
                bytesRemaining -= bytesWritten
            }
        }
    }

    /// Writes the data object's bytes to the file specified by a given path.
    public func write(toFile path: String, options writeOptionsMask: WritingOptions = []) throws {
        var fd : Int32
        var mode : Int32? = nil
        let useAuxiliaryFile = writeOptionsMask.contains(.atomic)
        var auxFilePath : String? = nil
        if useAuxiliaryFile {
            // Preserve permissions.
            var info = stat()
            if stat(path, &info) == 0 {
                mode = Int32(info.st_mode)
            } else if getErrno() != ENOENT && getErrno() != ENAMETOOLONG {
                throw _NSErrorWithErrno(getErrno(), reading: false, path: path)
            }
            let (newFD, path) = try self.makeTemporaryFile(inDirectory: path.deletingLastPathComponent)
            fd = newFD
            auxFilePath = path
            _ = path.withCString(encodedAs: UTF16.self) { _wchmod($0, 0o666) }
        } else {
            var flags = O_WRONLY | O_CREAT | O_TRUNC
            if writeOptionsMask.contains(.withoutOverwriting) {
                flags |= O_EXCL
            }
            fd = path.withCString(encodedAs: UTF16.self) { _wopenWithMode($0, flags, 0o666) }
        }
        if fd == -1 {
            throw _NSErrorWithErrno(getErrno(), reading: false, path: path)
        }

        try self.enumerateByteRangesUsingBlockRethrows { (buf, range, stop) in
            if range.length > 0 {
                do {
                    try Data.write(toFileDescriptor: fd, path: path, buf: buf, length: range.length)
                    if _commit(fd) != 0 {
                        throw _NSErrorWithErrno(getErrno(), reading: false, path: path)
                    }
                } catch let err {
                    if let auxFilePath = auxFilePath {
                        do {
                            try FileManager.default.removeItem(atPath: auxFilePath)
                        } catch _ {}
                    }
                    throw err
                }
            }
        }

        _close(fd)

        if let auxFilePath = auxFilePath {
            try auxFilePath.withCString(encodedAs: UTF16.self) { auxFilePathC in
                let renameResult = path.withCString(encodedAs: UTF16.self) { _wrename(auxFilePathC, $0) }
                if renameResult != 0 {
                    do {
                        try FileManager.default.removeItem(atPath: auxFilePath)
                    } catch _ {}
                    throw _NSErrorWithErrno(getErrno(), reading: false, path: path)
                }
                if let mode = mode {
                    _chmod(path, mode)
                }
            }
        }
    }

    /// Writes the data object's bytes to the file specified by a given path.
    /// NOTE: the 'atomically' flag is ignored if the url is not of a type the supports atomic writes
    public func write(toFile path: String, atomically useAuxiliaryFile: Bool) -> Bool {
        do {
            try write(toFile: path, options: useAuxiliaryFile ? .atomic : [])
        } catch {
            return false
        }
        return true
    }

    /// Writes the data object's bytes to the location specified by a given URL.
    /// NOTE: the 'atomically' flag is ignored if the url is not of a type the supports atomic writes
    public func write(to url: URL, atomically: Bool) -> Bool {
        if url.isFileURL {
            return write(toFile: url.path, atomically: atomically)
        }
        return false
    }

    ///    Writes the data object's bytes to the location specified by a given URL.
    ///
    ///    - parameter url:              The location to which the data objects's contents will be written.
    ///    - parameter writeOptionsMask: An option set specifying file writing options.
    ///
    ///    - throws: This method returns Void and is marked with the `throws` keyword to indicate that it throws an error in the event of failure.
    ///
    ///      This method is invoked in a `try` expression and the caller is responsible for handling any errors in the `catch` clauses of a `do` statement, as described in [Error Handling](https://developer.apple.com/library/prerelease/ios/documentation/Swift/Conceptual/Swift_Programming_Language/ErrorHandling.html#//apple_ref/doc/uid/TP40014097-CH42) in [The Swift Programming Language](https://developer.apple.com/library/prerelease/ios/documentation/Swift/Conceptual/Swift_Programming_Language/index.html#//apple_ref/doc/uid/TP40014097) and [Error Handling](https://developer.apple.com/library/prerelease/ios/documentation/Swift/Conceptual/BuildingCocoaApps/AdoptingCocoaDesignPatterns.html#//apple_ref/doc/uid/TP40014216-CH7-ID10) in [Using Swift with Cocoa and Objective-C](https://developer.apple.com/library/prerelease/ios/documentation/Swift/Conceptual/BuildingCocoaApps/index.html#//apple_ref/doc/uid/TP40014216).
    public func write(to url: URL, options writeOptionsMask: WritingOptions = []) throws {
        guard url.isFileURL else {
            let userInfo = [NSLocalizedDescriptionKey : "The folder at “\(url)” does not exist or is not a file URL.", // NSLocalizedString() not yet available
                            NSURLErrorKey             : url.absoluteString] as Dictionary<String, Any>
            throw NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: userInfo)
        }
        try write(toFile: url.path, options: writeOptionsMask)
    }

    /// Finds and returns the range of the first occurrence of the given data, within the given range, subject to given options.
    public func range(of dataToFind: Data, options mask: SearchOptions = [], in searchRange: NSRange) -> NSRange {
        guard dataToFind.count > 0 else {return NSRange(location: NSNotFound, length: 0)}
        guard let searchRange = Range(searchRange) else {fatalError("invalid range")}
        
        precondition(searchRange.upperBound <= self.count, "range outside the bounds of data")

        let basePtr = self._backing.bytes?.bindMemory(to: UInt8.self, capacity: self.count)
        let baseData = UnsafeBufferPointer<UInt8>(start: basePtr, count: self.count)[searchRange]
        let searchPtr = dataToFind._backing.bytes?.bindMemory(to: UInt8.self, capacity: dataToFind.count)
        let search = UnsafeBufferPointer<UInt8>(start: searchPtr, count: dataToFind.count)
        
        let location : Int?
        let anchored = mask.contains(.anchored)
        if mask.contains(.backwards) {
            location = Data.searchSubSequence(search.reversed(), inSequence: baseData.reversed(),anchored : anchored).map {$0.base-search.count}
        } else {
            location = Data.searchSubSequence(search, inSequence: baseData,anchored : anchored)
        }
        return location.map {NSRange(location: $0, length: search.count)} ?? NSRange(location: NSNotFound, length: 0)
    }

    private static func searchSubSequence<T : Collection, T2 : Sequence>(_ subSequence : T2, inSequence seq: T,anchored : Bool) -> T.Index? where T.Iterator.Element : Equatable, T.Iterator.Element == T2.Iterator.Element {
        for index in seq.indices {
            if seq.suffix(from: index).starts(with: subSequence) {
                return index
            }
            if anchored {return nil}
        }
        return nil
    }
    
    internal func enumerateByteRangesUsingBlockRethrows(_ block: (UnsafeRawPointer, NSRange, UnsafeMutablePointer<Bool>) throws -> Void) throws {
        var err : Swift.Error? = nil
        self.enumerateBytes() { (buf, range, stop) -> Void in
            do {
                try block(buf.baseAddress!, NSRange(location: 0, length: self.count), &stop)
            } catch let e {
                err = e
            }
        }
        if let err = err {
            throw err
        }
    }

    // MARK: - Base64 Methods

    /// Creates a Base64 encoded String from the data object using the given options.
    public func base64EncodedString(options: Base64EncodingOptions = []) -> String {
        var decodedBytes = [UInt8](repeating: 0, count: self.count)
        self.copyBytes(to: &decodedBytes, count: decodedBytes.count)
        let encodedBytes = Data.base64EncodeBytes(decodedBytes, options: options)
        let characters = encodedBytes.map { Character(UnicodeScalar($0)) }
        return String(characters)
    }

    /// Creates a Base64, UTF-8 encoded Data from the data object using the given options.
    public func base64EncodedData(options: Base64EncodingOptions = []) -> Data {
        var decodedBytes = [UInt8](repeating: 0, count: self.count)
        self.copyBytes(to: &decodedBytes, count: decodedBytes.count)
        let encodedBytes = Data.base64EncodeBytes(decodedBytes, options: options)
        return Data(bytes: encodedBytes, count: encodedBytes.count)
    }

    /// The ranges of ASCII characters that are used to encode data in Base64.
    private static let base64ByteMappings: [Range<UInt8>] = [
        65 ..< 91,      // A-Z
        97 ..< 123,     // a-z
        48 ..< 58,      // 0-9
        43 ..< 44,      // +
        47 ..< 48,      // /
    ]
    /**
     Padding character used when the number of bytes to encode is not divisible by 3
     */
    private static let base64Padding : UInt8 = 61 // =
    
    /**
     This method takes a byte with a character from Base64-encoded string
     and gets the binary value that the character corresponds to.
     
     - parameter byte:       The byte with the Base64 character.
     - returns:              Base64DecodedByte value containing the result (Valid , Invalid, Padding)
     */
    private enum Base64DecodedByte {
        case valid(UInt8)
        case invalid
        case padding
    }

    private static func base64DecodeByte(_ byte: UInt8) -> Base64DecodedByte {
        guard byte != base64Padding else {return .padding}
        var decodedStart: UInt8 = 0
        for range in base64ByteMappings {
            if range.contains(byte) {
                let result = decodedStart + (byte - range.lowerBound)
                return .valid(result)
            }
            decodedStart += range.upperBound - range.lowerBound
        }
        return .invalid
    }
    
    /**
     This method takes six bits of binary data and encodes it as a character
     in Base64.
     
     The value in the byte must be less than 64, because a Base64 character
     can only represent 6 bits.
     
     - parameter byte:       The byte to encode
     - returns:              The ASCII value for the encoded character.
     */
    private static func base64EncodeByte(_ byte: UInt8) -> UInt8 {
        assert(byte < 64)
        var decodedStart: UInt8 = 0
        for range in base64ByteMappings {
            let decodedRange = decodedStart ..< decodedStart + (range.upperBound - range.lowerBound)
            if decodedRange.contains(byte) {
                return range.lowerBound + (byte - decodedStart)
            }
            decodedStart += range.upperBound - range.lowerBound
        }
        return 0
    }

    /**
     This method decodes Base64-encoded data.
     
     If the input contains any bytes that are not valid Base64 characters,
     this will return nil.
     
     - parameter bytes:      The Base64 bytes
     - parameter options:    Options for handling invalid input
     - returns:              The decoded bytes.
     */
    private static func base64DecodeBytes(_ bytes: [UInt8], options: Base64DecodingOptions = []) -> [UInt8]? {
        var decodedBytes = [UInt8]()
        decodedBytes.reserveCapacity((bytes.count/3)*2)
        
        var currentByte : UInt8 = 0
        var validCharacterCount = 0
        var paddingCount = 0
        var index = 0
        
        
        for base64Char in bytes {
            
            let value : UInt8
            
            switch base64DecodeByte(base64Char) {
            case .valid(let v):
                value = v
                validCharacterCount += 1
            case .invalid:
                if options.contains(.ignoreUnknownCharacters) {
                    continue
                } else {
                    return nil
                }
            case .padding:
                paddingCount += 1
                continue
            }
            
            //padding found in the middle of the sequence is invalid
            if paddingCount > 0 {
                return nil
            }
            
            switch index%4 {
            case 0:
                currentByte = (value << 2)
            case 1:
                currentByte |= (value >> 4)
                decodedBytes.append(currentByte)
                currentByte = (value << 4)
            case 2:
                currentByte |= (value >> 2)
                decodedBytes.append(currentByte)
                currentByte = (value << 6)
            case 3:
                currentByte |= value
                decodedBytes.append(currentByte)
            default:
                fatalError()
            }
            
            index += 1
        }
        
        guard (validCharacterCount + paddingCount)%4 == 0 else {
            //invalid character count
            return nil
        }
        return decodedBytes
    }

    /**
     This method encodes data in Base64.
     
     - parameter bytes:      The bytes you want to encode
     - parameter options:    Options for formatting the result
     - returns:              The Base64-encoding for those bytes.
     */
    private static func base64EncodeBytes(_ bytes: [UInt8], options: Base64EncodingOptions = []) -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity((bytes.count/3)*4)
        
        let lineOptions : (lineLength : Int, separator : [UInt8])? = {
            let lineLength: Int
            
            if options.contains(.lineLength64Characters) { lineLength = 64 }
            else if options.contains(.lineLength76Characters) { lineLength = 76 }
            else {
                return nil
            }
            
            var separator = [UInt8]()
            if options.contains(.endLineWithCarriageReturn) { separator.append(13) }
            if options.contains(.endLineWithLineFeed) { separator.append(10) }
            
            //if the kind of line ending to insert is not specified, the default line ending is Carriage Return + Line Feed.
            if separator.isEmpty { separator = [13,10] }
            
            return (lineLength,separator)
        }()
        
        var currentLineCount = 0
        let appendByteToResult : (UInt8) -> Void = {
            result.append($0)
            currentLineCount += 1
            if let options = lineOptions, currentLineCount == options.lineLength {
                result.append(contentsOf: options.separator)
                currentLineCount = 0
            }
        }
        
        var currentByte : UInt8 = 0
        
        for (index,value) in bytes.enumerated() {
            switch index%3 {
            case 0:
                currentByte = (value >> 2)
                appendByteToResult(Data.base64EncodeByte(currentByte))
                currentByte = ((value << 6) >> 2)
            case 1:
                currentByte |= (value >> 4)
                appendByteToResult(Data.base64EncodeByte(currentByte))
                currentByte = ((value << 4) >> 2)
            case 2:
                currentByte |= (value >> 6)
                appendByteToResult(Data.base64EncodeByte(currentByte))
                currentByte = ((value << 2) >> 2)
                appendByteToResult(Data.base64EncodeByte(currentByte))
            default:
                fatalError()
            }
        }
        //add padding
        switch bytes.count%3 {
        case 0: break //no padding needed
        case 1:
            appendByteToResult(Data.base64EncodeByte(currentByte))
            appendByteToResult(self.base64Padding)
            appendByteToResult(self.base64Padding)
        case 2:
            appendByteToResult(Data.base64EncodeByte(currentByte))
            appendByteToResult(self.base64Padding)
        default:
            fatalError()
        }
        return result
    }
}