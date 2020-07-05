// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "SwiftFrameGraph",
    platforms: [.macOS(.v10_14), .iOS(.v12), .tvOS(.v12)],
    products: [
        .library(name: "FrameGraphTextureIO", targets: ["FrameGraphTextureIO"]),
        .library(name: "SwiftFrameGraph", targets: ["SwiftFrameGraph"]),
        .library(name: "FrameGraphUtilities", targets: ["FrameGraphUtilities"]),
        .library(name: "AppFramework", targets: ["AppFramework"]),
        .executable(name: "ShaderTool", targets: ["ShaderTool"])
    ],
    dependencies: [
        .package(url: "https://github.com/glessard/swift-atomics", from: "6.0.1"),
        .package(url: "https://github.com/troughton/SPIRV-Cross-SPM", from: "0.33.1"),
        .package(url: "https://github.com/sharplet/Regex", from: "2.1.0"),
        .package(url: "https://github.com/troughton/Cstb", from: "1.0.3"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.0.1"),
        .package(url: "https://github.com/troughton/LodePNG-SPM", from: "0.0.1"),
        .package(url: "https://github.com/troughton/SwiftImGui", from: "1.7.32"),
        .package(url: "https://github.com/troughton/SwiftMath", from: "5.0.0")
    ],
    targets: [
        // FrameGraph
        .target(name: "FrameGraphTextureIO", dependencies: ["SwiftFrameGraph", "stb_image", "stb_image_resize", "stb_image_write", "tinyexr", "LodePNG"]),
        .target(name: "FrameGraphCExtras", dependencies: ["Vulkan"]),
        .target(name: "SwiftFrameGraph", dependencies: ["FrameGraphUtilities", "FrameGraphCExtras", "SwiftAtomics", "SPIRV-Cross", "Vulkan"], path: "Sources/FrameGraph"),
        .target(name: "FrameGraphUtilities", dependencies: ["SwiftAtomics"]),
    
        // ShaderTool
        .target(
            name: "ShaderTool",
            dependencies: ["SPIRV-Cross", "SwiftFrameGraph", "Regex", "ArgumentParser"]),
        
        // AppFramework
        .systemLibrary(
            name: "CSDL2",
            pkgConfig: "sdl2",
            providers: [
                .brew(["sdl2"]),
                .apt(["sdl2"]),
            ]
        ),
        .systemLibrary(
            name: "Vulkan",
            providers: [
                .brew(["vulkan-headers"])
            ]
        ),
        .target(name: "CNativeFileDialog"),
        .target(
            name: "AppFramework",
            dependencies: ["FrameGraphUtilities", "SwiftFrameGraph", "SwiftMath", "ImGui", "CNativeFileDialog", "CSDL2", "Vulkan"]),
    ],
    cLanguageStandard: .c11, cxxLanguageStandard: .cxx14
)
