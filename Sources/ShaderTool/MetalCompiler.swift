//
//  File.swift
//  
//
//  Created by Thomas Roughton on 17/08/22.
//

import Foundation

#if canImport(Metal)
import Substrate
import SPIRV_Cross
import Metal

final class MetalCompiler : TargetCompiler {
    let target: Target
    let driver : MetalDriver
    
    init(target: Target) {
        precondition(target.isMetal)
        self.target = target
        self.driver = MetalDriver(target: target)!
    }
    
    private func makeMSLVersion(major: Int, minor: Int, patch: Int) -> UInt32 {
        return UInt32(major * 10000 + minor * 100 + patch)
    }
    
    func compile(spirvCompilers: [SPIRVCompiler], sourceDirectory: URL, workingDirectory: URL, outputDirectory: URL, withDebugInformation debug: Bool) throws {
        var sourceFiles = [(metalSource: URL, airFile: URL)]()
        var needsRegenerateLibrary = false
        var hadErrors = false
        
        let airDirectory = workingDirectory.appendingPathComponent("AIR")
        try FileManager.default.createDirectoryIfNeeded(at: airDirectory)
        
        for compiler in spirvCompilers where compiler.file.target == self.target {
            do {
                var options : spvc_compiler_options! = nil
                spvc_compiler_create_compiler_options(compiler.compiler, &options)
                
                let targetMetalVersion = self.target.metalVersion ?? (2, 1)
                spvc_compiler_options_set_uint(options, SPVC_COMPILER_OPTION_MSL_VERSION, makeMSLVersion(major: targetMetalVersion.major, minor: targetMetalVersion.minor, patch: 0))
                if targetMetalVersion.major >= 2 {
                    spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_ARGUMENT_BUFFERS, 1)
                    spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_FORCE_ACTIVE_ARGUMENT_BUFFER_RESOURCES, 1)
                    spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_ENABLE_DECORATION_BINDING, 1)
                    spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_IOS_USE_SIMDGROUP_FUNCTIONS, 1)
                }
                switch self.target {
                case .metal(.iOS, _), .metal(.macOSAppleSilicon, _):
                    spvc_compiler_options_set_uint(options, SPVC_COMPILER_OPTION_MSL_PLATFORM, UInt32(SPVC_MSL_PLATFORM_IOS.rawValue))
                    spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_FRAMEBUFFER_FETCH_SUBPASS, 1)
                    spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_IOS_USE_SIMDGROUP_FUNCTIONS, 1)
                default:
                    spvc_compiler_options_set_uint(options, SPVC_COMPILER_OPTION_MSL_PLATFORM, UInt32(SPVC_MSL_PLATFORM_MACOS.rawValue))
                    spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_FRAMEBUFFER_FETCH_SUBPASS, 0)
                }
                
                spvc_compiler_install_compiler_options(compiler.compiler, options)
            }
            
            let outputFileName = compiler.file.sourceFile.renderPass + "-" + compiler.file.entryPoint.name
            
            var metalFileURL = workingDirectory.appendingPathComponent(outputFileName + ".metal")
            let airFileURL = airDirectory.appendingPathComponent(outputFileName + ".air")
            do {
                // Generate the compiled source unconditionally, since we need it to compute bindings for reflection.
                let compiledSource = try compiler.compiledSource()
                
                if metalFileURL.needsGeneration(sourceFile: compiler.file.url) {
                    print("\(self.target): Compiling \(compiler.file.url.lastPathComponent)")
                    try compiledSource.write(to: metalFileURL, atomically: false, encoding: .ascii)
                    metalFileURL.removeCachedResourceValue(forKey: .contentModificationDateKey)
                }
                
                sourceFiles.append((metalFileURL, airFileURL))
                
            }
            catch {
                print("Error compiling file \(compiler.file):")
                print(error)
                hadErrors = true
            }
        }
        
        // Also include any source files in the Source/Metal folder.
        let metalSourcesDirectory = sourceDirectory.appendingPathComponent("Metal")
        if FileManager.default.fileExists(atPath: metalSourcesDirectory.path),
           let enumerator = FileManager.default.enumerator(at: metalSourcesDirectory, includingPropertiesForKeys: nil) {
            
            for case let metalFileURL as URL in enumerator where metalFileURL.pathExtension.lowercased() == "metal" {
                let outputFileName = metalFileURL.lastPathComponent
                let airFileURL = airDirectory.appendingPathComponent(outputFileName + ".air")
                
                sourceFiles.append((metalFileURL, airFileURL))
            }
        }
        
        for (metalFileURL, airFileURL) in sourceFiles {
            do {
                if airFileURL.needsGeneration(sourceFile: metalFileURL) {
                    try self.driver.compileToAIR(sourceFile: metalFileURL, destinationFile: airFileURL, withDebugInformation: debug).waitUntilExit()
                    
                    needsRegenerateLibrary = true
                }
            }
            catch {
                print("Error compiling Metal file \(metalFileURL):")
                print(error)
                hadErrors = true
            }
        }
        
        if hadErrors {
            throw CompilerError.shaderErrors
        }
        
        for i in 0..<sourceFiles.count {
            sourceFiles[i].airFile.removeCachedResourceValue(forKey: .contentModificationDateKey)
        }
        
        if needsRegenerateLibrary {
            do {
                try FileManager.default.createDirectoryIfNeeded(at: outputDirectory)
                
                let metalLibraryPath = outputDirectory.appendingPathComponent("Library-\(target.metalPlatform!.rawValue).metallib")
                print("\(self.target): Linking Metal library at \(metalLibraryPath.path)")
                try self.driver.generateLibrary(airFiles: sourceFiles.map { $1 }, outputLibrary: metalLibraryPath).waitUntilExit()
            }
            catch {
                throw CompilerError.libraryGenerationFailed(error)
            }
        }
    }
}

public struct MetalRenderReflectionRequest {
    public let library: MTLLibrary
    public var renderPass: String
    public var vertexFunctions: [String]
    public var fragmentFunctions: [String]
//    public var functionConstants: FunctionConstants
}

public struct MetalComputeReflectionRequest {
    public let library: MTLLibrary
    public var renderPass: String
    public var computeFunctions: [String]
//    public var functionConstants: FunctionConstants
}

enum MetalReflectionError: Error {
    case missingVertexFunction
}

extension RenderPass {
    public convenience init(metalRenderRequest request: MetalRenderReflectionRequest) throws {
        guard !request.vertexFunctions.isEmpty else { throw MetalReflectionError.missingVertexFunction }
        
        self.init(name: request.renderPass)
        
        let library = request.library
        
        let functions = self.buildFunctionLibrary(functions: request.vertexFunctions + request.fragmentFunctions, library: request.library)
        
        for vertexFunctionName in request.vertexFunctions.dropLast(request.fragmentFunctions.isEmpty ? 0 : 1) {
            guard let vertexFunction = functions[vertexFunctionName] else { continue }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            
            if let vertexAttributes = vertexFunction.vertexAttributes {
                pipelineDescriptor.vertexDescriptor = .init(attributes: vertexAttributes)
            }
            
            do {
                var pipelineReflection: MTLRenderPipelineReflection? = nil
                let _ = try library.device.makeRenderPipelineState(descriptor: pipelineDescriptor, options: .bufferTypeInfo, reflection: &pipelineReflection)
                
                if let pipelineReflection = pipelineReflection {
                    print(pipelineReflection)
                }
            } catch {
                print(error)
            }
        }
        
        if request.fragmentFunctions.isEmpty {
            return
        }
        
        guard let vertexFunction = request.vertexFunctions.reversed().lazy.compactMap({ functions[$0] }).first else {
            throw MetalReflectionError.missingVertexFunction
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        if let vertexAttributes = vertexFunction.vertexAttributes {
            pipelineDescriptor.vertexDescriptor = .init(attributes: vertexAttributes)
        }
        
        for fragmentFunctionName in request.fragmentFunctions {
            guard let fragmentFunction = functions[fragmentFunctionName] else { continue }
            
            pipelineDescriptor.fragmentFunction = fragmentFunction
            
            do {
                var pipelineReflection: MTLRenderPipelineReflection? = nil
                let _ = try library.device.makeRenderPipelineState(descriptor: pipelineDescriptor, options: .bufferTypeInfo, reflection: &pipelineReflection)
                
                if let pipelineReflection = pipelineReflection {
                    self.addBoundResources(from: pipelineReflection)
                }
            } catch {
                print(error)
            }
        }
    }
    
    func addBoundResources(from reflection: MTLRenderPipelineReflection) {
        for argument in reflection.vertexArguments ?? [] {
            argument.bufferPointerType?.elementStructType()
        }
    }
    
    public convenience init(metalComputeRequest request: MetalComputeReflectionRequest) throws {
        self.init(name: request.renderPass)
        
        let library = request.library
        let functions = self.buildFunctionLibrary(functions: request.computeFunctions, library: library)
        
        for computeFunctionName in request.computeFunctions {
            guard let computeFunction = functions[computeFunctionName] else { continue }
            
            let pipelineDescriptor = MTLComputePipelineDescriptor()
            pipelineDescriptor.computeFunction = computeFunction
            
            do {
                var pipelineReflection: MTLComputePipelineReflection? = nil
                let _ = try library.device.makeComputePipelineState(descriptor: pipelineDescriptor, options: .bufferTypeInfo, reflection: &pipelineReflection)
                
                if let pipelineReflection = pipelineReflection {
                    print(pipelineReflection)
                }
            } catch {
                print(error)
            }
        }
    }
    
    func buildFunctionLibrary(functions functionNames: [String], library: MTLLibrary) -> [String: MTLFunction] {
        var functions = [String: MTLFunction]()
        
        for name in functionNames {
            guard let function = library.makeFunction(name: name) else {
                print("Warning: couldn't make Metal function with name \(name)")
                continue
            }
            
            guard let shaderType = ShaderType(function.functionType) else {
                continue
            }
            
            let constants = MTLFunctionConstantValues()
            for (name, value) in function.functionConstantsDictionary {
                if value.required {
                    var valueToSet = SIMD8<UInt64>.zero
                    constants.setConstantValue(&valueToSet, type: value.type, index: value.index)
                }
                
                guard let spirvType = SPIRVType(value.type) else {
                    continue
                }
                
                let constantValue: FunctionConstantValue?
                switch spirvType {
                case .float:
                    constantValue = .float(0.0)
                case .int32:
                    constantValue = .int32(0)
                case .uint32:
                    constantValue = .uint32(0)
                case .bool:
                    constantValue = .bool(false)
                default:
                    print("Unhandled type \(spirvType) for default constant value.")
                    constantValue = nil
                }
                
                let functionConstant = FunctionConstant(name: name, type: spirvType, value: constantValue, index: value.index)
                self.addFunctionConstant(functionConstant)
            }
            
            do {
                let customizedFunction = try library.makeFunction(name: name, constantValues: constants)
                functions[name] = customizedFunction
            } catch {
                print("Warning: making Metal function with name \(name) failed with error: \(error)")
            }
            
            let entryPoint = EntryPoint(name: name, type: shaderType, renderPass: self.name)
            if !self.entryPoints.contains(entryPoint) {
                self.entryPoints.append(entryPoint)
            }
        }
        
        return functions
    }
}

extension SPIRVType {
    init?(_ type: MTLDataType, structMember: MTLStructMember? = nil) {
        switch type {
        case .none:
            return nil
        case .float:
            self = .float
        case .float2:
            self = .vector(element: .float, length: 2)
        case .float3:
            self = .vector(element: .float, length: 3)
        case .float4:
            self = .vector(element: .float, length: 4)
        case .float2x2:
            self = .matrix(element: .float, rows: 2, columns: 2)
        case .float2x3:
            self = .matrix(element: .float, rows: 2, columns: 3)
        case .float2x4:
            self = .matrix(element: .float, rows: 2, columns: 4)
        case .float3x2:
            self = .matrix(element: .float, rows: 3, columns: 2)
        case .float3x3:
            self = .matrix(element: .float, rows: 3, columns: 3)
        case .float3x4:
            self = .matrix(element: .float, rows: 3, columns: 4)
        case .float4x2:
            self = .matrix(element: .float, rows: 4, columns: 2)
        case .float4x3:
            self = .matrix(element: .float, rows: 4, columns: 3)
        case .float4x4:
            self = .matrix(element: .float, rows: 4, columns: 4)
        case .half:
            self = .half
        case .half2:
            self = .vector(element: .half, length: 2)
        case .half3:
            self = .vector(element: .half, length: 3)
        case .half4:
            self = .vector(element: .half, length: 4)
        case .half2x2:
            self = .matrix(element: .half, rows: 2, columns: 2)
        case .half2x3:
            self = .matrix(element: .half, rows: 2, columns: 3)
        case .half2x4:
            self = .matrix(element: .half, rows: 2, columns: 4)
        case .half3x2:
            self = .matrix(element: .half, rows: 3, columns: 2)
        case .half3x3:
            self = .matrix(element: .half, rows: 3, columns: 3)
        case .half3x4:
            self = .matrix(element: .half, rows: 3, columns: 4)
        case .half4x2:
            self = .matrix(element: .half, rows: 4, columns: 2)
        case .half4x3:
            self = .matrix(element: .half, rows: 4, columns: 3)
        case .half4x4:
            self = .matrix(element: .half, rows: 4, columns: 4)
        case .int:
            self = .int32
        case .int2:
            self = .vector(element: .int32, length: 2)
        case .int3:
            self = .vector(element: .int32, length: 3)
        case .int4:
            self = .vector(element: .int32, length: 4)
        case .uint, .rgb10a2Unorm, .rg11b10Float, .rgb9e5Float:
            self = .uint32
        case .uint2:
            self = .vector(element: .uint32, length: 2)
        case .uint3:
            self = .vector(element: .uint32, length: 3)
        case .uint4:
            self = .vector(element: .uint32, length: 4)
        case .short, .r16Snorm:
            self = .int16
        case .short2, .rg16Snorm:
            self = .vector(element: .int16, length: 2)
        case .short3:
            self = .vector(element: .int16, length: 3)
        case .short4, .rgba16Snorm:
            self = .vector(element: .int16, length: 4)
        case .ushort, .r16Unorm:
            self = .uint16
        case .ushort2, .rg16Unorm:
            self = .vector(element: .uint16, length: 2)
        case .ushort3:
            self = .vector(element: .uint16, length: 3)
        case .ushort4, .rgba16Unorm:
            self = .vector(element: .uint16, length: 4)
        case .char, .r8Snorm:
            self = .int8
        case .char2, .rg8Snorm:
            self = .vector(element: .int8, length: 2)
        case .char3:
            self = .vector(element: .int8, length: 3)
        case .char4, .rgba8Snorm:
            self = .vector(element: .int8, length: 4)
        case .uchar, .r8Unorm:
            self = .uint8
        case .uchar2, .rg8Unorm:
            self = .vector(element: .uint8, length: 2)
        case .uchar3:
            self = .vector(element: .uint8, length: 3)
        case .uchar4, .rgba8Unorm, .rgba8Unorm_srgb:
            self = .vector(element: .uint8, length: 4)
        case .bool:
            self = .bool
        case .bool2:
            self = .vector(element: .bool, length: 2)
        case .bool3:
            self = .vector(element: .bool, length: 3)
        case .bool4:
            self = .vector(element: .bool, length: 4)
        case .texture:
            self = .texture
        case .sampler:
            self = .sampler
        case .long:
            self = .int64
        case .long2:
            self = .vector(element: .int64, length: 2)
        case .long3:
            self = .vector(element: .int64, length: 3)
        case .long4:
            self = .vector(element: .int64, length: 4)
        case .ulong:
            self = .uint64
        case .ulong2:
            self = .vector(element: .uint64, length: 2)
        case .ulong3:
            self = .vector(element: .uint64, length: 3)
        case .ulong4:
            self = .vector(element: .uint64, length: 4)
        case .struct:
            guard let structMember = structMember, let structType = structMember.structType() else {
                print("Unhandled type \(type)")
                return nil
            }
            
            print(structType)
            preconditionFailure()
            
        case .array, .pointer, .renderPipeline, .computePipeline, .indirectCommandBuffer,
                .visibleFunctionTable, .intersectionFunctionTable, .primitiveAccelerationStructure, .instanceAccelerationStructure:
            print("Unhandled type \(type)")
            return nil
        @unknown default:
            print("Unhandled type \(type)")
            return nil
        }
    }
    
    init(name: String, type: MTLStructType) {
        var size = 0
        var offset = 0
        let members = type.members.compactMap { member -> SPIRVStructMember? in
            guard let sprivType = SPIRVType(structMember: member) else {
                print("Warning: skipped struct member \(member)")
                return nil
            }
            offset = offset.roundedUpToMultiple(of: sprivType.alignment)
            
            let spirvMember = SPIRVStructMember(name: member.name, type: sprivType, offset: offset)
            
            size = offset + spirvMember.type.size
            offset += spirvMember.type.stride
            
            return spirvMember
        }
        self = .struct(name: name, members: members, size: size)
    }
    
    init?(structMember: MTLStructMember) {
        self.init(structMember.dataType, structMember: structMember)
    }
}


fileprivate extension ShaderType {
    init?(_ type: MTLFunctionType) {
        switch type {
        case .vertex:
            self = .vertex
        case .fragment:
            self = .fragment
        case .kernel:
            self = .compute
        default:
            return nil
        }
    }
}

fileprivate extension MTLVertexDescriptor {
    convenience init(attributes: [MTLVertexAttribute]) {
        self.init()
        
        var offset = 0
        for attribute in attributes {
            let format: MTLVertexFormat
            switch attribute.attributeType {
            case .float:
                format = .float
                offset += MemoryLayout<Float>.stride
            case .float2:
                format = .float2
            case .float3:
                format = .float3
            case .float4:
                format = .float4
            case .half:
                format = .half
            case .half2:
                format = .half2
            case .half3:
                format = .half3
            case .half4:
                format = .half4
            case .int:
                format = .int
            case .int2:
                format = .int2
            case .int3:
                format = .int3
            case .int4:
                format = .int4
            case .uint:
                format = .uint
            case .uint2:
                format = .uint2
            case .uint3:
                format = .uint3
            case .uint4:
                format = .uint4
            case .short:
                format = .short
            case .short2:
                format = .short2
            case .short3:
                format = .short3
            case .short4:
                format = .short4
            case .ushort:
                format = .ushort
            case .ushort2:
                format = .ushort2
            case .ushort3:
                format = .ushort3
            case .ushort4:
                format = .ushort4
            case .char:
                format = .char
            case .char2:
                format = .char2
            case .char3:
                format = .char3
            case .char4:
                format = .char4
            case .uchar:
                format = .uchar
            case .uchar2:
                format = .uchar2
            case .uchar3:
                format = .uchar3
            case .uchar4:
                format = .uchar4
            case .r8Unorm:
                format = .ucharNormalized
            case .r8Snorm:
                format = .charNormalized
            case .r16Unorm:
                format = .ushortNormalized
            case .r16Snorm:
                format = .shortNormalized
            case .rg8Unorm:
                format = .uchar2Normalized
            case .rg8Snorm:
                format = .char2Normalized
            case .rg16Unorm:
                format = .ushort2Normalized
            case .rg16Snorm:
                format = .short2Normalized
            case .rgba8Unorm:
                format = .uchar4Normalized
            case .rgba8Unorm_srgb:
                format = .uchar4Normalized
            case .rgba8Snorm:
                format = .char4Normalized
            case .rgba16Unorm:
                format = .ushort4Normalized
            case .rgba16Snorm:
                format = .short4Normalized
            case .rgb10a2Unorm:
                format = .uint1010102Normalized
            default:
                continue
            }
            self.attributes[attribute.attributeIndex].format = format
            self.attributes[attribute.attributeIndex].bufferIndex = 0
            self.attributes[attribute.attributeIndex].offset = offset
            offset += 16
        }
        
        self.layouts[0].stepFunction = .perVertex
        self.layouts[0].stepRate = 1
        self.layouts[0].stride = offset
    }
}

#endif
