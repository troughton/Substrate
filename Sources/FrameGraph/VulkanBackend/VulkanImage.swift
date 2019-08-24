//
//  VulkanImage.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 6/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras

class VulkanImage {
    public let device : VulkanDevice
    
    let vkImage : VkImage
    let allocator : VmaAllocator?
    let allocation : VmaAllocation?
    let descriptor : VulkanImageDescriptor
    var layout : VkImageLayout
    
    var waitSemaphore : ResourceSemaphore? = nil
    
    var swapchainImageIndex : Int? = nil
    
    private var _defaultView : Unmanaged<VulkanImageView>! = nil
    
    init(device: VulkanDevice, image: VkImage, allocator: VmaAllocator?, allocation: VmaAllocation?, descriptor: VulkanImageDescriptor) {
        self.device = device
        self.vkImage = image
        self.allocator = allocator
        self.allocation = allocation
        self.descriptor = descriptor
        self.layout = descriptor.initialLayout
        
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
            self._defaultView = Unmanaged.passRetained(VulkanImageView(image: self, vkView: imageView!))
        }
    }
    
    deinit {
        _defaultView.release()
        
        if let allocator = self.allocator, let allocation = self.allocation {
            vmaDestroyImage(allocator, self.vkImage, allocation)
        } else {
            vkDestroyImage(self.device.vkDevice, self.vkImage, nil)
        }
    }
    
    var defaultImageView : VulkanImageView {
        return _defaultView.takeUnretainedValue()
    }
    
    func matches(descriptor: VulkanImageDescriptor) -> Bool {
        return self.descriptor.matches(descriptor: descriptor)
    }
    
    func viewForAttachment(descriptor: RenderTargetAttachmentDescriptor) -> VulkanImageView {

        if self.descriptor.imageViewType == VK_IMAGE_VIEW_TYPE_2D, descriptor.level == 0 {
            return self.defaultImageView
        }

        var createInfo = VkImageViewCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
        
        createInfo.image = self.vkImage
        createInfo.viewType = VK_IMAGE_VIEW_TYPE_2D
        createInfo.format = self.descriptor.format
        
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
        
        createInfo.subresourceRange = subresourceRange
        
        var imageView : VkImageView? = nil
        vkCreateImageView(self.device.vkDevice, &createInfo, nil, &imageView)
        return VulkanImageView(image: self, vkView: imageView!)
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
    
    public init() {
        
    }
    
    public init(_ descriptor: TextureDescriptor, usage: VkImageUsageFlagBits, sharingMode: VulkanSharingMode, initialLayout: VkImageLayout) {
        assert(!usage.isEmpty, "Usage for texture with descriptor \(descriptor) must not be empty.")
        
        self.imageType = VkImageType(descriptor.textureType)
        self.imageViewType = VkImageViewType(descriptor.textureType)
        self.format = VkFormat(pixelFormat: descriptor.pixelFormat)
        self.extent = VkExtent3D(width: UInt32(descriptor.width), height: UInt32(descriptor.height), depth: UInt32(descriptor.depth))
        self.mipLevels = UInt32(descriptor.mipmapLevelCount)
        self.arrayLayers = UInt32(descriptor.arrayLength)
        self.samples = VK_SAMPLE_COUNT_1_BIT
        self.tiling = descriptor.storageMode == .private ? VK_IMAGE_TILING_OPTIMAL : VK_IMAGE_TILING_LINEAR
        self.usage = usage
        self.sharingMode = sharingMode
        self.initialLayout = initialLayout

        if .typeCube == descriptor.textureType || .typeCubeArray == descriptor.textureType {
            self.flags = .cubeCompatible
            self.arrayLayers *= 6
        } else if .type2DArray == descriptor.textureType {
            self.flags = VK_IMAGE_CREATE_2D_ARRAY_COMPATIBLE_BIT_KHR
        } else {
            self.flags = []
        }
    }
    
    public var allAspects : [VkImageAspectFlags] {
        return [VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT)] // FIXME: wrong for depth-stencil. Affects buffer -> image copies
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
            self.sharingMode ~= descriptor.sharingMode
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
        case .concurrent(let queueFamily):
        
            let queueIndices = device.physicalDevice.queueFamilyIndices(for: queueFamily)
            
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
