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
        .library(name: "SwiftFrameGraph", targets: ["SwiftFrameGraph"]),
        .library(name: "FrameGraphUtilities", targets: ["FrameGraphUtilities"]),
    ],
    dependencies: [
        .package(url: "https://github.com/troughton/swift-atomics", .branch("patch-1")),
         .package(url: "https://github.com/troughton/SPIRV-Cross-SPM", from: "0.21.1"),
         .package(url: "https://github.com/sharplet/Regex", from: "2.1.0")
    ],
    targets: [
        .target(name: "FrameGraphCExtras", dependencies: []),
        .target(name: "SwiftFrameGraph", dependencies: ["FrameGraphUtilities", "FrameGraphCExtras", "SwiftAtomics"], path: "Sources/FrameGraph"),
        .target(name: "FrameGraphUtilities", dependencies: ["SwiftAtomics"]),
        .target(
            name: "ShaderReflectionGenerator",
            dependencies: ["SPIRV-Cross", "SwiftFrameGraph", "Regex"]),
    ],
    cLanguageStandard: .c11, cxxLanguageStandard: .cxx14
)
