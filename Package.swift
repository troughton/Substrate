// swift-tools-version:4.0

import PackageDescription

#if os(macOS)
let supportedRenderAPIs = ["MetalRenderer"]
#else
let supportedRenderAPIs = ["VkRenderer"]
#endif

let package = Package(
    name: "SwiftFrameGraph",
    dependencies: [
        .package(url: "https://github.com/glessard/swift-atomics", from: Version("4.1.0"))
    ],
    targets: [
        .target(name: "FrameGraphCExtras", dependencies: [],
                path: "Sources/FrameGraph/FrameGraphCExtras"),
        .target(name: "SwiftFrameGraph", dependencies: ["Utilities", "FrameGraphCExtras", "Atomics"],
                path: "Sources/FrameGraph/FrameGraph"),
        
        .target(name: "Utilities", dependencies: []),
        
        .target(name: "SwiftMath", dependencies: []),
        
        .target(name: "Windowing", dependencies: ["SwiftFrameGraph", "Utilities", "DrawTools", "SwiftMath"] + supportedRenderAPIs.map { Target.Dependency(stringLiteral: $0) }),
        
        .target(name: "CDebugDrawTools", dependencies: [],
                path: "Sources/DrawTools/CDebugDrawTools"),
        
        .target(name: "DrawTools", dependencies: ["CDebugDrawTools", "SwiftMath", "SwiftFrameGraph"],
                path: "Sources/DrawTools/DrawTools"),
        ],
    cLanguageStandard: .c11, cxxLanguageStandard: .cxx14
)

#if os(Windows)

for target in package.targets {
    target.dependencies.append("Foundation")
    target.dependencies.append("Dispatch")
    target.dependencies.append("ShaderTypes")
}

package.targets.append(contentsOf: [
    .target(name: "CFoundationExtras", path: "Sources/WindowsOverlays/CFoundationExtras"),
    .target(name: "Foundation", dependencies: ["Dispatch", "CFoundationExtras"], path: "Sources/WindowsOverlays/Foundation"),
    .target(name: "Dispatch", path: "Sources/WindowsOverlays/Dispatch")
    ]
    )

#endif

let baseRenderDependencies : [Target.Dependency] = ["SwiftFrameGraph"]
let basePath = "Sources/FrameGraph/Backends/"

for api in supportedRenderAPIs {
    var renderDepedencies = baseRenderDependencies
    var path = basePath

    if api == "VkRenderer" {
        package.targets.append(.target(name: "SPIRV-Cross", path: "Sources/FrameGraph/Backends/Vulkan/SPIRV-Cross", publicHeadersPath: ""))
        package.targets.append(.target(name: "CVkRenderer", dependencies: ["SPIRV-Cross"], path: "Sources/FrameGraph/Backends/Vulkan/CVkRenderer"))
        
        renderDepedencies.append("CVkRenderer")
        
        path += "Vulkan/"
    }
    
    package.targets.append(
        .target(name: api, dependencies: renderDepedencies,
        path: path + api)
    )
    
}
