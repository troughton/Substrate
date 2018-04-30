// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//


import CFoundationExtras

import Windows

let MAX_PATH = 260
let PATH_MAX = MAX_PATH 

public func NSTemporaryDirectory() -> String {
    // https://msdn.microsoft.com/en-us/library/windows/desktop/aa364992(v=vs.85).aspx
    var pathBuffer = [UInt16](repeating: 0, count: MAX_PATH + 2)

    let _ = GetTempPathW(DWORD(pathBuffer.count), &pathBuffer)

    return String(decodingCString: pathBuffer, as: UTF16.self)
}

internal extension String {
    
    internal var _startOfLastPathComponent : String.Index {
        precondition(!hasSuffix("\\") && self.count > 1)
        
        let startPos = startIndex
        var curPos = endIndex
        
        // Find the beginning of the component
        while curPos > startPos {
            let prevPos = index(before: curPos)
            if self[prevPos] == "\\" {
                break
            }
            curPos = prevPos
        }
        return curPos

    }

    internal var _startOfPathExtension : String.Index? {
        precondition(!hasSuffix("\\"))

        var currentPosition = endIndex
        let startOfLastPathComponent = _startOfLastPathComponent

        // Find the beginning of the extension
        while currentPosition > startOfLastPathComponent {
            let previousPosition = index(before: currentPosition)
            let character = self[previousPosition]
            if character == "\\" {
                return nil
            } else if character == "." {
                if startOfLastPathComponent == previousPosition {
                    return nil
                } else if case let previous2Position = index(before: previousPosition),
                    previousPosition == index(before: endIndex) &&
                    previous2Position == startOfLastPathComponent &&
                    self[previous2Position] == "."
                {
                    return nil
                } else {
                    return currentPosition
                }
            }
            currentPosition = previousPosition
        }
        return nil
    }

    internal var absolutePath: Bool {
        return hasPrefix("~") || hasPrefix("\\")
    }
    
    internal func _stringByAppendingPathComponent(_ str: String, doneAppending : Bool = true) -> String {
        if str.isEmpty {
            return self
        }
        if isEmpty {
            return str
        }
        if hasSuffix("\\") {
            return self + str
        }
        return self + "\\" + str
    }
    
    internal func _stringByFixingSlashes(compress : Bool = true, stripTrailing: Bool = true) -> String {
        var result = self
        if compress {
                let startPos = result.startIndex
                var endPos = result.endIndex
                var curPos = startPos
                
                while curPos < endPos {
                    if result[curPos] == "\\" {
                        var afterLastSlashPos = curPos
                        while afterLastSlashPos < endPos && result[afterLastSlashPos] == "\\" {
                            afterLastSlashPos = result.index(after: afterLastSlashPos)
                        }
                        if afterLastSlashPos != result.index(after: curPos) {
                            result.replaceSubrange(curPos ..< afterLastSlashPos, with: ["\\"])
                            endPos = result.endIndex
                        }
                        curPos = afterLastSlashPos
                    } else {
                        curPos = result.index(after: curPos)
                    }
                }
        }
        if stripTrailing && result.count > 1 && result.hasSuffix("\\") {
            result.remove(at: result.index(before: result.endIndex))
        }
        return result
    }
    
    internal func _stringByRemovingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else {
            return self
        }

        var temp = self
        temp.removeSubrange(startIndex..<prefix.endIndex)
        return temp
    }
    
    internal func _tryToRemovePathPrefix(_ prefix: String) -> String? {
        guard self != prefix else {
            return nil
        }
        
        let temp = _stringByRemovingPrefix(prefix)
        if FileManager.default.fileExists(atPath: temp) {
            return temp
        }
        
        return nil
    }
}

public extension String {
    
    public var isAbsolutePath: Bool {
        return hasPrefix("~") || hasPrefix("\\")
    }
    
    public static func pathWithComponents(_ components: [String]) -> String {
        var result = ""
        for comp in components.prefix(components.count - 1) {
            result = result._stringByAppendingPathComponent(comp._stringByFixingSlashes(), doneAppending: false)
        }
        if let last = components.last {
            result = result._stringByAppendingPathComponent(last._stringByFixingSlashes(), doneAppending: true)
        }
        return result
    }
    
    public var pathComponents : [String] {
        return _pathComponents(self)!
    }
    
    public var lastPathComponent : String {
        let fixedSelf = _stringByFixingSlashes()
        if fixedSelf.count <= 1 {
            return fixedSelf
        }
        
        return String(fixedSelf.suffix(from: fixedSelf._startOfLastPathComponent))
    }
    
    public var deletingLastPathComponent : String {
        let fixedSelf = _stringByFixingSlashes()
        if fixedSelf == "\\" {
            return fixedSelf
        }
        
        switch fixedSelf._startOfLastPathComponent {
        
        // relative path, single component
        case fixedSelf.startIndex:
            return ""
        
        // absolute path, single component
        case fixedSelf.index(after: fixedSelf.startIndex):
            return "\\"
        
        // all common cases
        case let startOfLast:
            return String(fixedSelf.prefix(upTo: fixedSelf.index(before: startOfLast)))
        }
    }
    
    public func appendingPathComponent(_ str: String) -> String {
        return _stringByAppendingPathComponent(str)
    }
    
    public var pathExtension : String {
        let fixedSelf = _stringByFixingSlashes()
        if fixedSelf.count <= 1 {
            return ""
        }

        if let extensionPos = fixedSelf._startOfPathExtension {
            return String(fixedSelf.suffix(from: extensionPos))
        } else {
            return ""
        }
    }
    
    public var deletingPathExtension: String {
        let fixedSelf = _stringByFixingSlashes()
        if fixedSelf.count <= 1 {
            return fixedSelf
        }
        if let extensionPos = fixedSelf._startOfPathExtension {
            return String(fixedSelf.prefix(upTo: fixedSelf.index(before: extensionPos)))
        } else {
            return fixedSelf
        }
    }
    
    public func appendingPathExtension(_ str: String) -> String? {
        if str.hasPrefix("\\") || self == "" || self == "\\" {
            print("Cannot append extension \(str) to path \(self)")
            return nil
        }
        let result = self._stringByFixingSlashes(compress: false, stripTrailing: true) + "." + str
        return result._stringByFixingSlashes()
    }

    public var expandingTildeInPath: String {
        guard hasPrefix("~") else {
            return self
        }

        let endOfUserName = self.index(of: "\\") ?? self.endIndex
        let startOfUserName = self.index(after: self.startIndex)
        let userName = String(self[startOfUserName..<endOfUserName])
        let optUserName: String? = userName.isEmpty ? nil : userName
        
        guard let homeDir = NSHomeDirectoryForUser(optUserName) else {
            return self._stringByFixingSlashes(compress: false, stripTrailing: true)
        }
        
        var result = self
        result.replaceSubrange(self.startIndex..<endOfUserName, with: homeDir)
        result = result._stringByFixingSlashes(compress: false, stripTrailing: true)
        
        return result
    }
    
    public var standardizingPath: String {
        let expanded = expandingTildeInPath
        let resolved = expanded.resolvingSymlinksInPath
        return resolved
    }
    
    public var resolvingSymlinksInPath: String {
        var components = pathComponents
        guard !components.isEmpty else {
            return self
        }
        
        // TODO: pathComponents keeps final path separator if any. Check that logic.
        if components.last == "\\" {
            components.removeLast()
        }
        
        let isAbsolutePath = components.first == "\\"
        
        var resolvedPath = components.removeFirst()
        for component in components {
            switch component {
                
            case "", ".":
                break
                
            case ".." where isAbsolutePath:
                resolvedPath = resolvedPath.deletingLastPathComponent
                
            default:
                resolvedPath = resolvedPath.appendingPathComponent(component)
                // if let destination = FileManager.default._tryToResolveTrailingSymlinkInPath(resolvedPath) {
                //     resolvedPath = destination
                // }
            }
        }
        
        let privatePrefix = "/private"
        resolvedPath = resolvedPath._tryToRemovePathPrefix(privatePrefix) ?? resolvedPath
        
        return resolvedPath
    }
    
    public func stringsByAppendingPaths(_ paths: [String]) -> [String] {
        if self == "" {
            return paths
        }
        return paths.map(appendingPathComponent)
    }

    internal func _stringIsPathToDirectory(_ path: String) -> Bool {
        if path.last != "\\" && path.last != "\\" {
            return false
        }
        
        var isDirectory: Bool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory
    }
    
    internal typealias _FileNamePredicate = (String?) -> Bool
    
    internal func _getNamesAtURL(_ filePathURL: URL, prependWith: String, namePredicate: _FileNamePredicate, typePredicate: _FileNamePredicate) -> [String] {
        var result: [String] = []
        
        if let enumerator = FileManager.default.enumerator(at: filePathURL, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants, errorHandler: nil) {
            for item in enumerator.lazy.map({ $0 as! URL }) {
                let itemName = item.lastPathComponent
                
                let matchByName = namePredicate(itemName)
                let matchByExtension = typePredicate(item.pathExtension)
                
                if matchByName && matchByExtension {
                    if prependWith.isEmpty {
                        result.append(itemName)
                    } else {
                        result.append(prependWith.appendingPathComponent(itemName))
                    }
                }
            }
        }
        
        return result
    }
    
    fileprivate func _getExtensionPredicate(_ extensions: [String]?, caseSensitive: Bool) -> _FileNamePredicate {
        guard let exts = extensions else {
            return { _ in true }
        }
        
        if caseSensitive {
            let set = Set(exts)
            return { $0 != nil && set.contains($0!) }
        } else {
            let set = Set(exts.map { $0.lowercased() })
            return { $0 != nil && set.contains($0!.lowercased()) }
        }
    }
    
    fileprivate func _getFileNamePredicate(_ prefix: String, caseSensitive: Bool) -> _FileNamePredicate {
        guard !prefix.isEmpty else {
            return { _ in true }
        }

        if caseSensitive {
            return { $0 != nil && $0!.hasPrefix(prefix) }
        } else {
            return { $0 != nil && $0!.lowercased().range(of: prefix).lowerBound == 0 }
        }
    }
    
    internal func _longestCommonPrefix(_ strings: [String], caseSensitive: Bool) -> String? {
        guard !strings.isEmpty else {
            return nil
        }
        
        guard strings.count > 1 else {
            return strings.first
        }
        
        var sequences = strings.map({ $0.makeIterator() })
        var prefix: [Character] = []
        loop: while true {
            var char: Character? = nil
            for (idx, s) in sequences.enumerated() {
                var seq = s
                
                guard let c = seq.next() else {
                    break loop
                }
                
                if let char = char {
                    let lhs = caseSensitive ? char : String(char).lowercased().first!
                    let rhs = caseSensitive ? c : String(c).lowercased().first!
                    if lhs != rhs {
                        break loop
                    }
                } else {
                    char = c
                }
                
                sequences[idx] = seq
            }
            prefix.append(char!)
        }
        
        return String(prefix)
    }
    
    internal func _ensureLastPathSeparator(_ path: String) -> String {
        if path.hasSuffix("\\") || path.isEmpty {
            return path
        }
        
        return path + "\\"
    }
    
    public var fileSystemRepresentation : UnsafePointer<Int8> {
        NSUnimplemented()
    }
}

extension FileManager {
    public enum SearchPathDirectory: UInt {
        
        case applicationDirectory // supported applications (Applications)
        case demoApplicationDirectory // unsupported applications, demonstration versions (Demos)
        case developerApplicationDirectory // developer applications (Developer/Applications). DEPRECATED - there is no one single Developer directory.
        case adminApplicationDirectory // system and network administration applications (Administration)
        case libraryDirectory // various documentation, support, and configuration files, resources (Library)
        case developerDirectory // developer resources (Developer) DEPRECATED - there is no one single Developer directory.
        case userDirectory // user home directories (Users)
        case documentationDirectory // documentation (Documentation)
        case documentDirectory // documents (Documents)
        case coreServiceDirectory // location of CoreServices directory (System/Library/CoreServices)
        case autosavedInformationDirectory // location of autosaved documents (Documents/Autosaved)
        case desktopDirectory // location of user's desktop
        case cachesDirectory // location of discardable cache files (Library/Caches)
        case applicationSupportDirectory // location of application support files (plug-ins, etc) (Library/Application Support)
        case downloadsDirectory // location of the user's "Downloads" directory
        case inputMethodsDirectory // input methods (Library/Input Methods)
        case moviesDirectory // location of user's Movies directory (~/Movies)
        case musicDirectory // location of user's Music directory (~/Music)
        case picturesDirectory // location of user's Pictures directory (~/Pictures)
        case printerDescriptionDirectory // location of system's PPDs directory (Library/Printers/PPDs)
        case sharedPublicDirectory // location of user's Public sharing directory (~/Public)
        case preferencePanesDirectory // location of the PreferencePanes directory for use with System Preferences (Library/PreferencePanes)
        case applicationScriptsDirectory // location of the user scripts folder for the calling application (~/Library/Application Scripts/code-signing-id)
        case itemReplacementDirectory // For use with NSFileManager's URLForDirectory:inDomain:appropriateForURL:create:error:
        case allApplicationsDirectory // all directories where applications can occur
        case allLibrariesDirectory // all directories where resources can occur
        case trashDirectory // location of Trash directory
    }

    public struct SearchPathDomainMask: OptionSet {
        public let rawValue : UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        public static let userDomainMask = SearchPathDomainMask(rawValue: 1) // user's home directory --- place to install user's personal items (~)
        public static let localDomainMask = SearchPathDomainMask(rawValue: 2) // local to the current machine --- place to install items available to everyone on this machine (/Library)
        public static let networkDomainMask = SearchPathDomainMask(rawValue: 4) // publically available location in the local area network --- place to install items available on the network (/Network)
        public static let systemDomainMask = SearchPathDomainMask(rawValue: 8) // provided by Apple, unmodifiable (/System)
        public static let allDomainsMask = SearchPathDomainMask(rawValue: 0x0ffff) // all domains: all of the above and future items
    }
}

public func NSSearchPathForDirectoriesInDomains(_ directory: FileManager.SearchPathDirectory, _ domainMask: FileManager.SearchPathDomainMask, _ expandTilde: Bool) -> [String] {
    var folderId : KNOWNFOLDERID
    switch directory {
    case .applicationSupportDirectory:
        folderId = FOLDERID_RoamingAppData
    default:
        NSUnimplemented()
    }
    var path : PWSTR! = nil
    let result = SHGetKnownFolderPath(&folderId, 0, nil, &path)
    if result != S_OK {
        return []
    }

    defer { CoTaskMemFree(path) }

    let pathString = String(decodingCString: path, as: UTF16.self)
    return [pathString]
}

public func NSHomeDirectory() -> String {
    return NSHomeDirectoryForUser(nil)!
}

public func NSHomeDirectoryForUser(_ user: String?) -> String? {
    NSUnimplemented()
}

public func NSUserName() -> String {
    NSUnimplemented()
}

internal func _NSCreateTemporaryFile(_ filePath: String) throws -> (Int32, String) {
    NSUnimplemented()
    // let template = "." + filePath + ".tmp.XXXXXX"
    // let maxLength = Int(PATH_MAX) + 1
    // var buf = [Int8](repeating: 0, count: maxLength)
    // let _ = template.getFileSystemRepresentation(&buf, maxLength: maxLength)
    // let fd = mkstemp(&buf)
    // if fd == -1 {
    //     throw _NSErrorWithErrno(getErrno(), reading: false, path: filePath)
    // }
    // let pathResult = FileManager.default.string(withFileSystemRepresentation: buf, length: Int(strlen(buf)))
    // return (fd, pathResult)

    // var tempFileName = [UInt16](repeating: 0, count: Int(MAX_PATH))
    // let result = dirPath.withCString(encodedAs: UTF16.self) { dirPath in 
    //     "tmp".withCString(encodedAs: UTF16.self) { tmpPrefix in
    //         GetTempFileNameW(dirPath, tmpPrefix, 0, &tempFileName)
    //     }
    // }
    // let fd = _wopenNoMode(tempFileName, _O_WRONLY)
    // let tempFilePath = String(decodingCString: tempFileName, as: UTF16.self) // FileManager.default.string(withFileSystemRepresentation:buf, length: Int(strlen(buf)))
    // return (fd, tempFilePath) 
}

internal func _NSCleanupTemporaryFile(_ auxFilePath: String, _ filePath: String) throws  {
    if rename(auxFilePath, filePath) != 0 {
        do {
            try FileManager.default.removeItem(atPath: auxFilePath)
        } catch _ {
        }
        throw _NSErrorWithErrno(getErrno(), reading: false, path: filePath)
    }
}
