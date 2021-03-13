//
//  ReflectionContext.swift
//  
//
//  Created by Thomas Roughton on 2/12/19.
//

import Foundation
import SPIRV_Cross

enum ReflectionError : Error {
    case reflectionFailed(SPIRVFile)
    case mismatchingSourceFiles(DXCSourceFile, DXCSourceFile)
}

final class ReflectionContext {
    let typeLookup = TypeLookup()
    
    var entryPoints : [String : EntryPoint] = [:]
    var renderPasses : [String : RenderPass] = [:]
    var descriptorSets : [DescriptorSet] = []
    
    public func reflect(compiler: SPIRVCompiler) throws {
        let file = compiler.file
        
        let renderPass = self.renderPasses[file.sourceFile.renderPass] ?? { () -> RenderPass in
            let pass = RenderPass(sourceFile: file.sourceFile)
            self.renderPasses[file.sourceFile.renderPass] = pass
            return pass
        }()
        
        guard renderPass.sourceFile == file.sourceFile else {
            throw ReflectionError.mismatchingSourceFiles(renderPass.sourceFile, file.sourceFile)
        }
        
        self.entryPoints[file.entryPoint.name] = file.entryPoint
        
        guard renderPass.addEntryPoint(file.entryPoint, compiler: compiler) else {
            throw ReflectionError.reflectionFailed(file)
        }
    }
    
    func fillTypeLookup() {
        for pass in self.renderPasses.values {
            for pushConstant in pass.pushConstants {
                self.typeLookup.registerType(pushConstant.type, set: nil, pass: pass)
            }
            
            for set in pass.sets {
                guard let set = set else { continue }
                for resource in set.resources {
                    self.typeLookup.registerType(resource.type, set: set, pass: pass)
                }
            }
        }
    }
    
    func generateDescriptorSets() {
        var allSets = [DescriptorSet]()
        
        for pass in self.renderPasses.values.sorted(by: { $0.name < $1.name }) {
            let resources = pass.boundResources
            var startIndex = 0
            setLoop: for setIndex in 0..<DescriptorSet.setCount {
                let endIndex = resources[startIndex...].firstIndex(where: { $0.binding.set != setIndex }) ?? resources.count
                defer { startIndex = endIndex }
                
                let indexRange = startIndex..<endIndex
                if indexRange.isEmpty { continue }
                
                for existingSet in allSets {
                    if existingSet.isCompatible(with: resources[indexRange]) {
                        existingSet.addResources(resources[indexRange])
                        pass.sets[setIndex] = existingSet
                        existingSet.passes.append(pass)
                        continue setLoop
                    }
                }
                
                let newSet = DescriptorSet()
                newSet.addResources(resources[indexRange])
                pass.sets[setIndex] = newSet
                newSet.passes.append(pass)
                allSets.append(newSet)
            }
        }
        
        self.descriptorSets = allSets
    }
    
    func mergePasses(_ pass: RenderPass, sourcePass: RenderPass) -> Bool {
        do {
            // Merge function constants.
            var i = 0
            var j = 0
            
            while i < pass.functionConstants.count && j < sourcePass.functionConstants.count {
                if pass.functionConstants[i].index < sourcePass.functionConstants[j].index {
                    i += 1
                } else if pass.functionConstants[i].index > sourcePass.functionConstants[j].index {
                    pass.functionConstants.insert(sourcePass.functionConstants[j], at: i)
                    j += 1
                } else {
                    if pass.functionConstants[i] != sourcePass.functionConstants[j] {
                        print("Warning: cannot merge \(sourcePass.name) with \(pass.name) since function constants \(pass.functionConstants[i]) and \(sourcePass.functionConstants[j]) share the same index but are different.")
                        return false
                    }
                    
                    i += 1
                    j += 1
                }
            }
            
            pass.functionConstants.append(contentsOf: sourcePass.functionConstants[j...])
        }
        
        do {
            // Merge push constants.
            var i = 0
            var j = 0
            
            while i < pass.pushConstants.count && j < sourcePass.pushConstants.count {
                let rangesOverlap = pass.pushConstants[i].range.lowerBound <= sourcePass.pushConstants[j].range.upperBound &&
                                    sourcePass.pushConstants[j].range.lowerBound <= pass.pushConstants[i].range.upperBound
                
                if rangesOverlap && pass.pushConstants[i].range != sourcePass.pushConstants[j].range {
                    print("Warning: cannot merge \(sourcePass.name) with \(pass.name) since push constants \(pass.pushConstants[i]) and \(sourcePass.pushConstants[j]) have overlapping ranges.")
                    return false
                }
                
                if pass.pushConstants[i].range.lowerBound < sourcePass.pushConstants[j].range.lowerBound {
                    i += 1
                } else if pass.pushConstants[i].range.lowerBound > sourcePass.pushConstants[j].range.lowerBound {
                    pass.pushConstants.insert(sourcePass.pushConstants[j], at: i)
                    j += 1
                } else {
                    if pass.pushConstants[i] != sourcePass.pushConstants[j] {
                        print("Warning: cannot merge \(sourcePass.name) with \(pass.name) since push constants \(pass.pushConstants[i]) and \(sourcePass.pushConstants[j]) share the same index but are different.")
                        return false
                    }
                    
                    i += 1
                    j += 1
                }
            }
            
            pass.pushConstants.append(contentsOf: sourcePass.pushConstants[j...])
        }
        
        do {
            // Merge resources
            assert(pass.sets.allSatisfy({ $0 == nil }), "Descriptor sets should not have been created yet.")
            
            var i = 0
            var j = 0
            
            while i < pass.boundResources.count && j < sourcePass.boundResources.count {
                if pass.boundResources[i].binding < sourcePass.boundResources[j].binding {
                    i += 1
                } else if pass.boundResources[i].binding > sourcePass.boundResources[j].binding {
                    pass.boundResources.insert(sourcePass.boundResources[j], at: i)
                    j += 1
                } else {
                    if pass.boundResources[i].binding.arrayLength != sourcePass.boundResources[j].binding.arrayLength ||
                        pass.boundResources[i].name != sourcePass.boundResources[j].name ||
                        pass.boundResources[i].type != sourcePass.boundResources[j].type {
                        print("Warning: cannot merge \(sourcePass.name) with \(pass.name) since resources \(pass.boundResources[i]) and \(sourcePass.boundResources[j]) share the same binding but are different.")
                        return false
                    }
                    pass.boundResources[i].stages.formUnion(sourcePass.boundResources[j].stages)
                    
                    i += 1
                    j += 1
                }
            }
            
            pass.boundResources.append(contentsOf: sourcePass.boundResources[j...])
        }
        
        pass.entryPoints.append(contentsOf: sourcePass.entryPoints)
        return true
    }
    
    func mergeExternalEntryPoints() {
        for pass in self.renderPasses.values {
            for entryPointName in pass.sourceFile.externalEntryPoints {
                guard let entryPoint = self.entryPoints[entryPointName] else {
                    print("Warning: pass \(pass.name) uses missing entry point \(entryPointName)")
                    continue
                }
                
                _ = mergePasses(pass, sourcePass: self.renderPasses[entryPoint.renderPass]!)
                
            }
        }
    }
    
    public func printReflection(to file: URL) throws {
        let reflectionDirectory = file.deletingLastPathComponent()
        try FileManager.default.createDirectoryIfNeeded(at: reflectionDirectory)

        var printer = ReflectionPrinter()
        
        printer.print("""
        // NOTE: This file is automatically generated by Substrate's ShaderTool.

        import SubstrateMath
        import Substrate
        
        #if canImport(Metal)
        import Metal
        #endif
        
        public typealias Vector3h = SIMD3<UInt16>

        // MARK: - Shared Structs

        """)
        
        for (type, context) in self.typeLookup.typeContexts.sorted(by: { $0.key.name < $1.key.name }) {
            guard case .topLevel = context else { continue }
            printer.print(type.declaration)
            printer.newLine()
        }
        
        printer.print("// MARK: - Shared Descriptor Sets")
        printer.newLine()
        
        for set in self.descriptorSets where set.passes.count > 1 {
            set.name = set.passes.map { $0.name }.sorted().joined() + "Set\( String(set.resources[0].binding.set))" // FIXME: what if the resources are in different sets for each pass?
        }
        
        for set in self.descriptorSets.lazy.filter({ $0.passes.count > 1 }).sorted(by: { $0.name! < $1.name! }) {
            set.printStruct(to: &printer, typeLookup: typeLookup, setIndex: -1)
        }
        
        printer.print("// MARK: - Render Passes")
        printer.newLine()
        
        for pass in self.renderPasses.values.sorted(by: { $0.name < $1.name }) {
            printer.print(pass: pass, typeLookup: typeLookup)
            printer.newLine()
        }
        
        try printer.write(to: file)
    }
}

final class TypeLookup {
    enum DeclarationContext {
        case descriptorSet(DescriptorSet)
        case renderPass(RenderPass)
        case topLevel
    }
    
    var typeContexts = [SPIRVType : DeclarationContext]()
    
    func registerType(_ type: SPIRVType, set: DescriptorSet?, pass: RenderPass) {
        if type.isKnownSwiftType { return }
        if case .array(let nestedType, _) = type {
            registerType(nestedType, set: set, pass: pass)
        }
        
        guard case .struct(_, let members, _) = type else { return }
        
        for member in members {
            self.registerType(member.type, set: set, pass: pass)
        }
        
        pass.types.insert(type)
        
        var context = self.typeContexts[type]
        
        switch context {
        case .descriptorSet(let currentSet):
            if let set = set {
                assert(set.passes.contains(where: { $0 === pass }))
                if currentSet === set {
                    break
                } else if currentSet.passes.count == 1, set.passes.count == 1, currentSet.passes[0] === set.passes[0] {
                    context = .renderPass(currentSet.passes[0])
                } else {
                    context = .topLevel
                }
            } else {
                if currentSet.passes.count == 1, currentSet.passes[0] === pass {
                    context = .renderPass(pass)
                } else {
                    context = .topLevel
                }
            }
        case .renderPass(let currentPass):
            if currentPass === pass {
                break
            } else if let set = set, set.passes.count > 1, set.passes.contains(where: { $0 === currentPass }) {
                context = .descriptorSet(set)
            } else {
                context = .topLevel
            }
        case .topLevel:
            break
        case .none:
            if let set = set {
                context = .descriptorSet(set)
            } else {
                context = .renderPass(pass)
            }
        }
        
        self.typeContexts[type] = context
    }
    
    static func formatName(_ name: String) -> String {
        if name.hasPrefix("type_PushConstant_") {
            return String(name.dropFirst("type_PushConstant_".count))
        }
        
        if name.hasPrefix("type_") {
            let name = name.dropFirst("type_".count)
            return String(name.prefix(1).uppercased()) + name.dropFirst()
        }
        
        if ["AffineMatrix", "AffineMatrix2D"].contains(name) {
            return name + "<Float>"
        }
        
        return name
    }
    
    static func formattedName(type: SPIRVType) -> String {
        guard case .struct(let name, _, _) = type else { return type.name }
        
        return formatName(name)
    }

    func declarationContext(for type: SPIRVType) -> DeclarationContext? {
        guard case .struct = type else { return nil }
        return self.typeContexts[type]
    }
}

final class RenderPass {
    let name : String
    let sourceFile: DXCSourceFile
    
    var entryPoints : [EntryPoint] = []
    var functionConstants : [FunctionConstant] = [] // Sorted by construction
    var pushConstants : [PushConstant] = [] // Sorted by construction
    var boundResources : [Resource] = [] // Sorted by construction
    
    var sets = [DescriptorSet?](repeating: nil, count: 8)
    
    var types = Set<SPIRVType>()
    
    var attachmentCount : Int = 0
    
    init(sourceFile: DXCSourceFile) {
        self.name = sourceFile.renderPass
        self.sourceFile = sourceFile
    }
    
    func addEntryPoint(_ entryPoint: EntryPoint, compiler: SPIRVCompiler) -> Bool {
        guard compiler.setEntryPoint(entryPoint) else { return false }
        
        if !self.entryPoints.contains(entryPoint) {
            self.entryPoints.append(entryPoint)
        }
        
        for constant in compiler.functionConstants {
            let insertionPoint = self.functionConstants.firstIndex(where: { $0.index >= constant.index }) ?? self.functionConstants.count
            if insertionPoint < self.functionConstants.count && self.functionConstants[insertionPoint] == constant { continue }
            
            guard insertionPoint >= self.functionConstants.count || self.functionConstants[insertionPoint].index != constant.index else {
                print("Warning: function constants \(self.functionConstants[insertionPoint]) and \(constant) share the same index but are not identical.")
                continue
            }
            self.functionConstants.insert(constant, at: insertionPoint)
        }
        
        for constant in compiler.pushConstants {
            if !self.pushConstants.contains(constant) {
                self.pushConstants.append(constant)
            }
        }
        
        for resource in compiler.boundResources {
            if resource.viewType == .inputAttachment, compiler.file.target.isAppleSilicon {
                continue // No explicit bindings for input attachments on iOS Metal.
            }
            
            let insertionPoint = self.boundResources.firstIndex(where: { $0.binding >= resource.binding }) ?? self.boundResources.count
            if insertionPoint < self.boundResources.count && self.boundResources[insertionPoint] == resource {
                self.boundResources[insertionPoint].stages.formUnion(resource.stages)
                self.boundResources[insertionPoint].platformBindings.formUnion(resource.platformBindings)
                continue
            }
            
            guard insertionPoint >= self.boundResources.count || self.boundResources[insertionPoint].binding != resource.binding else {
                print("Warning: resources \(self.boundResources[insertionPoint]) and \(resource) share the same binding \(resource.binding) but are not identical.")
                continue
            }
            self.boundResources.insert(resource, at: insertionPoint)
        }
        
        self.attachmentCount = max(self.attachmentCount, compiler.attachments.max(by: { $0.index < $1.index }).map { $0.index + 1 } ?? 0)
        
        return true
    }
}
