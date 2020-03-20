// swift-tools-version:5.0

import PackageDescription

#if os(macOS)
let supportedRenderAPIs = ["MetalRenderer"]
#else
let supportedRenderAPIs = ["VkRenderer"]
#endif

let package = Package(
    name: "SwiftFrameGraph",
    platforms: [.macOS(.v10_14), .iOS(.v12), .tvOS(.v12)],
    products: [
        .library(name: "FrameGraphTextureIO", targets: ["FrameGraphTextureIO"]),
        .library(name: "SwiftFrameGraph", targets: ["SwiftFrameGraph"]),
        .library(name: "FrameGraphUtilities", targets: ["FrameGraphUtilities"]),
        .executable(name: "ShaderTool", targets: ["ShaderTool"])
    ],
    dependencies: [
        .package(url: "https://github.com/glessard/swift-atomics", from: "6.0.1"),
        .package(url: "https://github.com/troughton/SPIRV-Cross-SPM", from: "0.24.0"),
        .package(url: "https://github.com/sharplet/Regex", from: "2.1.0"),
        .package(url: "https://github.com/troughton/Cstb", from: "1.0.2"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.0.1")
    ],
    targets: [
        .target(name: "FrameGraphTextureIO", dependencies: ["SwiftFrameGraph", "stb_image", "stb_image_resize", "stb_image_write", "tinyexr"]),
        .target(name: "FrameGraphCExtras", dependencies: []),
        .target(name: "SwiftFrameGraph", dependencies: ["FrameGraphUtilities", "FrameGraphCExtras", "SwiftAtomics"], path: "Sources/FrameGraph"),
        .target(name: "FrameGraphUtilities", dependencies: ["SwiftAtomics"]),
        .target(
            name: "ShaderTool",
            dependencies: ["SPIRV-Cross", "SwiftFrameGraph", "Regex", "ArgumentParser"]),
    ],
    cLanguageStandard: .c11, cxxLanguageStandard: .cxx14
)
