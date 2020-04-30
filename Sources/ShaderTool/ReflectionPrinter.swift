//
//  ReflectionPrinter.swift
//  ShaderReflectionGenerator
//
//  Created by Thomas Roughton on 7/06/19.
//

import Foundation
import SwiftFrameGraph

struct ReflectionPrinter {
    static let tab = "    "
    
    var buffer = ""
    var indent = 0
    
    private mutating func printLine(_ string: String) {
        for _ in 0..<self.indent {
            self.buffer += ReflectionPrinter.tab
        }
        self.buffer += string
        self.buffer += "\n"
    }
    
    mutating func print(_ string: String) {
        let lines = string.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        
        for line in lines {
            let scopeBegins = line.lazy.filter { $0 == "{" || $0 == "(" }.count
            let scopeEnds = line.lazy.filter { $0 == "}" || $0 == ")" }.count
            let delta = scopeBegins - scopeEnds
            
            if delta < 0 {
                self.indent = max(0, self.indent +  delta)
            }
            
            printLine(line)
            
            if delta > 0 {
                self.indent += delta
            }
        }
    }
    
    mutating func newLine() {
        self.buffer += "\n"
    }
    
    func write(to url: URL) throws {
        try self.buffer.write(to: url, atomically: true, encoding: .utf8)
    }
    
}

extension ReflectionPrinter {
    
    mutating func processEntryPoints(pass: RenderPass, stageName: String, type: ShaderType) {
        let filteredEntryPoints = pass.entryPoints.filter { $0.type == type }
        
        guard !filteredEntryPoints.isEmpty else {
            return
        }
        
        if let sourcePass = filteredEntryPoints.first?.renderPass, sourcePass != pass.name, filteredEntryPoints.allSatisfy({ $0.renderPass == sourcePass }) {
            print("public typealias \(stageName) = \(sourcePass)Reflection.\(stageName)")
            newLine()
            return
        }
        
        print("public enum \(stageName) : String {")
        
        for entryPoint in filteredEntryPoints {
            let name = entryPoint.name
            let entryPointFunctionNameStart = name.lastIndex(of: "_").map { name.index(after: $0) } ?? name.startIndex
            var enumCaseName = String(name[entryPointFunctionNameStart...])
            enumCaseName.replaceSubrange(enumCaseName.startIndex...enumCaseName.startIndex, with: enumCaseName[enumCaseName.startIndex].lowercased())
            
            print("case \(enumCaseName) = \"\(name)\"")
        }
        
        print("}")
        newLine()
    }
    
    mutating func print(pass: RenderPass, typeLookup: TypeLookup) {
        print("public struct \(pass.name)Reflection : RenderPassReflection {")
        newLine()
        
        if pass.attachmentCount > 0 {
            print("public static var attachmentCount : Int { \(pass.attachmentCount) }")
            newLine()
        }
        
        // Entry points
        
        processEntryPoints(pass: pass, stageName: "VertexFunction", type: .vertex)
        processEntryPoints(pass: pass, stageName: "FragmentFunction", type: .fragment)
        processEntryPoints(pass: pass, stageName: "ComputeFunction", type: .compute)
        
        // Print struct definitions
        let structDefs = pass.types.filter {
            if case .renderPass = typeLookup.declarationContext(for: $0) { return true }
            return false
        }.sorted(by: { $0.name < $1.name })
        
        for type in structDefs {
            print(type.declaration)
            newLine()
        }
        
        // Function Constants
        if !pass.functionConstants.isEmpty {
            print("public struct FunctionConstants : FunctionConstantEncodable {")
            
            let constantNames = pass.functionConstants.map { constant -> String in
                var name = constant.name
                name = name.replacingOccurrences(of: "fc", with: "")
                name.replaceSubrange(name.startIndex...name.startIndex, with: name[name.startIndex].lowercased())
                return name
            }
            
            for (name, constant) in zip(constantNames, pass.functionConstants) {
                print("public var \(name): \(constant.type.name) = \(constant.value)")
            }
            newLine()
            
            print("@inlinable")
            print("public init() {}")
            newLine()
            
            print("@inlinable")
            print("public func encode(into functionConstants: inout SwiftFrameGraph.FunctionConstants) {")
            
            for (name, constant) in zip(constantNames, pass.functionConstants) {
                print("functionConstants.setConstant(self.\(name), at: \(constant.index))")
            }
            
            print("}")
            print("}")
            newLine()
        }
        
        if !pass.pushConstants.isEmpty {
            let setCount = (pass.sets.lastIndex(where: { $0 != nil }) ?? pass.sets.count - 1) + 1
            
            print("public static var pushConstantPath : ResourceBindingPath {")
            do {
                print("#if canImport(Metal)")
                print("if RenderBackend.api == .metal {")
                
                print("return ResourceBindingPath(stages: [.vertex, .fragment], type: .buffer, argumentBufferIndex: nil, index: \(setCount))")

                print("}")
                print("#endif // canImport(Metal)")
            }
            newLine()
            // Vulkan
            do {
                print("#if canImport(Vulkan)")
                print("if RenderBackend.api == .vulkan {")
                
                print("return .pushConstantPath")

                print("}")
                print("#endif // canImport(Vulkan)")
            }
            print("return .nil")
            print("}")
            newLine()
            
            if pass.pushConstants.count == 1, !pass.pushConstants.first!.type.isKnownSwiftType {
                print("public typealias PushConstants = \(pass.pushConstants.first!.type.name)")
            } else {
                print("public struct PushConstants : NoArgConstructable {")
                
                for constant in pass.pushConstants {
                    print("public var \(constant.name): \(constant.type.name) = \(constant.type.defaultInitialiser)")
                }
                newLine()
                
                print("@inlinable")
                print("public init() {}")
                newLine()
                
                let argumentList = pass.pushConstants.map { constant in
                    return "\(constant.name): \(constant.type.name)"
                }.joined(separator: ", ")
                
                print("@inlinable")
                print("public init(\(argumentList)) {")
                
                for constant in pass.pushConstants {
                    print("self.\(constant.name) = \(constant.name)")
                }
                
                print("}")
                print("}")
            }
            
            newLine()
        }
        
        for (i, set) in pass.sets.enumerated() {
            guard let set = set else { continue }
            if let name = set.name {
                print("public typealias Set\(i) = \(name)")
                newLine()
            } else {
                set.printStruct(to: &self, typeLookup: typeLookup, setIndex: i)
            }
            
        }
        
        print("}")
    }
}
