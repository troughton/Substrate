//
//  File.swift
//  
//
//  Created by Thomas Roughton on 30/11/19.
//

import Foundation
import Regex
import SPIRV_Cross

// Need to perform reflection for each SPIR-V target and combine conditionally (e.g. with #if canImport(Vulkan)).

struct EntryPoint : Hashable {
    var name: String
    var type: ShaderType
    var renderPass : String
}

struct InlineUniformBlockBinding: Hashable {
    var set: Int
    var binding: Int
}

struct DXCSourceFile : Equatable {
    static let entryPointPattern = Regex(#"\[shader\(\"(\w+)\"\)\]\s*(?:\[[^\]]+\])*\s*\w+\s([^\(]+)"#)
    static let externalEntryPointPattern = Regex(#"USES-SHADER:\s+(\S+)"#)
    static let inlineUniformBlockPattern = Regex(#"INLINE-UNIFORM-BLOCK:(?:\s*\(((\d+)\s*, (\d+))\)\s*,*)+"#)
    
    let url : URL
    let renderPass : String
    let modificationTime : Date
    let entryPoints : [EntryPoint]
    let externalEntryPoints : Set<String> // Entry points from used from another source file.
    let inlineUniformBlocks : Set<InlineUniformBlockBinding> // Bindings which should be interpreted as inline uniform blocks.
    
    init(url: URL, modificationTimes: [URL : Date]) throws {
        self.url = url
        self.modificationTime = modificationTimes[url] ?? .distantFuture
        let renderPass = url.deletingPathExtension().lastPathComponent
        self.renderPass = renderPass
        
        let fileText = try String(contentsOf: url)
        self.entryPoints = DXCSourceFile.entryPointPattern.allMatches(in: fileText).compactMap { match in
            guard let shaderTypeString = match.captures[0] else { print("No shader type specified for file \(url)"); return nil }
            guard let shaderType = ShaderType(string: shaderTypeString) else { print("Unrecognised shader type \(shaderTypeString) for file \(url)"); return nil }
            return EntryPoint(name: match.captures[1]!, type: shaderType, renderPass: renderPass)
        }
        self.externalEntryPoints = Set(DXCSourceFile.externalEntryPointPattern.allMatches(in: fileText).map { match in
            return match.captures[0]!
        })
        self.inlineUniformBlocks = Set(DXCSourceFile.inlineUniformBlockPattern.allMatches(in: fileText).map { match in
            let binding = Int(match.captures[1]!)!
            let set = Int(match.captures[2]!)!
            return .init(set: set, binding: binding)
        })
    }
    
    static func ==(lhs: DXCSourceFile, rhs: DXCSourceFile) -> Bool {
        return lhs.url == rhs.url && lhs.entryPoints == rhs.entryPoints && lhs.externalEntryPoints == rhs.externalEntryPoints && lhs.inlineUniformBlocks == rhs.inlineUniformBlocks
    }
}

struct SPIRVFile {
    let sourceFile : DXCSourceFile
    let url : URL
    let entryPoint : EntryPoint
    let target : Target
    let modificationTime : Date
    
    init(sourceFile: DXCSourceFile, url: URL, entryPoint: EntryPoint, target: Target) {
        self.sourceFile = sourceFile
        self.url = url
        self.entryPoint = entryPoint
        self.target = target
        self.modificationTime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
    
    var exists : Bool {
        return FileManager.default.fileExists(atPath: self.url.path)
    }
    
    var inlineUniformBlocks : Set<InlineUniformBlockBinding> {
        return self.sourceFile.inlineUniformBlocks
    }
}

extension SPIRVFile : CustomStringConvertible {
    var description: String {
        return "SPIRVFile { renderPass: \(sourceFile.renderPass), entryPoint: \(entryPoint.name), target: \(target) }"
    }
}

extension FileManager {
    func createDirectoryIfNeeded(at url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }
}

extension URL {
    func needsGeneration(sourceFile: URL) -> Bool {
        let sourceFileDate = (try? sourceFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture
        
        let modificationDate = (try? self.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return modificationDate < sourceFileDate
    }
    
    func needsGeneration(sourceFileDate: Date) -> Bool {
        let modificationDate = (try? self.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return modificationDate < sourceFileDate
    }
}

enum ShaderCompilerError : Error {
    case missingSourceDirectory(URL)
    case duplicateTarget(Target)
}

func computeSourceFileModificationTimes(_ files: [URL]) -> [URL : Date] {

    let includeRegexPattern = Regex("#include(?:\\s+)\"([^\"]+)\"")
    
    var modificationTimes = [URL: Date]()
    
    func computeFileModification(file: URL) {
        if modificationTimes[file] != nil {
            return
        }
        
        let directory = file.deletingLastPathComponent()
        var modificationTime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
        
        if let fileText = try? String(contentsOf: file) {
            let includedFiles = includeRegexPattern.allMatches(in: fileText)
            
            for include in includedFiles {
                let fullIncludeURL = directory.appendingPathComponent(include.captures[0]!).standardized
                if fullIncludeURL == file {
                    print("Warning: recursive include in \(file)")
                    continue
                }
                
                computeFileModification(file: fullIncludeURL)
                modificationTime = max(modificationTime, modificationTimes[fullIncludeURL] ?? .distantPast)
            }
            
            modificationTimes[file] = modificationTime
        }
    }
    
    for file in files {
        computeFileModification(file: file)
    }
    
    return modificationTimes
}

final class ShaderCompiler {
    let baseDirectory : URL
    let sourceDirectory : URL
    let reflectionFile : URL?
    let compileWithDebugInfo: Bool
    let legalizeHLSL: Bool
    let invariantPosition: Bool
    
    let sourceFiles : [DXCSourceFile]
    let targets : [Target]
    
    let dxcDriver : DXCDriver
    let spirvOptDriver : SPIRVOptDriver?
    
    let context = SPIRVContext()
    let reflectionContext = ReflectionContext()
    
    let needsGenerateReflection : Bool
    
    var spirvCompilers : [SPIRVCompiler] = []
    
    init(directory: URL, reflectionFile: URL? = nil, targets: [Target] = [.defaultTarget], compileWithDebugInfo: Bool, legalizeHLSL: Bool, invariantPosition: Bool) throws {
        self.baseDirectory = directory
        self.sourceDirectory = directory.appendingPathComponent("Source/RenderPasses")
        self.reflectionFile = reflectionFile
        self.compileWithDebugInfo = compileWithDebugInfo
        self.legalizeHLSL = legalizeHLSL
        self.invariantPosition = invariantPosition

        for (i, target) in targets.enumerated() {
            guard !targets.dropFirst(i + 1).contains(target) else {
                throw ShaderCompilerError.duplicateTarget(target)
            }
        }
        
        self.targets = targets

        self.dxcDriver = try DXCDriver()
        
        if self.legalizeHLSL {
            self.spirvOptDriver = try SPIRVOptDriver()
        } else {
            self.spirvOptDriver = nil
        }
        
        guard FileManager.default.fileExists(atPath: self.sourceDirectory.path) else {
            throw ShaderCompilerError.missingSourceDirectory(self.sourceDirectory)
        }
        
        for target in targets {
            let spirvDirectory = self.baseDirectory.appendingPathComponent(target.spirvDirectory)
            try FileManager.default.createDirectoryIfNeeded(at: spirvDirectory)
        }
        
        var directoryContents: [URL] = []
        if let directoryEnumerator = FileManager.default.enumerator(at: sourceDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .nameKey]) {
            for case let fileURL as URL in directoryEnumerator {
                if fileURL.pathExtension.lowercased() == "hlsl" {
                    directoryContents.append(fileURL)
                }
            }
        }
        
        let modificationTimes = computeSourceFileModificationTimes(directoryContents)
        
        let mostRecentModificationDate = modificationTimes.values.max() ?? .distantFuture
        
        self.sourceFiles = directoryContents.compactMap {
            try? DXCSourceFile(url: $0, modificationTimes: modificationTimes)
        }
        
        if let reflectionFile = reflectionFile,
            FileManager.default.fileExists(atPath: reflectionFile.path),
            let reflectionModificationDate = try? reflectionFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
            mostRecentModificationDate < reflectionModificationDate {
            self.needsGenerateReflection = false
        } else {
            self.needsGenerateReflection = true
        }
    }
    
    public func compile() {
        if !self.sourceFiles.isEmpty {
            let spvCompilationGroup = DispatchGroup()
            
            var spirvFiles = [SPIRVFile]()
            print("Compiling SPIR-V:\n")
            
            for target in targets {
                for file in self.sourceFiles {
                    for entryPoint in file.entryPoints {
                        spirvFiles.append(self.compileToSPV(file: file, entryPoint: entryPoint, target: target, group: spvCompilationGroup))
                    }
                }
            }
            
            spvCompilationGroup.wait()
            
            print()
            
            self.spirvCompilers = spirvFiles.compactMap { file in
                guard file.exists else { return nil }
                do {
                    return try SPIRVCompiler(file: file, context: self.context, forceInvariantPosition: self.invariantPosition)
                } catch {
                    print("Error generating SPIRV compiler for file \(file): \(error)")
                    return nil
                }
            }
        }
        
        for target in self.targets {
            guard let compiler = target.compiler else { continue }
            let targetCompilers = self.spirvCompilers.filter { $0.file.target == target }
            do {
                print("Compiling target \(target).\n")
                
                try compiler.compile(spirvCompilers: targetCompilers,
                                     sourceDirectory: self.baseDirectory.appendingPathComponent("Source"),
                                     workingDirectory: self.baseDirectory.appendingPathComponent(target.intermediatesDirectory),
                                     outputDirectory: self.baseDirectory.appendingPathComponent(target.outputDirectory),
                    withDebugInformation: self.compileWithDebugInfo)
                
                print()
            }
            catch {
                print("Compilation failed for target \(target): \(error)")
            }
        }
    }
    
    public func generateReflection() {
        guard let reflectionFile = self.reflectionFile, !self.sourceFiles.isEmpty, self.needsGenerateReflection else { return }
        print("Generating reflection to file \(reflectionFile.path)")
        
        for compiler in self.spirvCompilers {
            do {
                try self.reflectionContext.reflect(compiler: compiler)
            } catch {
                print("Error generating reflection for file \(compiler.file): \(error)")
            }
        }
        
        self.reflectionContext.mergeExternalEntryPoints()
        self.reflectionContext.generateResourceSets()
        self.reflectionContext.fillTypeLookup()
        
        do {
            try self.reflectionContext.printReflection(to: reflectionFile)
        } catch {
            print("Error generating reflection: \(error)")
        }
    }
    
    private func compileToSPV(file: DXCSourceFile, entryPoint: EntryPoint, target: Target, group: DispatchGroup) -> SPIRVFile {
        let spirvDirectory = self.baseDirectory.appendingPathComponent(target.spirvDirectory)
        
        let fileName = file.url.deletingPathExtension().lastPathComponent
        var spvFileURL = spirvDirectory.appendingPathComponent("\(fileName)-\(entryPoint.name).spv")
        
        if spvFileURL.needsGeneration(sourceFileDate: file.modificationTime) {
            DispatchQueue.global().async(group: group) {
                let tempFileURL = spirvDirectory.appendingPathComponent("\(fileName)-\(entryPoint.name)-tmp.spv")
                do {

                    print("\(target): Compiling \(entryPoint.name) in \(file.url.lastPathComponent) to SPIR-V")
                    
                    let task = try self.dxcDriver.compile(sourceFile: file.url, destinationFile: self.legalizeHLSL ? tempFileURL : spvFileURL, entryPoint: entryPoint.name, type: entryPoint.type, target: target)
                    task.waitUntilExit()
                    guard task.terminationStatus == 0 else { print("Error compiling entry point \(entryPoint.name) in file \(file): \(task.terminationReason)"); return }
                    
                    if self.legalizeHLSL {
                        try? FileManager.default.removeItem(at: spvFileURL)
                        
                        let optimisationTask = try self.spirvOptDriver!.optimise(sourceFile: tempFileURL, destinationFile: spvFileURL)
                        optimisationTask.waitUntilExit()
                        if optimisationTask.terminationStatus != 0 {
                            print("Error optimising entry point \(entryPoint.name) in file \(file)")
                        } else {
                            try? FileManager.default.removeItem(at: tempFileURL)
                        }
                        if !FileManager.default.fileExists(atPath: spvFileURL.path) {
                            return
                        }
                    }
                    
                    spvFileURL.removeCachedResourceValue(forKey: .contentModificationDateKey)
                    
                } catch {
                    print("Error compiling entry point \(entryPoint.name) in file \(file): \(error)")
                }
            }
        }
        
        return SPIRVFile(sourceFile: file, url: spvFileURL, entryPoint: entryPoint, target: target)
    }
}
