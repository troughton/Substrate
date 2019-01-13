# SwiftFrameGraph

_Note: The current version of SwiftFrameGraph on `master` has not been thoroughly tested on Vulkan. If you run into issues building from `master` and using `Vulkan`, the `Vulkan` branch contains the last version tested to be working on Vulkan, although its API has fallen significantly behind `master`._

## What is this?

In short: this is a way to code against a higher-level, Swift-native, reduced-friction version of the Metal rendering API and have your rendering code run in a fairly efficient manner, cross-platform on both Metal and Vulkan.

This is the base rendering system for a game I'm working on with a few other people called Interdimensional Llama. More specifically, it's a platform-agnostic abstraction over a rendering API, combined with backends for Metal and Vulkan. Its design is heavily inspired by Metal; in fact, it started off as a direct overlay over Metal, and gradually diverged. As such, [Apple's Metal documentation](https://developer.apple.com/documentation/metal) is probably the best general reference for RenderAPI, since it's what we referred to.

The Metal backend has received the most attention, and should be _reasonably_ optimised and stable. The Vulkan backend works for our use cases but could have a few bugs and inefficiencies.

This project does _not_ handle cross-compilation of shaders. For that, you'll want to use other tools; in our case, we've been writing our shaders once for each of Vulkan and Metal.

[This early demo](https://www.youtube.com/watch?v=Nlr7m4rq37A) (which is not at all representative of the game or art style) is an example of something that was made using this framework.

## What's the motivation?

Recently there's been an interest in render-graph based APIs for rendering, making it simpler to compose together multiple render passes and build frames. To my knowledge, the origin of this is [in the Frostbite engine, as described by this talk](https://www.ea.com/frostbite/news/framegraph-extensible-rendering-architecture-in-frostbite), although [many](http://ourmachinery.com/post/high-level-rendering-using-render-graphs/) [others](http://themaister.net/blog/2017/08/15/render-graphs-and-vulkan-a-deep-dive/) have had their input since.

A key contribution of render graphs is that per-frame resource management is done automatically; rather than manually managing buffers and buffer pools, you can just request a new buffer each frame. Originally, our implementation was fairly closely based on the described design; however, we decided to take things one step further.

A major annoyance with APIs such as Vulkan is that you have to be explicit about _everything_. You need to describe how a buffer will be used, for example, or outline every barrier to insert. With Metal, the overhead is a little less, but as soon as you want to do manual resource tracking, or use resource heaps, or other such advanced features, you soon run into the same problem.

The main idea behind this framework is that if we execute in a _deferred_ mode, we can infer a lot of things we'd otherwise need to specify; we can record a frame, tracking how each resource is used, and then execute the frame. Furthermore, we can infer _how_ the resource is used based on information from shader reflection – we can tell whether an image is sampled, written to, or read from in a shader, for example. What I mean by deferred is basically that each render pass runs twice: the first time, the resource tracking code plans out what will be needed for the frame, and the second time the commands are actually called to the underlying API (Vulkan or Metal).

In practice, this has some really neat effects. For example, our engine uses clustered shading, and performs light culling on the CPU in a `CPURenderPass`. During some experiments, I commented out the lighting code in the shader that makes use of the clustered shading buffers. Given that, the shader compiler optimised out the use of those resources; then when the Frame Graph executed, it could see that the output of that pass was never used, and prevented it from being executed at all.

Another thing a deferred setup means is that per-frame resources can be handled extremely easily. Want a buffer with some data in it? 

```swift
let vertexBufferDescriptor = BufferDescriptor(length: renderData.vertexBuffer.count * MemoryLayout<ImDrawVert>.size)
let vertexBuffer = Buffer(descriptor: vertexBufferDescriptor, bytes: renderData.vertexBuffer.baseAddress!)
renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
```

That will automatically get allocated with the correct flags and disposed without any GPU overhead (if you're curious how, take a look at the Metal and Vulkan backends, and in particular ResourceRegistry.swift). Dependency ordering is determined by the order that render passes are added to the `FrameGraph`.

This method is significantly simpler than the two-stage setup and resource handles used in e.g. Frostbite's design. You treat resources as simple objects, creating them when you need them and letting them be deallocated once you're done.

Persistent resources are a little trickier. To create them, you pass `.persistent` as a flag in the `Buffer` or `Texture` constructor, and you make sure that the `usageHint` in the descriptor matches how it's going to be used. If you make or dispose persistent resources frequently the code will still work, but you'll be losing out on a lot of the benefits and incurring a large overhead.

## Where can I see how it works?

A good place to start would be the main render pass execution in [CommandRecorder.swift](Sources/FrameGraph/FrameGraph/CommandRecorder.swift).

With regards to the backends, take a look at the [Vulkan](Sources/FrameGraph/Backends/Vulkan/VkRenderer/FrameGraphBackend.swift) and [Metal](Sources/FrameGraph/Backends/MetalRenderer/FrameGraphBackend.swift) backends.

## How practical is this to use in my personal projects?

Honestly? Probably not very, although it'll work if you're determined and willing to look around the code base. Almost all of the documentation is contained within my and the other authors' heads, and there are a few edge cases or hidden functionality. While we'd like to properly document this project, it's a fairly low priority for us; we understand it, and we're the primary users, so that's enough for us in making our game. Long-term, however, we'd definitely like for this code-base to live up to the standards of a high-quality open source project. 

We do plan to release a more full-featured example project, including a [Dear ImGui](https://github.com/ocornut/imgui) render pass and a debug drawing tool. The problem is that the rest of the code is fairly tightly intertwined with our engine, and we're not wanting to open source our full engine - as such, it might be a while before we have time to release it.

With all that said, this is open source so others can use it! We'd welcome input to make it better or easier to use. 

## What does a Render Pass look like?

Here's an example of a draw render pass from our engine to draw debug shapes (wireframe outlines, points, and lines). It hasn't been cleaned up at all, so forgive the slight messiness.

```swift
final class DebugDrawPass : DrawRenderPass {

    static let pointLineVertexDescriptor : VertexDescriptor = {
        var descriptor = VertexDescriptor()

        // position
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].format = .float3

        // color
        descriptor.attributes[1].bufferIndex = 0
        descriptor.attributes[1].offset = 3 * MemoryLayout<Float>.size
        descriptor.attributes[1].format = .float4

        // point size
        descriptor.attributes[2].bufferIndex = 0
        descriptor.attributes[2].offset = 7 * MemoryLayout<Float>.size
        descriptor.attributes[2].format = .float


        descriptor.layouts[0].stepFunction = .perVertex
        descriptor.layouts[0].stepRate = 1
        descriptor.layouts[0].stride = MemoryLayout<DebugDraw.DebugDrawVertex>.size

        return descriptor
    }()

    static let depthStencilNoDepth : DepthStencilDescriptor = {
        var depthStencilDescriptor = DepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .always
        depthStencilDescriptor.isDepthWriteEnabled = false
        return depthStencilDescriptor
    }()

    static let depthStencilWithDepth : DepthStencilDescriptor = {
        var depthStencilDescriptor = DepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .greater
        depthStencilDescriptor.isDepthWriteEnabled = true
        return depthStencilDescriptor
    }()

    static let pipelineDescriptor : RenderPipelineDescriptor = {
        var descriptor = RenderPipelineDescriptor(identifier: ScreenRenderTargetIndex.self)

        var blendDescriptor = BlendDescriptor()

        blendDescriptor.alphaBlendOperation = .add
        blendDescriptor.rgbBlendOperation = .add
        blendDescriptor.sourceRGBBlendFactor = .sourceAlpha
        blendDescriptor.sourceAlphaBlendFactor = .sourceAlpha
        blendDescriptor.destinationRGBBlendFactor = .oneMinusSourceAlpha
        blendDescriptor.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        descriptor[blendStateFor: ScreenRenderTargetIndex.display] = blendDescriptor

        descriptor.vertexDescriptor = DebugDrawPass.pointLineVertexDescriptor

        descriptor.vertexFunction = "debugDrawVertexLinePoint"
        descriptor.fragmentFunction = "debugDrawFragmentLinePoint"

        return descriptor
    }()


    let renderTargetDescriptor: RenderTargetDescriptor

    var name: String = "Debug Draw"

    let renderData : DebugDraw.RenderData
    let viewUniforms : ViewRenderUniforms

    let outputTexture: Texture

    init(renderData: DebugDraw.RenderData, outputTexture: Texture, viewUniforms: ViewRenderUniforms) {
        self.renderData = renderData
        self.viewUniforms = viewUniforms

        var renderTargetDesc = RenderTargetDescriptor(identifierType: ScreenRenderTargetIndex.self)
        renderTargetDesc[ScreenRenderTargetIndex.display] = RenderTargetColorAttachmentDescriptor(texture: outputTexture)
        renderTargetDesc[ScreenRenderTargetIndex.display]!.clearColor = ClearColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0)
	self.renderTargetDescriptor = renderTargetDesc
    }

    func execute(renderCommandEncoder: RenderCommandEncoder) {

        if self.renderData.vertexBuffer.isEmpty {
            return //early out
        }

        let vertexBuffer = Buffer(descriptor: BufferDescriptor(length: MemoryLayout<DebugDraw.DebugDrawVertex>.size * self.renderData.vertexBuffer.count), bytes: self.renderData.vertexBuffer.buffer)
        let indexBuffer = Buffer(descriptor: BufferDescriptor(length: MemoryLayout<UInt16>.size * self.renderData.indexBuffer.count), bytes: self.renderData.indexBuffer.buffer)

        renderCommandEncoder.setRenderPipelineState(DebugDrawPass.pipelineDescriptor)
        renderCommandEncoder.setCullMode(.none)
        renderCommandEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderCommandEncoder.setValue(self.viewUniforms, key: "drawVertexUniforms")

        var vertexBufferOffset = 0
        var indexBufferOffset = 0

        for drawCommand in self.renderData.commands {
            renderCommandEncoder.setVertexBufferOffset(vertexBufferOffset, index: 0)

            var primitiveType : PrimitiveType? = nil

            switch drawCommand.type {
                case .point:
                    primitiveType = .point
                case .line:
                    primitiveType = .line
                case .triangle:
                    primitiveType = .triangle
            }

            if let primitiveType = primitiveType {
                renderCommandEncoder.setDepthStencilState(drawCommand.depthEnabled ? DebugDrawPass.depthStencilWithDepth : DebugDrawPass.depthStencilNoDepth)

                if primitiveType == .point {
                    renderCommandEncoder.drawPrimitives(type: primitiveType, vertexStart: 0, vertexCount: drawCommand.vertexCount)
                } else {
                    renderCommandEncoder.drawIndexedPrimitives(type: primitiveType, indexCount: drawCommand.indexCount!, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: indexBufferOffset)
                    indexBufferOffset += drawCommand.indexCount! * MemoryLayout<UInt16>.size
                }

                vertexBufferOffset += drawCommand.vertexCount * MemoryLayout<DebugDraw.DebugDrawVertex>.size
            }
        }
    }
}
```

Every frame, you'd call something like this:

```swift
let debugDrawPass = DebugDrawPass(outputTexture: texture, renderData: debugDrawData, viewUniforms: viewUniforms)
FrameGraph.addPass(debugDrawPass)

```

and then execute the FrameGraph using a call like:

```swift
FrameGraph.execute(backend: self.backend)
```

where `self.backend` is an instance of either the Metal or Vulkan backends. 

To get something to display on screen, you'd pass in a `Texture` from a window (take a look at the Windowing subdirectory) as the `outputTexture`. Otherwise, you could create or pass in a texture such as:

```swift
var textureDescriptor = TextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: Int(self.drawableSize.width), height: Int(self.drawableSize.height), mipmapped: false)
let emissiveTexture = Texture(descriptor: textureDescriptor)
let debugDrawPass = DebugDrawPass(outputTexture: emissiveTexture, renderData: debugDrawData, viewUniforms: viewUniforms, motionVectorsEnabled: renderSettings.temporalAAEnabled)
```

## How do I build it?

### macOS

Using a recent [Swift toolchain](https://swift.org), run `./build_metal_macos.sh` from the cloned directory to generate an Xcode project, and then build the frameworks from within Xcode.

### Linux

Untested, but using a recent [Swift toolchain](https://swift.org) and running `swift build` in the cloned directory should be enough.

### Windows

Swift on Windows is a very early work in progress, and while I can promise you this works, I can't really tell you how to build it. I will say that we cross-compile Windows binaries from Ubuntu for Windows, since Swift Package Manager is a long way from supporting Windows.

I've also included our overlays for Foundation for Windows. If this is interesting to you, make use of it however you please.

## Why Swift? 

I think Swift's a great language, and it's what we wanted to use when making our engine. In particular, the use case this was built for doesn't require much interoperability with existing C++ code, which enabled us to use a more modern and ergonomic language.

## What about multithreading?

The FrameGraph automatically executes all non-CPU render passes in parallel, and the Metal backend will use parallel render command encoders where it makes sense. This does mean that you need to ensure that all `Draw`, `Blit`, and `Compute` render passes don't change any external state that other passes depend on in their `execute` methods; instead, any such changes should be made in their `init` methods or elsewhere.

## What about (some other question here)?

Feel free to post an issue. If you're genuinely curious about getting something to work with this we'd be more than happy to help.

## License

See the MIT license in [LICENSE](LICENSE.md). Other licenses may apply to included libraries.
