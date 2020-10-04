//
//  VulkanImage.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 6/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras
import FrameGraphUtilities

extension VkImageViewType : Hashable {
    public func hash(into hasher: inout Hasher) {
        rawValue.hash(into: &hasher)
    }
}

extension VkFormat : Hashable {
    public func hash(into hasher: inout Hasher) {
        rawValue.hash(into: &hasher)
    }
}

extension VkComponentMapping : Hashable {
    public static func == (lhs: VkComponentMapping, rhs: VkComponentMapping) -> Bool {
        return lhs.r == rhs.r &&
            lhs.g == rhs.g &&
            lhs.b == rhs.b &&
            lhs.a == rhs.a
    }
    
    public func hash(into hasher: inout Hasher) {
        r.rawValue.hash(into: &hasher)
        g.rawValue.hash(into: &hasher)
        b.rawValue.hash(into: &hasher)
        a.rawValue.hash(into: &hasher)
    }
}

extension VkImageSubresourceRange : Hashable {
    public static func == (lhs: VkImageSubresourceRange, rhs: VkImageSubresourceRange) -> Bool {
        return lhs.aspectMask == rhs.aspectMask &&
            lhs.baseArrayLayer == rhs.baseArrayLayer &&
            lhs.baseMipLevel == rhs.baseMipLevel &&
            lhs.layerCount == rhs.layerCount &&
            lhs.levelCount == rhs.levelCount
    }
    
    public func hash(into hasher: inout Hasher) {
        aspectMask.hash(into: &hasher)
        baseArrayLayer.hash(into: &hasher)
        baseMipLevel.hash(into: &hasher)
        layerCount.hash(into: &hasher)
        levelCount.hash(into: &hasher)
    }
}

class VulkanImage {
    public let device : VulkanDevice
    
    struct ViewDescriptor : Hashable {
        public var flags: VkImageViewCreateFlags
        public var viewType: VkImageViewType
        public var format: VkFormat
        public var components: VkComponentMapping
        public var subresourceRange: VkImageSubresourceRange
    }
    
    struct LayoutState {
        var commandRange: Range<Int>
        var layout: VkImageLayout
        var subresourceRange: ActiveResourceRange
    }
    
    let vkImage : VkImage
    let allocator : VmaAllocator?
    let allocation : VmaAllocation?
    let descriptor : VulkanImageDescriptor
    
    var label : String? = nil
    
    var swapchainImageIndex : Int? = nil
    
    var defaultImageView : VulkanImageView! = nil
    var views = [ViewDescriptor : VulkanImageView]()
    
    var frameLayouts: [LayoutState]
    var frameLayoutsLastFrameIndex = UInt64.max

    init(device: VulkanDevice, image: VkImage, allocator: VmaAllocator?, allocation: VmaAllocation?, descriptor: VulkanImageDescriptor) {
        self.device = device
        self.vkImage = image
        self.allocator = allocator
        self.allocation = allocation
        self.descriptor = descriptor
        self.frameLayouts = [LayoutState(commandRange: -1..<0, layout: descriptor.initialLayout, subresourceRange: .fullResource)]
        
        do {
            var createInfo = VkImageViewCreateInfo()
            createInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
            
            createInfo.image = image
            createInfo.viewType = self.descriptor.imageViewType
            createInfo.format = self.descriptor.format
            
            var subresourceRange = VkImageSubresourceRange()
            var aspectMask = VkImageAspectFlagBits()
            
            /*
             Specification for VkImageSubresourceRange:
             
             When using an imageView of a depth/stencil image to populate a descriptor set
             (e.g. for sampling in the shader, or for use as an input attachment), the aspectMask
             must only include one bit and selects whether the imageView is used for depth reads
             (i.e. using a floating-point sampler or input attachment in the shader) or stencil
             reads (i.e. using an unsigned integer sampler or input attachment in the shader).
             When an imageView of a depth/stencil image is used as a depth/stencil framebuffer attachment,
             the aspectMask is ignored and both depth and stencil image subresources are used.
             */
            
            if descriptor.format.isDepthStencil {
                aspectMask.formUnion(VK_IMAGE_ASPECT_DEPTH_BIT) // FIXME: we assume that you always want to sample depth when sampling a depth-stencil image.
            } else if descriptor.format.isDepth {
                aspectMask.formUnion(VK_IMAGE_ASPECT_DEPTH_BIT)
            } else if descriptor.format.isStencil {
                aspectMask.formUnion(VK_IMAGE_ASPECT_STENCIL_BIT)
            } else {
                aspectMask = VK_IMAGE_ASPECT_COLOR_BIT
            }
            subresourceRange.aspectMask = VkImageAspectFlags(aspectMask)
            subresourceRange.baseArrayLayer = 0
            subresourceRange.baseMipLevel = 0
            switch descriptor.imageViewType {
            case VK_IMAGE_VIEW_TYPE_CUBE:
                subresourceRange.layerCount = 6
            default:
                subresourceRange.layerCount = self.descriptor.arrayLayers
            }
            subresourceRange.levelCount = self.descriptor.mipLevels
            createInfo.subresourceRange = subresourceRange
            
            var imageView : VkImageView? = nil
            vkCreateImageView(self.device.vkDevice, &createInfo, nil, &imageView)
            self.defaultImageView = VulkanImageView(image: self, vkView: imageView!)
        }
    }
    
    deinit {
        self.clearFrameLayouts()
        if let allocator = self.allocator, let allocation = self.allocation {
            vmaDestroyImage(allocator, self.vkImage, allocation)
        } else {
            vkDestroyImage(self.device.vkDevice, self.vkImage, nil)
        }
    }
    
    func matches(descriptor: VulkanImageDescriptor) -> Bool {
        return self.descriptor.matches(descriptor: descriptor)
    }
    
    func computeFrameLayouts(resource: Resource, usages: ChunkArray<ResourceUsage>, preserveLastLayout: Bool, frameIndex: UInt64) {
        defer { self.frameLayoutsLastFrameIndex = frameIndex }
        
        let subresourceCount = self.descriptor.subresourceCount
        
        if frameIndex != self.frameLayoutsLastFrameIndex {
            // If we don't already have some layouts assigned for this frame (for a different resource).
            // NOTE: we use the system allocator for subresource masks within the frameLayouts array
            let previousLayouts = self.frameLayouts
            defer {
                previousLayouts.forEach { $0.subresourceRange.deallocateStorage(subresourceCount: subresourceCount, allocator: .system) }
            }
            
            self.frameLayouts.removeAll(keepingCapacity: true)
            if !preserveLastLayout {
                self.frameLayouts.append(LayoutState(commandRange: -1..<0,
                                                     layout: VK_IMAGE_LAYOUT_UNDEFINED,
                                                     subresourceRange: .fullResource))
            } else {
                var remainingSubresources = ActiveResourceRange.fullResource
                for layout in previousLayouts.reversed() {
                    let subresources = remainingSubresources.intersection(with: layout.subresourceRange, subresourceCount: subresourceCount, allocator: .system)
                    remainingSubresources.subtract(range: subresources, subresourceCount: subresourceCount, allocator: .system)
                    
                    self.frameLayouts.append(LayoutState(commandRange: -1..<0,
                                                         layout: layout.layout,
                                                         subresourceRange: subresources))

                    if remainingSubresources.isEqual(to: .inactive, resource: resource) {
                        break
                    }
                }
            }
        }
        
        let isDepthOrStencil = self.descriptor.allAspects.intersection([VK_IMAGE_ASPECT_DEPTH_BIT, VK_IMAGE_ASPECT_STENCIL_BIT]) != []
        
        for usage in usages {
            // Preserve the last layout if the usage doesn't require a specific layout
            let layout = usage.type.imageLayout(isDepthOrStencil: isDepthOrStencil) ?? 
                self.frameLayouts.last(where: { $0.subresourceRange.intersects(with: usage.activeRange, subresourceCount: self.descriptor.subresourceCount) })!.layout
            // Find the insertion location (since reads may be unordered in the usages list).
            self.frameLayouts.append(LayoutState(commandRange: usage.commandRange, layout: layout, subresourceRange: ActiveResourceRange(usage.activeRange, subresourceCount: subresourceCount, allocator: .system)))
        }
        
        // Merge reads of different layouts to use the VK_IMAGE_LAYOUT_GENERAL layout so we don't need to insert layout transition barriers between reads.
        let readLayouts = [VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL]
        
        var i = self.frameLayouts.firstIndex(where: { $0.commandRange.lowerBound >= 0 }) ?? self.frameLayouts.endIndex
        while i < self.frameLayouts.endIndex {
            if readLayouts.contains(self.frameLayouts[i].layout) {
                var makeGeneralLayout = false
                var generalLayoutEndIndex = -1
                
                for j in self.frameLayouts.index(after: i)..<self.frameLayouts.endIndex {
                    if !readLayouts.contains(self.frameLayouts[j].layout) { break }
                    generalLayoutEndIndex = j + 1
                    if self.frameLayouts[j].layout != self.frameLayouts[i].layout {
                        makeGeneralLayout = true
                    }
                }
                
                if makeGeneralLayout {
                    for j in i..<generalLayoutEndIndex {
                        self.frameLayouts[j].layout = VK_IMAGE_LAYOUT_GENERAL
                    }
                    i = generalLayoutEndIndex
                    continue
                }
            }
            
            i = self.frameLayouts.index(after: i)
        }
    }
    
    func clearFrameLayouts() {
        self.frameLayouts.forEach { $0.subresourceRange.deallocateStorage(subresourceCount: self.descriptor.subresourceCount, allocator: .system) }
        self.frameLayouts.removeAll()
    }
    
    func frameInitialLayout(for subresources: ActiveResourceRange, allocator: AllocatorType) -> (VkImageLayout, layoutSubresource: ActiveResourceRange, unhandledSubresources: ActiveResourceRange) {
        var remainingSubresources = subresources
        
        guard let layout = self.frameLayouts.prefix(while: { $0.commandRange.upperBound <= 0}).first(where: { $0.subresourceRange.intersects(with: remainingSubresources, subresourceCount: self.descriptor.subresourceCount) }) else {
            preconditionFailure("No initial layout found for range \(subresources); layouts are \(self.frameLayouts)")
        }
        remainingSubresources.subtract(range: layout.subresourceRange, subresourceCount: self.descriptor.subresourceCount, allocator: allocator)
        let intersectedSubresources = subresources.intersection(with: layout.subresourceRange, subresourceCount: self.descriptor.subresourceCount, allocator: allocator)
        return (layout.layout, intersectedSubresources, remainingSubresources)
    }
    
    func layout(commandIndex: Int, subresourceRange: ActiveResourceRange) -> VkImageLayout {
        guard let layout = self.frameLayouts.first(where: { $0.commandRange.contains(commandIndex) && $0.subresourceRange.intersects(with: subresourceRange, subresourceCount: self.descriptor.subresourceCount) })?.layout else {
            preconditionFailure("Command index \(commandIndex) does not correspond to a usage of this image for range \(subresourceRange); layouts are \(self.frameLayouts)")
        }
        return layout
    }
    
    func layout(commandIndex: Int, slice: Int, level: Int, descriptor: TextureDescriptor) -> VkImageLayout {
        guard let layout = self.frameLayouts.first(where: { $0.commandRange.contains(commandIndex) && $0.subresourceRange.intersects(textureSlice: slice, level: level, descriptor: descriptor) })?.layout else {
            preconditionFailure("Command index \(commandIndex) does not correspond to a usage of this image (descriptor \(descriptor)) for slice \(slice) and level \(level); layouts are \(self.frameLayouts)")
        }
        return layout
    }

    func renderPassLayouts(previousCommandIndex: Int, nextCommandIndex: Int, slice: Int, level: Int, texture: Texture) -> (VkImageLayout, VkImageLayout) {
        var initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        var finalLayout = self.swapchainImageIndex != nil ? VK_IMAGE_LAYOUT_PRESENT_SRC_KHR : VK_IMAGE_LAYOUT_UNDEFINED

        for layout in self.frameLayouts {
            if previousCommandIndex >= 0, layout.commandRange.contains(previousCommandIndex), layout.subresourceRange.intersects(textureSlice: slice, level: level, descriptor: texture.descriptor) {
                initialLayout = layout.layout
            }
            if nextCommandIndex >= 0, layout.commandRange.contains(nextCommandIndex), layout.subresourceRange.intersects(textureSlice: slice, level: level, descriptor: texture.descriptor) {
                finalLayout = layout.layout
                break
            }
        }
        if finalLayout == VK_IMAGE_LAYOUT_UNDEFINED {
            finalLayout = self.frameLayouts.last(where: { $0.subresourceRange.intersects(textureSlice: slice, level: level, descriptor: texture.descriptor) })!.layout
        }

        return (initialLayout, finalLayout)
    }
    
    subscript(viewDescriptor: ViewDescriptor) -> VulkanImageView {
        if let view = self.views[viewDescriptor] {
            return view
        }
        
        var createInfo = VkImageViewCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
        
        createInfo.image = self.vkImage
        createInfo.viewType = viewDescriptor.viewType
        createInfo.format = viewDescriptor.format
        createInfo.subresourceRange = viewDescriptor.subresourceRange
        
        var imageView : VkImageView? = nil
        vkCreateImageView(self.device.vkDevice, &createInfo, nil, &imageView)
        let view = VulkanImageView(image: self, vkView: imageView!)
        
        self.views[viewDescriptor] = view
        return view
    }
    
    func viewForAttachment(descriptor: RenderTargetAttachmentDescriptor) -> VulkanImageView {

        if self.descriptor.imageViewType == VK_IMAGE_VIEW_TYPE_2D, descriptor.level == 0, descriptor.slice == 0, descriptor.depthPlane == 0 {
            return self.defaultImageView
        }
        
        var subresourceRange = VkImageSubresourceRange()
        var aspectMask = VkImageAspectFlagBits()
        if self.descriptor.format.isDepthStencil {
            aspectMask.formUnion([VK_IMAGE_ASPECT_DEPTH_BIT, VK_IMAGE_ASPECT_STENCIL_BIT])
        } else if self.descriptor.format.isDepth {
            aspectMask.formUnion(VK_IMAGE_ASPECT_DEPTH_BIT)
        } else if self.descriptor.format.isStencil {
            aspectMask.formUnion(VK_IMAGE_ASPECT_STENCIL_BIT)
        } else {
            aspectMask = VK_IMAGE_ASPECT_COLOR_BIT
        }
        subresourceRange.aspectMask = VkImageAspectFlags(aspectMask.rawValue)
        subresourceRange.baseArrayLayer = UInt32(max(descriptor.slice, descriptor.depthPlane))
        subresourceRange.baseMipLevel = UInt32(descriptor.level)
        subresourceRange.layerCount = 1
        subresourceRange.levelCount = 1
        
        let descriptor = ViewDescriptor(flags: 0, viewType: VK_IMAGE_VIEW_TYPE_2D, format: self.descriptor.format, components: VkComponentMapping(), subresourceRange: subresourceRange)
        
       return self[descriptor]
    }
}

class VulkanImageView {
    public let image : VulkanImage
    public let vkView : VkImageView
    
    fileprivate init(image: VulkanImage, vkView: VkImageView) {
        self.image = image
        self.vkView = vkView
    }
    
    deinit {
        vkDestroyImageView(self.image.device.vkDevice, self.vkView, nil)
    }
}

struct VulkanImageDescriptor : Equatable {
    var flags : VkImageCreateFlagBits = []
    var imageType : VkImageType = VK_IMAGE_TYPE_2D
    var imageViewType : VkImageViewType = VK_IMAGE_VIEW_TYPE_2D
    var format : VkFormat = VK_FORMAT_R16G16B16A16_SFLOAT
    var extent : VkExtent3D = VkExtent3D(width: 0, height: 0, depth: 0)
    var mipLevels : UInt32 = 1
    var arrayLayers : UInt32 = 1
    var samples : VkSampleCountFlagBits = VK_SAMPLE_COUNT_1_BIT
    var tiling : VkImageTiling = VK_IMAGE_TILING_OPTIMAL
    var usage : VkImageUsageFlagBits = []
    var sharingMode : VulkanSharingMode = .exclusive
    var initialLayout : VkImageLayout = VK_IMAGE_LAYOUT_UNDEFINED
    var storageMode: StorageMode = .private
    var cacheMode: CPUCacheMode = .defaultCache
    
    public init() {
        
    }
    
    public init(_ descriptor: TextureDescriptor, usage: VkImageUsageFlagBits, sharingMode: VulkanSharingMode, initialLayout: VkImageLayout) {
        assert(!usage.isEmpty, "Usage for texture with descriptor \(descriptor) must not be empty.")
        
        self.imageType = VkImageType(descriptor.textureType)
        self.imageViewType = VkImageViewType(descriptor.textureType)
        self.format = VkFormat(pixelFormat: descriptor.pixelFormat)!
        self.extent = VkExtent3D(width: UInt32(descriptor.width), height: UInt32(descriptor.height), depth: UInt32(descriptor.depth))
        self.mipLevels = UInt32(descriptor.mipmapLevelCount)
        self.arrayLayers = UInt32(descriptor.arrayLength)
        self.samples = VK_SAMPLE_COUNT_1_BIT
        self.tiling = descriptor.storageMode == .private ? VK_IMAGE_TILING_OPTIMAL : VK_IMAGE_TILING_LINEAR
        self.usage = usage
        self.sharingMode = sharingMode
        self.initialLayout = initialLayout
        self.storageMode = descriptor.storageMode
        self.cacheMode = descriptor.cacheMode

        if .typeCube == descriptor.textureType || .typeCubeArray == descriptor.textureType {
            self.flags = .cubeCompatible
            self.arrayLayers *= 6
        } else {
            self.flags = []
        }
    }
    
    public var allAspects : VkImageAspectFlagBits {
        if self.format.isDepthStencil {
            return [VK_IMAGE_ASPECT_DEPTH_BIT, VK_IMAGE_ASPECT_STENCIL_BIT]
        } else if self.format.isDepth {
            return VK_IMAGE_ASPECT_DEPTH_BIT
        } else if self.format.isStencil {
            return VK_IMAGE_ASPECT_STENCIL_BIT
        } else {
            return VK_IMAGE_ASPECT_COLOR_BIT
        }
    }
    
    var subresourceCount: Int {
        return Int(self.arrayLayers * self.mipLevels)
    }
    
    public func matches(descriptor: VulkanImageDescriptor) -> Bool {
        return  self.flags.isSuperset(of: descriptor.flags) &&
            self.imageType == descriptor.imageType &&
            self.imageViewType == descriptor.imageViewType &&
            self.format == descriptor.format &&
            self.extent == descriptor.extent &&
            self.mipLevels == descriptor.mipLevels &&
            self.arrayLayers == descriptor.arrayLayers &&
            self.samples == descriptor.samples &&
            self.tiling == descriptor.tiling &&
            self.usage.isSuperset(of: descriptor.usage) &&
            self.sharingMode ~= descriptor.sharingMode &&
            self.storageMode == descriptor.storageMode &&
            self.cacheMode == descriptor.cacheMode
    }
    
    func withImageCreateInfo(device: VulkanDevice, withInfo: (VkImageCreateInfo) -> Void) {
        var createInfo = VkImageCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO

        createInfo.flags = VkImageCreateFlags(self.flags.rawValue)
        createInfo.imageType = self.imageType
        createInfo.format = self.format
        createInfo.extent = self.extent
        createInfo.mipLevels = self.mipLevels
        createInfo.arrayLayers = self.arrayLayers
        createInfo.samples = self.samples
        createInfo.tiling = self.tiling
        createInfo.usage = VkImageUsageFlags(self.usage)
        createInfo.initialLayout = self.initialLayout
        
        switch self.sharingMode {
        case .concurrent(let queueIndices):
            if queueIndices.count == 1 {
                fallthrough
            } else {
                createInfo.sharingMode = VK_SHARING_MODE_CONCURRENT
            
                queueIndices.withUnsafeBufferPointer { queueIndices in
                    createInfo.queueFamilyIndexCount = UInt32(queueIndices.count)
                    createInfo.pQueueFamilyIndices = queueIndices.baseAddress
                    withInfo(createInfo)
                }
            }
        case .exclusive:
            createInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE
            withInfo(createInfo)
        }
    }
}

extension VkExtent3D : Equatable {
    public static func == (lhs: VkExtent3D, rhs: VkExtent3D) -> Bool {
        return lhs.width == rhs.width && lhs.height == rhs.height && lhs.depth == rhs.depth
    }
}

extension VkFormat {
    public var isDepth : Bool {
        switch self {
        case VK_FORMAT_D16_UNORM , VK_FORMAT_D16_UNORM_S8_UINT,
             VK_FORMAT_D24_UNORM_S8_UINT, VK_FORMAT_D32_SFLOAT,
             VK_FORMAT_D32_SFLOAT_S8_UINT, VK_FORMAT_X8_D24_UNORM_PACK32:
            return true
        default:
            return false
        }
    }
    
    public var isStencil : Bool {
        switch self {
        case VK_FORMAT_S8_UINT, VK_FORMAT_D32_SFLOAT_S8_UINT,
             VK_FORMAT_D16_UNORM_S8_UINT, VK_FORMAT_D24_UNORM_S8_UINT:
            return true
        default:
            return false
        }
    }
    
    public var isDepthStencil : Bool {
        switch self {
        case VK_FORMAT_D16_UNORM_S8_UINT,
             VK_FORMAT_D24_UNORM_S8_UINT,
             VK_FORMAT_D32_SFLOAT_S8_UINT:
            return true
        default:
            return false
        }
    }
}

#endif // canImport(Vulkan)
