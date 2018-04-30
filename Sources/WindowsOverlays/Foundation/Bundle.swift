// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//

import Windows

open class Bundle: NSObject {
    private var _url : URL

    private static var _mainBundle : Bundle = {
        let requiredLength = GetCurrentDirectoryW(0, nil)
        var buffer = [UInt16](repeating: 0, count: Int(requiredLength))
        GetCurrentDirectoryW(1024, &buffer)

        return Bundle(path: String(decodingCString: buffer, as: UTF16.self))!
    }()
    
    open class var main: Bundle {
        get {
            return _mainBundle
        }
    }
    
    open class var allBundles: [Bundle] {
        NSUnimplemented()
    }

    public init?(path: String) {
        
        // TODO: We do not yet resolve symlinks, but we must for compatibility
        // let resolvedPath = path.stringByResolvingSymlinksInPath
        let resolvedPath = path
        guard !resolvedPath.isEmpty else {
            return nil
        }
        
        let url = URL(fileURLWithPath: resolvedPath)
        self._url = url

        super.init()
    }
    
    public convenience init?(url: URL) {
        self.init(path: url.path)
    }
    
    public init(for aClass: AnyClass) { NSUnimplemented() }
    
    override open var description: String {
        return "\(String(describing: Bundle.self)) <\(bundleURL.path)> (\(isLoaded  ? "loaded" : "not yet loaded"))"
    }

    
    /* Methods for loading and unloading bundles. */
    open func load() -> Bool {
        return true
    }
    open var isLoaded: Bool {
        return true
    }
    
    open func preflight() throws {
        
    }
    
    open func loadAndReturnError() throws {
       
    }

    
    /* Methods for locating various components of a bundle. */
    open var bundleURL: URL {
        return self._url
    }
    
    open var resourceURL: URL? {
        return self._url.appendingPathComponent("Resources")
    }
    
    open var executableURL: URL? {
        return nil
    }
    
    open func url(forAuxiliaryExecutable executableName: String) -> URL? {
        return nil
    }
    
    open var privateFrameworksURL: URL? {
        return nil
    }
    
    open var sharedFrameworksURL: URL? {
        return nil
    }
    
    open var sharedSupportURL: URL? {
        return nil
    }
    
    open var builtInPlugInsURL: URL? {
        return nil
    }
    
    open var appStoreReceiptURL: URL? {
        // Always nil on this platform
        return nil
    }
    
    open var bundlePath: String {
        return bundleURL.path
    }
    
    open var resourcePath: String? {
        return self.resourceURL?.path
    }
    
    open var executablePath: String? {
        return executableURL?.path
    }
    
    open func path(forAuxiliaryExecutable executableName: String) -> String? {
        return url(forAuxiliaryExecutable: executableName)?.path
    }
    
    open var privateFrameworksPath: String? {
        return privateFrameworksURL?.path
    }
    
    open var sharedFrameworksPath: String? {
        return sharedFrameworksURL?.path
    }
    
    open var sharedSupportPath: String? {
        return sharedSupportURL?.path
    }
    
    open var builtInPlugInsPath: String? {
        return builtInPlugInsURL?.path
    }
}