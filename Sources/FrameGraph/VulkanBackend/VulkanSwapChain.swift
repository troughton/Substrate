//
//  VulkanSwapChain.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 10/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphUtilities
import FrameGraphCExtras

public class VulkanSwapChain : SwapChain {
    
    struct SwapChainSupportDetails {
        let capabilities : VkSurfaceCapabilitiesKHR
        let formats : [VkSurfaceFormatKHR]
        let presentModes : [VkPresentModeKHR]
        
        public init(physicalDevice: VkPhysicalDevice, surface: VkSurfaceKHR) {
            var capabilities = VkSurfaceCapabilitiesKHR()
            vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, surface, &capabilities)
            self.capabilities = capabilities
            
            var formatCount = 0 as UInt32
            vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, &formatCount, nil)
            
            var formats = [VkSurfaceFormatKHR](repeating: VkSurfaceFormatKHR(), count: Int(formatCount))
            if formatCount != 0 {
                vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, &formatCount, &formats)
            }
            self.formats = formats
            
            
            var presentModeCount = 0 as UInt32
            vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface, &presentModeCount, nil)
            
            var presentModes = [VkPresentModeKHR](repeating: VK_PRESENT_MODE_FIFO_KHR, count: Int(presentModeCount))
            if presentModeCount != 0 {
                vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface, &presentModeCount, &presentModes)
            }
            self.presentModes = presentModes
            
        }
    }
    
    public let device : VulkanDevice
    
    let surface : VkSurfaceKHR
    
    var surfaceFormat : VkSurfaceFormatKHR! = nil
    let presentQueue : VkQueue

    private var needsRecreateSwapChain = false
    
    private(set) var swapChain : VkSwapchainKHR? = nil
    private(set) var images : [VulkanImage] = []

    private var currentImageIndex : Int? = nil
    
    
    public var format: PixelFormat {
        return PixelFormat(self.surfaceFormat.format)
    }
    
    public init(device: VulkanDevice, surface: VkSurfaceKHR) {
        self.device = device
        self.surface = surface

        var presentQueue : VkQueue? = nil
        vkGetDeviceQueue(device.vkDevice, UInt32(device.physicalDevice.queueFamilyIndices.present), 0, &presentQueue)
        self.presentQueue = presentQueue!
    }

    private var currentDrawableSize = Size()
    
    public var pixelFormat: PixelFormat {
        if let surfaceFormat = self.surfaceFormat {
            return PixelFormat(surfaceFormat.format)
        } else {
            let swapChainSupport = SwapChainSupportDetails(physicalDevice: device.physicalDevice.vkDevice, surface: surface)
            self.surfaceFormat = VulkanSwapChain.chooseSwapSurfaceFormat(availableFormats: swapChainSupport.formats)
            return self.pixelFormat
        }
    }
    
    private func createSwapChain(drawableSize: Size) {
        let swapChainSupport = SwapChainSupportDetails(physicalDevice: device.physicalDevice.vkDevice, surface: surface)
        self.surfaceFormat = VulkanSwapChain.chooseSwapSurfaceFormat(availableFormats: swapChainSupport.formats)
        let presentMode = VulkanSwapChain.chooseSwapPresentMode(availableModes: swapChainSupport.presentModes)
        
        let extent = VulkanSwapChain.chooseSwapExtent(capabilities: swapChainSupport.capabilities, windowSize: drawableSize)
        self.currentDrawableSize = drawableSize

        var imageCount = swapChainSupport.capabilities.minImageCount + 1
        if swapChainSupport.capabilities.maxImageCount > 0 && imageCount < swapChainSupport.capabilities.maxImageCount {
            imageCount = swapChainSupport.capabilities.maxImageCount
        }
        
        var createInfo = VkSwapchainCreateInfoKHR()
        createInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR
        createInfo.surface = surface
        
        createInfo.minImageCount = imageCount
        createInfo.imageFormat = surfaceFormat.format
        createInfo.imageColorSpace = surfaceFormat.colorSpace
        createInfo.imageExtent = extent
        createInfo.imageArrayLayers = 1
        createInfo.imageUsage = VkImageUsageFlags(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT)
        
        createInfo.preTransform = swapChainSupport.capabilities.currentTransform
        createInfo.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR
        createInfo.presentMode = presentMode
        createInfo.clipped = true
        
        let queueIndices = device.physicalDevice.queueFamilyIndices
        let queueFamilyIndices = [ UInt32(queueIndices.graphics), UInt32(queueIndices.present) ]
        
        let sharingMode : VulkanSharingMode
        if queueIndices.graphics != queueIndices.present {
            sharingMode = .concurrent([.graphics, .present])
        } else {
            sharingMode = .exclusive
        }
        
        var swapChain : VkSwapchainKHR? = nil
        queueFamilyIndices.withUnsafeBufferPointer { queueFamilyIndices in
            if queueIndices.graphics != queueIndices.present {
                createInfo.imageSharingMode = VK_SHARING_MODE_CONCURRENT
                createInfo.queueFamilyIndexCount = 2
                createInfo.pQueueFamilyIndices = queueFamilyIndices.baseAddress
            } else {
                createInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE
            }
            
            if vkCreateSwapchainKHR(device.vkDevice, &createInfo, nil, &swapChain) != VK_SUCCESS {
                fatalError("Failed to create swap chain.")
            }
        }
        
        self.swapChain = swapChain!
        
        vkGetSwapchainImagesKHR(device.vkDevice, swapChain, &imageCount, nil)
        
        var images = [VkImage?](repeating: nil, count: Int(imageCount))
        vkGetSwapchainImagesKHR(device.vkDevice, swapChain, &imageCount, &images)
        print("Swapchain created with \(images.count) images.")
        
        self.images = images.lazy.compactMap { $0 }.enumerated().map { (i, image) in
            var descriptor = VulkanImageDescriptor()
            descriptor.imageType = VK_IMAGE_TYPE_2D
            descriptor.imageViewType = VK_IMAGE_VIEW_TYPE_2D
            descriptor.format = surfaceFormat.format
            descriptor.extent = VkExtent3D(width: extent.width, height: extent.height, depth: 1)
            descriptor.mipLevels = 1
            descriptor.arrayLayers = 1
            descriptor.samples = VK_SAMPLE_COUNT_1_BIT
            descriptor.tiling = VK_IMAGE_TILING_OPTIMAL
            descriptor.usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT
            descriptor.sharingMode = sharingMode
            descriptor.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED // as per spec.
            
            let image = VulkanImage(device: device, image: image, allocator: nil, allocation: nil, descriptor: descriptor)
            image.swapchainImageIndex = i
            return image
        }
    }
    
    private func cleanupSwapChain() {
        vkDeviceWaitIdle(self.device.vkDevice)
        
        vkDestroySwapchainKHR(self.device.vkDevice, swapChain, nil)
    }

    private func recreateSwapChain(drawableSize: Size) {
        self.cleanupSwapChain()
        self.createSwapChain(drawableSize: drawableSize)
    }
    
    func nextImage(descriptor: TextureDescriptor) -> (VulkanImage, VulkanContextWaitSemaphore) {
        if self.swapChain == nil {
            self.createSwapChain(drawableSize: descriptor.size)
        } else if descriptor.size != self.currentDrawableSize {
            print("Recreating the swap chain. Drawable size is \(descriptor.size)")
            self.recreateSwapChain(drawableSize: descriptor.size)
        }
        
        var imageIndex = 0 as UInt32
        let semaphore = self.device.semaphorePool.allocateSemaphore()
        let result = vkAcquireNextImageKHR(device.vkDevice, self.swapChain, UInt64.max, semaphore, nil, &imageIndex)
        
        if result == VK_ERROR_OUT_OF_DATE_KHR {
            self.recreateSwapChain(drawableSize: descriptor.size)
            self.device.semaphorePool.depositSemaphore(semaphore)
            return self.nextImage(descriptor: descriptor)
        } else if result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR {
            fatalError("Failed to acquire swap chain image.")
        }
        
        let image = self.images[Int(imageIndex)]
        self.currentImageIndex = Int(imageIndex)
        image.waitSemaphore = ResourceSemaphore(vkSemaphore: semaphore, stages: VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT)
        return image
    }
    
    func submit() {
        guard let imageIndex = self.currentImageIndex else {
            fatalError("VulkanSwapChain.submit() called without matching nextImage(). Aborting.")
        }
        defer { self.currentImageIndex = nil }
        let image = self.images[imageIndex]
        
        var presentInfo = VkPresentInfoKHR();
        presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;

        var semaphore = image.waitSemaphore?.vkSemaphore
        presentInfo.waitSemaphoreCount = semaphore == nil ? 0 : 1
        defer { image.waitSemaphore = nil }
        
        withUnsafePointer(to: &semaphore) { semaphorePtr in
            presentInfo.pWaitSemaphores = semaphorePtr
            
            var swapChain = self.swapChain as VkSwapchainKHR?
            presentInfo.swapchainCount = 1
            withUnsafePointer(to: &swapChain) { swapChainPtr in
                presentInfo.pSwapchains = swapChainPtr
                
                var imageIndex = UInt32(image.swapchainImageIndex!)
                
                withUnsafePointer(to: &imageIndex) { imageIndex in
                    presentInfo.pImageIndices = imageIndex
                    
                    let result = vkQueuePresentKHR(presentQueue, &presentInfo)
                    if result == VK_ERROR_OUT_OF_DATE_KHR /*|| result == VK_SUBOPTIMAL_KHR*/ {
                        self.cleanupSwapChain()
                        self.createSwapChain(drawableSize: self.currentDrawableSize)
                    } else if result != VK_SUCCESS {
                        fatalError("Failed to present swap chain image: \(result).")
                    }
                }
            }
            
        }
    }
    
    static func chooseSwapSurfaceFormat(availableFormats: [VkSurfaceFormatKHR]) -> VkSurfaceFormatKHR {
        if availableFormats.count == 1 && availableFormats[0].format == VK_FORMAT_UNDEFINED {
            return VkSurfaceFormatKHR(format: VK_FORMAT_B8G8R8A8_SRGB, colorSpace: VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
        }
        
        var bestFormat = availableFormats[0]
        
        for availableFormat in availableFormats {
            if availableFormat.format == VK_FORMAT_B8G8R8A8_SRGB && availableFormat.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR {
                return availableFormat
            }
            if availableFormat.format == VK_FORMAT_B8G8R8A8_UNORM && availableFormat.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR {
                bestFormat = availableFormat
            }
        }
        
        return bestFormat
    }
    
    static func chooseSwapPresentMode(availableModes: [VkPresentModeKHR]) -> VkPresentModeKHR {
        var bestMode = VK_PRESENT_MODE_FIFO_KHR
        
        for availablePresentMode in availableModes {
            if availablePresentMode == VK_PRESENT_MODE_MAILBOX_KHR {
                return availablePresentMode
            } else if availablePresentMode == VK_PRESENT_MODE_IMMEDIATE_KHR {
                bestMode = availablePresentMode
            }
        }
        
        return bestMode
    }
    
    static func chooseSwapExtent(capabilities: VkSurfaceCapabilitiesKHR, windowSize: Size) -> VkExtent2D {
        if capabilities.currentExtent.width != UInt32.max {
            return capabilities.currentExtent
        } else {
            
            var actualExtent = VkExtent2D(width: UInt32(windowSize.width), height: UInt32(windowSize.height))
            
            actualExtent.width = max(capabilities.minImageExtent.width, min(capabilities.maxImageExtent.width, actualExtent.width))
            actualExtent.height = max(capabilities.minImageExtent.height, min(capabilities.maxImageExtent.height, actualExtent.height))
            
            return actualExtent
        }
    }
    
    deinit {
        self.cleanupSwapChain()
    }
}

#endif // canImport(Vulkan)
