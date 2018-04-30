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
    ],
    targets: [
        .target(name: "FrameGraph", dependencies: ["Utilities", "RenderAPI"],
                path: "Sources/FrameGraph/FrameGraph"),
        
        .target(name: "RenderAPI", dependencies: ["Utilities"],
                path: "Sources/RenderAPI"),
        
        .target(name: "Utilities", dependencies: []),
        ],
    cLanguageStandard: .c11, cxxLanguageStandard: .cxx14
)

#if !os(macOS)

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

let baseRenderDependencies : [Target.Dependency] = ["RenderAPI", "FrameGraph"]
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
