// swift-tools-version:5.2

import PackageDescription

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
let vulkanDependencies: [Target.Dependency] = []
#else
let vulkanDependencies: [Target.Dependency] = [.target(name: "Vulkan", condition: .when(platforms: [.linux, .windows]))]
#endif

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
        .package(name: "SwiftAtomics", url: "https://github.com/glessard/swift-atomics", from: "6.0.1"),
        .package(name: "SPIRV-Cross", url: "https://github.com/troughton/SPIRV-Cross-SPM", from: "0.33.1"),
        .package(url: "https://github.com/sharplet/Regex", from: "2.1.0"),
        .package(url: "https://github.com/troughton/Cstb", from: "1.0.3"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.0.1"),
        .package(name: "LodePNG", url: "https://github.com/troughton/LodePNG-SPM", from: "0.0.1"),
        .package(url: "https://github.com/troughton/SwiftImGui", from: "1.7.32"),
        .package(url: "https://github.com/troughton/SwiftMath", from: "5.0.0")
    ],
    targets: [
        // FrameGraph
        .target(name: "FrameGraphTextureIO", dependencies: ["SwiftFrameGraph", .product(name: "stb_image", package: "Cstb"), .product(name: "stb_image_resize", package: "Cstb"), .product(name: "stb_image_write", package: "Cstb"), .product(name: "tinyexr", package: "Cstb"), .product(name: "LodePNG", package: "LodePNG")]),
        .target(name: "FrameGraphCExtras", dependencies: vulkanDependencies, exclude: ["CMakeLists.txt"]),
        .target(name: "SwiftFrameGraph", dependencies: ["FrameGraphUtilities", "FrameGraphCExtras", .product(name: "CAtomics", package: "SwiftAtomics"), .product(name: "SPIRV-Cross", package: "SPIRV-Cross")] + vulkanDependencies, path: "Sources/FrameGraph", exclude: ["CMakeLists.txt", "FrameGraph/CMakeLists.txt", "FrameGraph/BackendExecution/CMakeLists.txt", "MetalBackend/CMakeLists.txt", "VulkanBackend/CMakeLists.txt"]),
        .target(name: "FrameGraphUtilities", dependencies: [.product(name: "CAtomics", package: "SwiftAtomics")], exclude: ["CMakeLists.txt"]),
    
        // ShaderTool
        .target(
            name: "ShaderTool",
            dependencies: [.product(name: "SPIRV-Cross", package: "SPIRV-Cross"), "SwiftFrameGraph", "Regex", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        
        // AppFramework
        .systemLibrary(
            name: "CSDL2",
            pkgConfig: "sdl2",
            providers: [
                .brew(["sdl2"]),
                .apt(["sdl2"]),
            ]
        ),
        .target(name: "CNativeFileDialog", exclude: ["CMakeLists.txt"]),
        .target(
            name: "AppFramework",
            dependencies: ["FrameGraphUtilities", "SwiftFrameGraph", "SwiftMath", .product(name: "ImGui", package: "SwiftImGui"), "CNativeFileDialog", "CSDL2"] + vulkanDependencies,
            exclude: ["CMakeLists.txt", "Input/CMakeLists.txt", "UpdateScheduler/CMakeLists.txt", "Windowing/CMakeLists.txt"]),
    ],
    cLanguageStandard: .c11, cxxLanguageStandard: .cxx14
)

//#if !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
//package.targets.append(
//    .systemLibrary(
//        name: "Vulkan",
//        path: "Sources/Vulkan",
//        providers: [
//            .apt("vulkan")
//        ])
//)
//#endif
