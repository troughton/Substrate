// swift-tools-version:5.2

import PackageDescription

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
let vulkanDependencies: [Target.Dependency] = []
#else
let vulkanDependencies: [Target.Dependency] = [.target(name: "Vulkan")]
#endif

let package = Package(
    name: "Substrate",
    platforms: [.macOS(.v10_14), .iOS(.v13), .tvOS(.v13)],
    products: [
        .library(name: "SwiftFrameGraph", targets: ["Substrate", "SwiftFrameGraph"]),
        .library(name: "FrameGraphTextureIO", targets: ["SubstrateTextureIO", "FrameGraphTextureIO"]),
        .library(name: "FrameGraphUtilities", targets: ["SubstrateUtilities", "FrameGraphUtilities"]),
        
        .library(name: "Substrate", targets: ["Substrate"]),
        .library(name: "SubstrateUtilities", targets: ["SubstrateUtilities"]),
        .library(name: "SubstrateImage", targets: ["SubstrateImage"]),
        .library(name: "SubstrateTextureIO", targets: ["SubstrateImage", "SubstrateTextureIO"]),
        .library(name: "SubstrateMath", targets: ["SubstrateMath"]),
        .library(name: "AppFramework", targets: ["AppFramework"]),
        .executable(name: "ShaderTool", targets: ["ShaderTool"])
    ],
    dependencies: [
        .package(name: "swift-atomics", url: "https://github.com/apple/swift-atomics", from: "1.0.1"),
        .package(name: "SPIRV-Cross", url: "https://github.com/troughton/SPIRV-Cross-SPM", from: "0.44.0"),
        .package(url: "https://github.com/sharplet/Regex", from: "2.1.0"),
        .package(url: "https://github.com/troughton/Cstb", from: "1.0.5"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.1"),
        .package(name: "Wuffs", url: "https://github.com/troughton/Wuffs-SPM", from: "0.3.02"),
        .package(name: "LodePNG", url: "https://github.com/troughton/LodePNG-SPM", from: "0.0.1"),
        .package(url: "https://github.com/troughton/SwiftImGui", .branch("docking")),
        .package(url: "https://github.com/apple/swift-numerics", from: "0.1.0"),
        .package(url: "https://github.com/apple/swift-collections/", .upToNextMajor(from: "0.0.2"))
    ],
    targets: [
        // FrameGraph compatibility libraries
        .target(name: "FrameGraphTextureIO", dependencies: ["SubstrateTextureIO"]),
        .target(name: "FrameGraphUtilities", dependencies: ["SubstrateUtilities"]),
        .target(name: "SwiftFrameGraph", dependencies: ["Substrate"]),
        
        // SubstrateMath
        .target(name: "SubstrateMath", dependencies: [.product(name: "RealModule", package: "swift-numerics")]),
        .testTarget(name: "SubstrateMathTests", dependencies: ["SubstrateMath", .product(name: "RealModule", package: "swift-numerics")]),
        
        // Substrate
        .target(name: "SubstrateImage", dependencies: [
                    .product(name: "stb_image", package: "Cstb"),
                    .product(name: "stb_image_resize", package: "Cstb"),
                    .product(name: "stb_image_write", package: "Cstb"),
                    .product(name: "tinyexr", package: "Cstb"),
                    .product(name: "LodePNG", package: "LodePNG"),
                    .product(name: "WuffsAux", package: "Wuffs"),
                    .product(name: "CWuffs", package: "Wuffs"),
                    .product(name: "RealModule", package: "swift-numerics")],
                swiftSettings: [
                    .unsafeFlags([
                        "-Xfrontend", "-enable-experimental-concurrency",
                        "-Xfrontend", "-disable-availability-checking",
                    ])
                ]),
        
        .testTarget(name: "SubstrateImageTests", dependencies: ["SubstrateImage"]),
        
        .target(name: "SubstrateTextureIO", dependencies: ["Substrate", "SubstrateImage"],
                swiftSettings: [
                    .unsafeFlags([
                        "-Xfrontend", "-enable-experimental-concurrency",
                        "-Xfrontend", "-disable-availability-checking",
                    ])
                ]),
        
        .target(name: "SubstrateCExtras", dependencies: vulkanDependencies, exclude: ["CMakeLists.txt"]),
        .target(name: "Substrate", dependencies: ["SubstrateUtilities", "SubstrateCExtras", .product(name: "Atomics", package: "swift-atomics"), .product(name: "SPIRV-Cross", package: "SPIRV-Cross"), .product(name: "OrderedCollections", package: "swift-collections")] + vulkanDependencies, path: "Sources/Substrate", exclude: ["CMakeLists.txt", "MetalBackend/CMakeLists.txt", "VulkanBackend/CMakeLists.txt"],
                swiftSettings: [
                    .unsafeFlags([
                        "-Xfrontend", "-enable-experimental-concurrency",
                        "-Xfrontend", "-disable-availability-checking",
                    ])
                ]),
        .target(name: "SubstrateUtilities", dependencies: [.product(name: "Atomics", package: "swift-atomics")], exclude: ["CMakeLists.txt"],
                swiftSettings: [
                    .unsafeFlags([
                        "-Xfrontend", "-enable-experimental-concurrency",
                        "-Xfrontend", "-disable-availability-checking",
                    ])
                ]),
        .testTarget(name: "SubstrateUtilitiesTests", dependencies: ["SubstrateUtilities"]),
        
        // ShaderTool
        .target(name: "SPIRVCrossExtras",
                dependencies: [.product(name: "SPIRV-Cross", package: "SPIRV-Cross")]),
        
        .target(
            name: "ShaderTool",
            dependencies: [.product(name: "SPIRV-Cross", package: "SPIRV-Cross"), "SPIRVCrossExtras", "Substrate", "Regex", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        
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
            dependencies: ["SubstrateUtilities", "Substrate", "SubstrateMath", .product(name: "ImGui", package: "SwiftImGui"), "CNativeFileDialog", "CSDL2"] + vulkanDependencies,
            exclude: ["CMakeLists.txt", "Input/CMakeLists.txt", "UpdateScheduler/CMakeLists.txt", "Windowing/CMakeLists.txt"],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-enable-experimental-concurrency",
                    "-Xfrontend", "-disable-availability-checking",
                    "-Xfrontend", "-validate-tbd-against-ir=none",
                ])
            ]),
    ],
    cLanguageStandard: .c11, cxxLanguageStandard: .cxx14
)

#if !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
package.targets.append(
        .systemLibrary(
            name: "Vulkan",
            pkgConfig: "vulkan",
            providers: [
                .apt(["vulkan"]),
            ]
        )
)
#endif

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
