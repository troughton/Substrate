//
//  Target.swift
//  
//
//  Created by Thomas Roughton on 7/12/19.
//

import Foundation
import SPIRV_Cross

enum Target: Equatable {
    enum MetalPlatform: String, Hashable {
        case macOS
        case macOSAppleSilicon
        case iOS
    }
    
    case metal(platform: MetalPlatform, deploymentTarget: String)
    case vulkan(version: String)
    
    static func ==(lhs: Target, rhs: Target) -> Bool {
        switch (lhs, rhs) {
        case (.metal(.iOS, _), .metal(.iOS, _)),
             (.metal(.macOS, _), .metal(.macOS, _)),
             (.metal(.macOSAppleSilicon, _), .metal(.macOSAppleSilicon, _)),
             (.vulkan(_), .vulkan(_)):
            return true
        default:
            return false
        }
    }
    
    static var defaultTarget : Target {
#if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
    return .metal(platform: .iOS, deploymentTarget: "12.0")
#elseif os(macOS) || targetEnvironment(macCatalyst)
#if arch(i386) || arch(x86_64)
    return .metal(platform: .macOS, deploymentTarget: "10.14")
#else
    return .metal(platform: .macOSAppleSilicon, deploymentTarget: "10.16")
#endif
#else
        return .vulkan(version: "1.1")
#endif
    }
    
    var metalPlatform: MetalPlatform? {
        switch self {
        case .metal(let platform, _):
            return platform
        default:
            return nil
        }
    }
    
    var metalVersion: (major: Int, minor: Int)? {
        switch self {
        case .metal(let platform, let deploymentTarget):
            let components = deploymentTarget.split(separator: ".")

            let majorVersion = components.first.flatMap { Int($0) } ?? 10
            let minorVersion = components.dropFirst().first.flatMap { Int($0) } ?? 0
            
            switch platform {
            case .macOS:
                switch (majorVersion, minorVersion) {
                case _ where majorVersion >= 11:
                    return (2, 3)
                case (10, 16):
                    return (2, 3)
                case (10, 15):
                    return (2, 2)
                case (10, 14):
                    return (2, 1)
                case (10, 13):
                    return (2, 0)
                case (10, 12):
                    return (1, 2)
                case (10, 11):
                    return (1, 1)
                default:
                    return (1, 0)
                }
            case .macOSAppleSilicon:
                return (2, 3)
            case .iOS:
                switch majorVersion {
                case _ where majorVersion >= 14:
                    return (2, 3)
                case 13:
                    return (2, 2)
                case 12:
                    return (2, 1)
                case 11:
                    return (2, 0)
                case 10:
                    return (1, 2)
                case 9:
                    return (1, 1)
                default:
                    return (1, 0)
                }
            }
        default:
            return nil
        }
    }
    
    var isAppleSilicon: Bool {
        if let platform = self.metalPlatform, platform != .macOS {
            return true
        }
        return false
    }
    
    var isMetal: Bool {
        switch self {
        case .metal:
            return true
        default:
            return false
        }
    }
    
    var spvcBackend : spvc_backend {
        switch self {
        case .metal:
            return SPVC_BACKEND_MSL
        case .vulkan:
            return SPVC_BACKEND_NONE
        }
    }
    
    var targetDefines : [String] {
        switch self {
        case .metal(.macOS, _):
            return ["TARGET_METAL_MACOS"]
        case .metal(.macOSAppleSilicon, _):
            return ["TARGET_METAL_MACOS", "TARGET_METAL_APPLE_SILICON"]
        case .metal(.iOS, _):
            return ["TARGET_METAL_IOS", "TARGET_METAL_APPLE_SILICON"]
        case .vulkan:
            return ["TARGET_VULKAN"]
        }
    }

    var intermediatesDirectory : String {
        switch self {
        case .metal(let platform, _):
            return "Intermediates/Metal-\(platform.rawValue)"
        case .vulkan:
            return self.outputDirectory
        }
    }
    
    var outputDirectory : String {
        switch self {
        case .metal:
            return "Compiled"
        case .vulkan:
            return "Compiled/Vulkan"
        }
    }
    
    var spirvDirectory : String {
        switch self {
        case .vulkan:
            return self.intermediatesDirectory
        default:
            return self.intermediatesDirectory + "/SPIRV"
        }
    }
    
    var compiler : TargetCompiler? {
        switch self {
        case .metal:
            return MetalCompiler(target: self)
        case .vulkan:
            return nil // We've already compiled to SPIR-V, so there's nothing else to do.
        }
    }
}

extension Target: CustomStringConvertible {
    var description: String {
        switch self {
        case .metal(let platform, let deploymentTarget):
            return "Metal (\(platform.rawValue) \(deploymentTarget))"
        case .vulkan(let version):
            return "Vulkan (v\(version))"
        }
    }
}

enum CompilerError : Error {
    case shaderErrors
    case libraryGenerationFailed(Error)
}

protocol TargetCompiler {
    func compile(spirvCompilers: [SPIRVCompiler], sourceDirectory: URL, workingDirectory: URL, outputDirectory: URL, withDebugInformation debug: Bool) throws
}
