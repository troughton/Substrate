// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//

#if os(OSX) || os(iOS)
    import Darwin
#elseif os(Linux) || CYGWIN
    import Glibc
#elseif os(Windows)
    import visualc
    import ucrt
    import Windows
#endif

import CFoundationExtras

let INVALID_HANDLE_VALUE = HANDLE(bitPattern: UInt.max)

open class FileManager : NSObject {
    
    /* Returns the default singleton instance.
    */
    private static let _default = FileManager()

    private override init() {
        super.init()
        _set_fmode(_O_BINARY)
    }

    open class var `default`: FileManager {
        get {
            return _default
        }
    }
    
    /* Returns an NSArray of URLs identifying the the directory entries. 
    
        If the directory contains no entries, this method will return the empty array. When an array is specified for the 'keys' parameter, the specified property values will be pre-fetched and cached with each enumerated URL.
     
        This method always does a shallow enumeration of the specified directory (i.e. it always acts as if NSDirectoryEnumerationSkipsSubdirectoryDescendants has been specified). If you need to perform a deep enumeration, use -[NSFileManager enumeratorAtURL:includingPropertiesForKeys:options:errorHandler:].
     
        If you wish to only receive the URLs and no other attributes, then pass '0' for 'options' and an empty NSArray ('[NSArray array]') for 'keys'. If you wish to have the property caches of the vended URLs pre-populated with a default set of attributes, then pass '0' for 'options' and 'nil' for 'keys'.
     */
    open func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: DirectoryEnumerationOptions = []) throws -> [URL] {
        var error : Error? = nil
        let e = self.enumerator(at: url, includingPropertiesForKeys: keys, options: mask.union(.skipsSubdirectoryDescendants)) { (url, err) -> Bool in
            error = err
            return false
        }
        var result = [URL]()
        if let e = e {
            for url in e {
                result.append(url as! URL)
            }
            if let error = error {
                throw error
            }
        }
        return result
    }
    
    /* createDirectoryAtURL:withIntermediateDirectories:attributes:error: creates a directory at the specified URL. If you pass 'NO' for withIntermediateDirectories, the directory must not exist at the time this call is made. Passing 'YES' for withIntermediateDirectories will create any necessary intermediate directories. This method returns YES if all directories specified in 'url' were created and attributes were set. Directories are created with attributes specified by the dictionary passed to 'attributes'. If no dictionary is supplied, directories are created according to the umask of the process. This method returns NO if a failure occurs at any stage of the operation. If an error parameter was provided, a presentable NSError will be returned by reference.
     */
    open func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = [:]) throws {
        guard url.isFileURL else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnsupportedScheme.rawValue, userInfo: [NSURLErrorKey : url])
        }
        try self.createDirectory(atPath: url.path, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
    
    /* Instances of FileManager may now have delegates. Each instance has one delegate, and the delegate is not retained. In versions of Mac OS X prior to 10.5, the behavior of calling [[NSFileManager alloc] init] was undefined. In Mac OS X 10.5 "Leopard" and later, calling [[NSFileManager alloc] init] returns a new instance of an FileManager.
     */
    open weak var delegate: FileManagerDelegate? {
        NSUnimplemented()
    }
    
    /* createDirectoryAtPath:withIntermediateDirectories:attributes:error: creates a directory at the specified path. If you pass 'NO' for createIntermediates, the directory must not exist at the time this call is made. Passing 'YES' for 'createIntermediates' will create any necessary intermediate directories. This method returns YES if all directories specified in 'path' were created and attributes were set. Directories are created with attributes specified by the dictionary passed to 'attributes'. If no dictionary is supplied, directories are created according to the umask of the process. This method returns NO if a failure occurs at any stage of the operation. If an error parameter was provided, a presentable NSError will be returned by reference.
     
        This method replaces createDirectoryAtPath:attributes:
     */
    open func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = [:]) throws {
        if createIntermediates {
            var isDir: Bool = false
            if !fileExists(atPath: path, isDirectory: &isDir) {
                let parent = path.deletingLastPathComponent
                if !fileExists(atPath: parent, isDirectory: &isDir) {
                    try createDirectory(atPath: parent, withIntermediateDirectories: true, attributes: attributes)
                }
                
                let createDirectoryResult = path.withCString(encodedAs: UTF16.self) { CreateDirectoryW($0, nil) }
                if createDirectoryResult == 0 {
                    throw _NSErrorWithErrno(getErrno(), reading: false, path: path)
                } else if attributes != nil {
                    print("Warning: attributes ignored for FileManager.createDirectory on Windows.")
                }
            } else if isDir {
                return
            } else {
                throw _NSErrorWithErrno(EEXIST, reading: false, path: path)
            }
        } else {
            let createDirectoryResult = path.withCString(encodedAs: UTF16.self) { CreateDirectoryW($0, nil) }
            if createDirectoryResult == 0 {
                throw _NSErrorWithErrno(getErrno(), reading: false, path: path)
            } else if attributes != nil {
                    print("Warning: attributes ignored for FileManager.createDirectory on Windows.")
            }
        }
    }
    
    /**
     Performs a shallow search of the specified directory and returns the paths of any contained items.
     
     This method performs a shallow search of the directory and therefore does not traverse symbolic links or return the contents of any subdirectories. This method also does not return URLs for the current directory (“.”), parent directory (“..”) but it does return other hidden files (files that begin with a period character).
     
     The order of the files in the returned array is undefined.
     
     - Parameter path: The path to the directory whose contents you want to enumerate.
     
     - Throws: `NSError` if the directory does not exist, this error is thrown with the associated error code.
     
     - Returns: An array of String each of which identifies a file, directory, or symbolic link contained in `path`. The order of the files returned is undefined.
     */
    open func contentsOfDirectory(atPath path: String) throws -> [String] {
        var contents : [String] = [String]()
        
        var hFind = INVALID_HANDLE_VALUE
        var stringLength = DWORD(MAX_PATH + 2)
        var ffd = WIN32_FIND_DATA()
        
        var error : NSError? = nil

        _ = path.withCString(encodedAs: UTF16.self) { path16 in
        _withStackOrHeapBuffer(MemoryLayout<TCHAR>.size * Int(MAX_PATH)) { szDir in
            let buffer = szDir.pointee.memory.assumingMemoryBound(to: UInt16.self)

            let lengthOfArg = wcslen(path16)

            if lengthOfArg > Int(MAX_PATH) - 3 {
                preconditionFailure("Directory path is too long.")
            }

            wcscpy_s(buffer, MAX_PATH, path16)
            _ = "\\*".withCString(encodedAs: UTF16.self) {
                wcscat_s(buffer, MAX_PATH, $0)
            }

            // Find the first file in the directory.

            hFind = FindFirstFileW(buffer, &ffd)

            if (INVALID_HANDLE_VALUE == hFind) 
            {
                error = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoSuchFile.rawValue, userInfo: [NSFilePathErrorKey: path])
                return 
            } 
            
            // List all the files in the directory with some info about them.

            repeat
            {
                let entryName = withUnsafePointer(to: &ffd.cFileName.0) {
                    String(decodingCString: $0, as: UTF16.self)
                } 
                if entryName != "." && entryName != ".." {
                    contents.append(entryName)
                }
            }
            while (FindNextFileW(hFind, &ffd) != 0)
            
            defer {
                FindClose(hFind)
            }
        }
        }

        if let error = error {
            throw error
        }

        return contents
    }
    
    /**
    Performs a deep enumeration of the specified directory and returns the paths of all of the contained subdirectories.
    
    This method recurses the specified directory and its subdirectories. The method skips the “.” and “..” directories at each level of the recursion.
    
    Because this method recurses the directory’s contents, you might not want to use it in performance-critical code. Instead, consider using the enumeratorAtURL:includingPropertiesForKeys:options:errorHandler: or enumeratorAtPath: method to enumerate the directory contents yourself. Doing so gives you more control over the retrieval of items and more opportunities to abort the enumeration or perform other tasks at the same time.
    
    - Parameter path: The path of the directory to list.
    
    - Throws: `NSError` if the directory does not exist, this error is thrown with the associated error code.
    
    - Returns: An array of NSString objects, each of which contains the path of an item in the directory specified by path. If path is a symbolic link, this method traverses the link. This method returns nil if it cannot retrieve the device of the linked-to file.
    */
    open func subpathsOfDirectory(atPath path: String) throws -> [String] {
      var contents : [String] = [String]()
        
        var hFind = INVALID_HANDLE_VALUE

        var stringLength = DWORD(MAX_PATH + 2)
        var ffd = WIN32_FIND_DATA()
        
        var error : NSError? = nil

        _ = path.withCString(encodedAs: UTF16.self) { path16 in
        _withStackOrHeapBuffer(MemoryLayout<TCHAR>.size * Int(MAX_PATH + 2)) { szDir in
            let buffer = szDir.pointee.memory.assumingMemoryBound(to: UInt16.self)

            let lengthOfArg = wcslen(path16)

            if lengthOfArg > Int(MAX_PATH) - 3 {
                preconditionFailure("Directory path is too long.")
            }

            wcscpy_s(buffer, MAX_PATH, path16)
            _ = "\\*".withCString(encodedAs: UTF16.self) {
                wcscat_s(buffer, MAX_PATH, $0)
            }

            // Find the first file in the directory.

            hFind = FindFirstFileW(buffer, &ffd)

            if (INVALID_HANDLE_VALUE == hFind) 
            {
                let winError = GetLastError()
                print("Error reading folder: \(winError)).")
                error = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoSuchFile.rawValue, userInfo: [NSFilePathErrorKey: path])
                return
            } 
            
            // List all the files in the directory with some info about them.

            repeat
            {

                let entryName = withUnsafePointer(to: &ffd.cFileName.0) {
                    String(decodingCString: $0, as: UTF16.self)
                } 
                if entryName != "." && entryName != ".." {
                    contents.append(entryName)

                    if (ffd.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY)) != 0 { // FIXME: this can all be done in one function; see https://msdn.microsoft.com/en-us/library/aa365200(VS.85).aspx
                        let subPath: String = path + "\\" + entryName

                        let entries = try! subpathsOfDirectory(atPath: subPath)
                        contents.append(contentsOf: entries.map({file in "\(entryName)\\\(file)"}))
                    }
                }

            }
            while (FindNextFileW(hFind, &ffd) != 0)
            
            defer {
                FindClose(hFind)
            }
        }
        }

        if let error = error {
            throw error
        }

        return contents
    }
    
    open func copyItem(atPath srcPath: String, toPath dstPath: String) throws {
        
        let attributes = srcPath.withCString(encodedAs: UTF16.self) { GetFileAttributesW($0) }
        if attributes == UInt32.max { // INVALID_FILE_ATTRIBUTES
            return
        }

        if attributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0 {
            try createDirectory(atPath: dstPath, withIntermediateDirectories: false, attributes: nil)
            let subpaths = try subpathsOfDirectory(atPath: srcPath)
            for subpath in subpaths {
                try copyItem(atPath: srcPath + "\\" + subpath, toPath: dstPath + "\\" + subpath)
            }
        } else {
            if createFile(atPath: dstPath, contents: contents(atPath: srcPath), attributes: nil) == false {
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue, userInfo: [NSFilePathErrorKey : dstPath])
            }
        }
    }
    
    open func moveItem(atPath srcPath: String, toPath dstPath: String) throws {
        guard !self.fileExists(atPath: dstPath) else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteFileExists.rawValue, userInfo: [NSFilePathErrorKey : dstPath])
        }
        if rename(srcPath, dstPath) != 0 {
            if getErrno() == EXDEV {
                // TODO: Copy and delete.
                NSUnimplemented("Cross-device moves not yet implemented")
            } else {
                throw _NSErrorWithErrno(getErrno(), reading: false, path: srcPath)
            }
        }
    }
    
    open func removeItem(atPath path: String) throws {
        if _rmdir(path) == 0 {
            return
        } else if getErrno() == ENOTEMPTY {
            NSUnimplemented()
        } else if getErrno() != ENOTDIR {
            throw _NSErrorWithErrno(getErrno(), reading: false, path: path)
        } else if _unlink(path) != 0 {
            throw _NSErrorWithErrno(getErrno(), reading: false, path: path)
        }
    }
    
    open func copyItem(at srcURL: URL, to dstURL: URL) throws {
        guard srcURL.isFileURL else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnsupportedScheme.rawValue, userInfo: [NSURLErrorKey : srcURL])
        }
        guard dstURL.isFileURL else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnsupportedScheme.rawValue, userInfo: [NSURLErrorKey : dstURL])
        }
        try copyItem(atPath: srcURL.path, toPath: dstURL.path)
    }
    
    open func moveItem(at srcURL: URL, to dstURL: URL) throws {
        guard srcURL.isFileURL else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnsupportedScheme.rawValue, userInfo: [NSURLErrorKey : srcURL])
        }
        guard dstURL.isFileURL else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnsupportedScheme.rawValue, userInfo: [NSURLErrorKey : dstURL])
        }
        try moveItem(atPath: srcURL.path, toPath: dstURL.path)
    }
    
    open func linkItem(at srcURL: URL, to dstURL: URL) throws {
        guard srcURL.isFileURL else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnsupportedScheme.rawValue, userInfo: [NSURLErrorKey : srcURL])
        }
        guard dstURL.isFileURL else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnsupportedScheme.rawValue, userInfo: [NSURLErrorKey : dstURL])
        }
        NSUnimplemented()
        // try linkItem(atPath: srcURL.path, toPath: dstURL.path)
    }
    
    open func removeItem(at url: URL) throws {
        guard url.isFileURL else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnsupportedScheme.rawValue, userInfo: [NSURLErrorKey : url])
        }
        try self.removeItem(atPath: url.path)
    }
    
    /* Process working directory management. Despite the fact that these are instance methods on FileManager, these methods report and change (respectively) the working directory for the entire process. Developers are cautioned that doing so is fraught with peril.
     */
    open var currentDirectoryPath: String {
        let length = Int(PATH_MAX) + 1
        var buf = [Int8](repeating: 0, count: length)
        _getcwd(&buf, Int32(length))
        let result = String(cString: buf)//self.string(withFileSystemRepresentation: buf, length: Int(strlen(buf)))
        return result
    }
    
    @discardableResult
    open func changeCurrentDirectoryPath(_ path: String) -> Bool {
        return _chdir(path) == 0
    }
    
    /* The following methods are of limited utility. Attempting to predicate behavior based on the current state of the filesystem or a particular file on the filesystem is encouraging odd behavior in the face of filesystem race conditions. It's far better to attempt an operation (like loading a file or creating a directory) and handle the error gracefully than it is to try to figure out ahead of time whether the operation will succeed.
     */
    open func fileExists(atPath path: String) -> Bool {
        return self.fileExists(atPath: path, isDirectory: nil)
    }
    
    open func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<Bool>?) -> Bool {
        let fileType = path.withCString(encodedAs: UTF16.self) { GetFileAttributesW($0) }
        isDirectory?.pointee = (fileType & DWORD(FILE_ATTRIBUTE_DIRECTORY)) != 0
        return fileType != UInt32.max // INVALID_FILE_ATTRIBUTES
    }
    
    open func isReadableFile(atPath path: String) -> Bool {
        return _access(path, 4) == 0
    }
    
    open func isWritableFile(atPath path: String) -> Bool {
        return _access(path, 2) == 0
    }
    
    open func isExecutableFile(atPath path: String) -> Bool {
        return _access(path, 1) == 0
    }

    /* enumeratorAtPath: returns an NSDirectoryEnumerator rooted at the provided path. If the enumerator cannot be created, this returns NULL. Because NSDirectoryEnumerator is a subclass of NSEnumerator, the returned object can be used in the for...in construct.
     */
    open func enumerator(atPath path: String) -> DirectoryEnumerator? {
        return NSPathDirectoryEnumerator(path: path)
    }
    
    /* enumeratorAtURL:includingPropertiesForKeys:options:errorHandler: returns an NSDirectoryEnumerator rooted at the provided directory URL. The NSDirectoryEnumerator returns URLs from the -nextObject method. The optional 'includingPropertiesForKeys' parameter indicates which resource properties should be pre-fetched and cached with each enumerated URL. The optional 'errorHandler' block argument is invoked when an error occurs. Parameters to the block are the URL on which an error occurred and the error. When the error handler returns YES, enumeration continues if possible. Enumeration stops immediately when the error handler returns NO.
    
        If you wish to only receive the URLs and no other attributes, then pass '0' for 'options' and an empty NSArray ('[NSArray array]') for 'keys'. If you wish to have the property caches of the vended URLs pre-populated with a default set of attributes, then pass '0' for 'options' and 'nil' for 'keys'.
     */
    // Note: Because the error handler is an optional block, the compiler treats it as @escaping by default. If that behavior changes, the @escaping will need to be added back.
    open func enumerator(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: DirectoryEnumerationOptions = [], errorHandler handler: (/* @escaping */ (URL, Error) -> Bool)? = nil) -> DirectoryEnumerator? {
        if mask.contains(.skipsPackageDescendants) || mask.contains(.skipsHiddenFiles) {
            NSUnimplemented("Enumeration options not yet implemented")
        }
        #if os(Windows)
            NSUnimplemented()
        #else
            return URLDirectoryEnumerator(url: url, options: mask, errorHandler: handler)
        #endif
    }
    
    /* subpathsAtPath: returns an NSArray of all contents and subpaths recursively from the provided path. This may be very expensive to compute for deep filesystem hierarchies, and should probably be avoided.
     */
    open func subpaths(atPath path: String) -> [String]? {
        NSUnimplemented()
    }
    
    /* These methods are provided here for compatibility. The corresponding methods on NSData which return NSErrors should be regarded as the primary method of creating a file from an NSData or retrieving the contents of a file as an NSData.
     */
    open func contents(atPath path: String) -> Data? {
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }
    
    open func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey : Any]? = nil) -> Bool {
        do {
            try (data ?? Data()).write(to: URL(fileURLWithPath: path), options: .atomic)
            if attr != nil {
                print("Warning: attributes ignored for FileManager.createDirectory on Windows.")
            }
            return true
        } catch {
            print("Error creating file: \(error)")
            return false
        }
    }
    
}

extension FileManager {
    public func replaceItemAt(_ originalItemURL: URL, withItemAt newItemURL: URL, backupItemName: String? = nil, options: ItemReplacementOptions = []) throws -> URL? {
        NSUnimplemented()
    }
}

extension FileManager {
    open var homeDirectoryForCurrentUser: URL {
        NSUnimplemented()
    }
    
    open var temporaryDirectory: URL {
        return URL(fileURLWithPath: NSTemporaryDirectory())
    }
    
    open func homeDirectory(forUser userName: String) -> URL? {
        guard !userName.isEmpty else { return nil }
        NSUnimplemented()
    }
}

extension FileManager {
    public struct VolumeEnumerationOptions : OptionSet {
        public let rawValue : UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        /* The mounted volume enumeration will skip hidden volumes.
         */
        public static let skipHiddenVolumes = VolumeEnumerationOptions(rawValue: 1 << 1)

        /* The mounted volume enumeration will produce file reference URLs rather than path-based URLs.
         */
        public static let produceFileReferenceURLs = VolumeEnumerationOptions(rawValue: 1 << 2)
    }
    
    public struct DirectoryEnumerationOptions : OptionSet {
        public let rawValue : UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        /* NSDirectoryEnumerationSkipsSubdirectoryDescendants causes the NSDirectoryEnumerator to perform a shallow enumeration and not descend into directories it encounters.
         */
        public static let skipsSubdirectoryDescendants = DirectoryEnumerationOptions(rawValue: 1 << 0)

        /* NSDirectoryEnumerationSkipsPackageDescendants will cause the NSDirectoryEnumerator to not descend into packages.
         */
        public static let skipsPackageDescendants = DirectoryEnumerationOptions(rawValue: 1 << 1)

        /* NSDirectoryEnumerationSkipsHiddenFiles causes the NSDirectoryEnumerator to not enumerate hidden files.
         */
        public static let skipsHiddenFiles = DirectoryEnumerationOptions(rawValue: 1 << 2)
    }

    public struct ItemReplacementOptions : OptionSet {
        public let rawValue : UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        /* Causes -replaceItemAtURL:withItemAtURL:backupItemName:options:resultingItemURL:error: to use metadata from the new item only and not to attempt to preserve metadata from the original item.
         */
        public static let usingNewMetadataOnly = ItemReplacementOptions(rawValue: 1 << 0)

        /* Causes -replaceItemAtURL:withItemAtURL:backupItemName:options:resultingItemURL:error: to leave the backup item in place after a successful replacement. The default behavior is to remove the item.
         */
        public static let withoutDeletingBackupItem = ItemReplacementOptions(rawValue: 1 << 1)
    }

    public enum URLRelationship : Int {
        case contains
        case same
        case other
    }
}

public struct FileAttributeKey : RawRepresentable, Equatable, Hashable {
    public let rawValue: String
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public var hashValue: Int {
        return self.rawValue.hashValue
    }
    
    public static func ==(_ lhs: FileAttributeKey, _ rhs: FileAttributeKey) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
    
    public static let type = FileAttributeKey(rawValue: "NSFileType")
    public static let size = FileAttributeKey(rawValue: "NSFileSize")
    public static let modificationDate = FileAttributeKey(rawValue: "NSFileModificationDate")
    public static let referenceCount = FileAttributeKey(rawValue: "NSFileReferenceCount")
    public static let deviceIdentifier = FileAttributeKey(rawValue: "NSFileDeviceIdentifier")
    public static let ownerAccountName = FileAttributeKey(rawValue: "NSFileOwnerAccountName")
    public static let groupOwnerAccountName = FileAttributeKey(rawValue: "NSFileGroupOwnerAccountName")
    public static let posixPermissions = FileAttributeKey(rawValue: "NSFilePosixPermissions")
    public static let systemNumber = FileAttributeKey(rawValue: "NSFileSystemNumber")
    public static let systemFileNumber = FileAttributeKey(rawValue: "NSFileSystemFileNumber")
    public static let extensionHidden = FileAttributeKey(rawValue: "NSFileExtensionHidden")
    public static let hfsCreatorCode = FileAttributeKey(rawValue: "NSFileHFSCreatorCode")
    public static let hfsTypeCode = FileAttributeKey(rawValue: "NSFileHFSTypeCode")
    public static let immutable = FileAttributeKey(rawValue: "NSFileImmutable")
    public static let appendOnly = FileAttributeKey(rawValue: "NSFileAppendOnly")
    public static let creationDate = FileAttributeKey(rawValue: "NSFileCreationDate")
    public static let ownerAccountID = FileAttributeKey(rawValue: "NSFileOwnerAccountID")
    public static let groupOwnerAccountID = FileAttributeKey(rawValue: "NSFileGroupOwnerAccountID")
    public static let busy = FileAttributeKey(rawValue: "NSFileBusy")
    public static let systemSize = FileAttributeKey(rawValue: "NSFileSystemSize")
    public static let systemFreeSize = FileAttributeKey(rawValue: "NSFileSystemFreeSize")
    public static let systemNodes = FileAttributeKey(rawValue: "NSFileSystemNodes")
    public static let systemFreeNodes = FileAttributeKey(rawValue: "NSFileSystemFreeNodes")
}

public struct FileAttributeType : RawRepresentable, Equatable, Hashable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var hashValue: Int {
        return self.rawValue.hashValue
    }

    public static func ==(_ lhs: FileAttributeType, _ rhs: FileAttributeType) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }

    public static let typeDirectory = FileAttributeType(rawValue: "NSFileTypeDirectory")
    public static let typeRegular = FileAttributeType(rawValue: "NSFileTypeRegular")
    public static let typeSymbolicLink = FileAttributeType(rawValue: "NSFileTypeSymbolicLink")
    public static let typeSocket = FileAttributeType(rawValue: "NSFileTypeSocket")
    public static let typeCharacterSpecial = FileAttributeType(rawValue: "NSFileTypeCharacterSpecial")
    public static let typeBlockSpecial = FileAttributeType(rawValue: "NSFileTypeBlockSpecial")
    public static let typeUnknown = FileAttributeType(rawValue: "NSFileTypeUnknown")
}

public protocol FileManagerDelegate : NSObjectProtocol {
    
    /* fileManager:shouldCopyItemAtPath:toPath: gives the delegate an opportunity to filter the resulting copy. Returning YES from this method will allow the copy to happen. Returning NO from this method causes the item in question to be skipped. If the item skipped was a directory, no children of that directory will be copied, nor will the delegate be notified of those children.
     */
    func fileManager(_ fileManager: FileManager, shouldCopyItemAtPath srcPath: String, toPath dstPath: String) -> Bool
    func fileManager(_ fileManager: FileManager, shouldCopyItemAt srcURL: URL, to dstURL: URL) -> Bool
    
    /* fileManager:shouldProceedAfterError:copyingItemAtPath:toPath: gives the delegate an opportunity to recover from or continue copying after an error. If an error occurs, the error object will contain an NSError indicating the problem. The source path and destination paths are also provided. If this method returns YES, the FileManager instance will continue as if the error had not occurred. If this method returns NO, the FileManager instance will stop copying, return NO from copyItemAtPath:toPath:error: and the error will be provied there.
     */
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, copyingItemAtPath srcPath: String, toPath dstPath: String) -> Bool
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, copyingItemAt srcURL: URL, to dstURL: URL) -> Bool
    
    /* fileManager:shouldMoveItemAtPath:toPath: gives the delegate an opportunity to not move the item at the specified path. If the source path and the destination path are not on the same device, a copy is performed to the destination path and the original is removed. If the copy does not succeed, an error is returned and the incomplete copy is removed, leaving the original in place.
    
     */
    func fileManager(_ fileManager: FileManager, shouldMoveItemAtPath srcPath: String, toPath dstPath: String) -> Bool
    func fileManager(_ fileManager: FileManager, shouldMoveItemAt srcURL: URL, to dstURL: URL) -> Bool
    
    /* fileManager:shouldProceedAfterError:movingItemAtPath:toPath: functions much like fileManager:shouldProceedAfterError:copyingItemAtPath:toPath: above. The delegate has the opportunity to remedy the error condition and allow the move to continue.
     */
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, movingItemAtPath srcPath: String, toPath dstPath: String) -> Bool
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, movingItemAt srcURL: URL, to dstURL: URL) -> Bool
    
    /* fileManager:shouldLinkItemAtPath:toPath: acts as the other "should" methods, but this applies to the file manager creating hard links to the files in question.
     */
    func fileManager(_ fileManager: FileManager, shouldLinkItemAtPath srcPath: String, toPath dstPath: String) -> Bool
    func fileManager(_ fileManager: FileManager, shouldLinkItemAt srcURL: URL, to dstURL: URL) -> Bool
    
    /* fileManager:shouldProceedAfterError:linkingItemAtPath:toPath: allows the delegate an opportunity to remedy the error which occurred in linking srcPath to dstPath. If the delegate returns YES from this method, the linking will continue. If the delegate returns NO from this method, the linking operation will stop and the error will be returned via linkItemAtPath:toPath:error:.
     */
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, linkingItemAtPath srcPath: String, toPath dstPath: String) -> Bool
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, linkingItemAt srcURL: URL, to dstURL: URL) -> Bool
    
    /* fileManager:shouldRemoveItemAtPath: allows the delegate the opportunity to not remove the item at path. If the delegate returns YES from this method, the FileManager instance will attempt to remove the item. If the delegate returns NO from this method, the remove skips the item. If the item is a directory, no children of that item will be visited.
     */
    func fileManager(_ fileManager: FileManager, shouldRemoveItemAtPath path: String) -> Bool
    func fileManager(_ fileManager: FileManager, shouldRemoveItemAt URL: URL) -> Bool
    
    /* fileManager:shouldProceedAfterError:removingItemAtPath: allows the delegate an opportunity to remedy the error which occurred in removing the item at the path provided. If the delegate returns YES from this method, the removal operation will continue. If the delegate returns NO from this method, the removal operation will stop and the error will be returned via linkItemAtPath:toPath:error:.
     */
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, removingItemAtPath path: String) -> Bool
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, removingItemAt URL: URL) -> Bool
}

extension FileManagerDelegate {
    func fileManager(_ fileManager: FileManager, shouldCopyItemAtPath srcPath: String, toPath dstPath: String) -> Bool { return true }
    func fileManager(_ fileManager: FileManager, shouldCopyItemAtURL srcURL: URL, toURL dstURL: URL) -> Bool { return true }

    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, copyingItemAtPath srcPath: String, toPath dstPath: String) -> Bool { return false }
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, copyingItemAtURL srcURL: URL, toURL dstURL: URL) -> Bool { return false }

    func fileManager(_ fileManager: FileManager, shouldMoveItemAtPath srcPath: String, toPath dstPath: String) -> Bool { return true }
    func fileManager(_ fileManager: FileManager, shouldMoveItemAtURL srcURL: URL, toURL dstURL: URL) -> Bool { return true }

    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, movingItemAtPath srcPath: String, toPath dstPath: String) -> Bool { return false }
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, movingItemAtURL srcURL: URL, toURL dstURL: URL) -> Bool { return false }

    func fileManager(_ fileManager: FileManager, shouldLinkItemAtPath srcPath: String, toPath dstPath: String) -> Bool { return true }
    func fileManager(_ fileManager: FileManager, shouldLinkItemAtURL srcURL: URL, toURL dstURL: URL) -> Bool { return true }

    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, linkingItemAtPath srcPath: String, toPath dstPath: String) -> Bool { return false }
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, linkingItemAtURL srcURL: URL, toURL dstURL: URL) -> Bool { return false }

    func fileManager(_ fileManager: FileManager, shouldRemoveItemAtPath path: String) -> Bool { return true }
    func fileManager(_ fileManager: FileManager, shouldRemoveItemAtURL url: URL) -> Bool { return true }

    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, removingItemAtPath path: String) -> Bool { return false }
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, removingItemAtURL url: URL) -> Bool { return false }
}

extension FileManager {
    open class DirectoryEnumerator : NSEnumerator {
        
        /* For NSDirectoryEnumerators created with -enumeratorAtPath:, the -fileAttributes and -directoryAttributes methods return an NSDictionary containing the keys listed below. For NSDirectoryEnumerators created with -enumeratorAtURL:includingPropertiesForKeys:options:errorHandler:, these two methods return nil.
         */
        open var fileAttributes: [FileAttributeKey : Any]? {
            NSRequiresConcreteImplementation()
        }
        open var directoryAttributes: [FileAttributeKey : Any]? {
            NSRequiresConcreteImplementation()
        }
        
        /* This method returns the number of levels deep the current object is in the directory hierarchy being enumerated. The directory passed to -enumeratorAtURL:includingPropertiesForKeys:options:errorHandler: is considered to be level 0.
         */
        open var level: Int {
            NSRequiresConcreteImplementation()
        }
        
        open func skipDescendants() {
            NSRequiresConcreteImplementation()
        }
    }

    internal class NSPathDirectoryEnumerator: DirectoryEnumerator {
        let baseURL: URL
        let innerEnumerator : DirectoryEnumerator
        override var fileAttributes: [FileAttributeKey : Any]? {
            NSUnimplemented()
        }
        override var directoryAttributes: [FileAttributeKey : Any]? {
            NSUnimplemented()
        }
        
        override var level: Int {
            NSUnimplemented()
        }
        
        override func skipDescendants() {
            NSUnimplemented()
        }
        
        init?(path: String) {
            let url = URL(fileURLWithPath: path)
            self.baseURL = url
            guard let ie = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: nil) else {
                return nil
            }
            self.innerEnumerator = ie
        }
        
        override func nextObject() -> Any? {
            let o = innerEnumerator.nextObject()
            guard let url = o as? URL else {
                return nil
            }
            let path = url.path.replacingOccurrences(of: baseURL.path+"\\", with: "")
            return path
        }

    }
}
