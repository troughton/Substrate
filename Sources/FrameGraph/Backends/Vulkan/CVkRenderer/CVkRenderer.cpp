#if defined(_WIN32)
#define VK_USE_PLATFORM_WIN32_KHR
#endif

#include "include/CVkRenderer.h"
#include <iostream>
#include <vector>

bool checkExtensionAvailability( const char *extension_name, const std::vector<VkExtensionProperties> &available_extensions ) {
    for( size_t i = 0; i < available_extensions.size(); ++i ) {
        if( strcmp( available_extensions[i].extensionName, extension_name ) == 0 ) {
            return true;
        }
    }
    return false;
}

const std::vector<const char*> validationLayers = {
    "VK_LAYER_LUNARG_standard_validation"
};

const std::vector<const char*> deviceExtensions = {
    VK_KHR_SWAPCHAIN_EXTENSION_NAME,
    VK_KHR_MAINTENANCE1_EXTENSION_NAME // to allow flipping the viewport vertically.
};

bool validationLayersSupported() {
    uint32_t layerCount;
    vkEnumerateInstanceLayerProperties(&layerCount, nullptr);

    std::vector<VkLayerProperties> availableLayers(layerCount);
    vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.data());

    for (const char* layerName : validationLayers) {
        bool layerFound = false;

        for (const auto& layerProperties : availableLayers) {
            if (strcmp(layerName, layerProperties.layerName) == 0) {
                layerFound = true;
                break;
            }
        }

        if (!layerFound) {
            return false;
       }
    }

    return true;
}

VKAPI_ATTR VkBool32 VKAPI_CALL VulkanDebugReportCallback(
    VkDebugReportFlagsEXT       flags,
    VkDebugReportObjectTypeEXT  objectType,
    uint64_t                    object,
    size_t                      location,
    int32_t                     messageCode,
    const char*                 pLayerPrefix,
    const char*                 pMessage,
    void*                       pUserData)
{
    // std::cerr << "Vulkan Error in " << object << " of type " << objectType << "." << std::endl;
    std::cerr << pMessage << std::endl;
    return VK_FALSE;
}

C_API VkInstance VkInstanceCreate() {
    uint32_t extensions_count = 0;
    if( (vkEnumerateInstanceExtensionProperties( nullptr, &extensions_count, nullptr ) != VK_SUCCESS) ||
       (extensions_count == 0) ) {
        std::cout << "Error occurred during instance extensions enumeration!" << std::endl;
        return nullptr;
    }
    
    std::vector<VkExtensionProperties> available_extensions( extensions_count );
    if( vkEnumerateInstanceExtensionProperties( nullptr, &extensions_count, &available_extensions[0] ) != VK_SUCCESS ) {
        std::cout << "Error occurred during instance extensions enumeration!" << std::endl;
        return nullptr;
    }
    
    std::vector<const char*> extensions = {
        VK_KHR_SURFACE_EXTENSION_NAME,
#if defined(VK_USE_PLATFORM_WIN32_KHR)
        VK_KHR_WIN32_SURFACE_EXTENSION_NAME,
#elif defined(VK_USE_PLATFORM_XCB_KHR)
        VK_KHR_XCB_SURFACE_EXTENSION_NAME,
#elif defined(VK_USE_PLATFORM_XLIB_KHR)
        VK_KHR_XLIB_SURFACE_EXTENSION_NAME,
#endif

#ifdef DEBUG
    VK_EXT_DEBUG_REPORT_EXTENSION_NAME,
#endif
    };
    
    for( size_t i = 0; i < extensions.size(); ++i ) {
        if( !checkExtensionAvailability( extensions[i], available_extensions ) ) {
            std::cout << "Could not find instance extension named \"" << extensions[i] << "\"!" << std::endl;
            return nullptr;
        }
    }
    
    VkApplicationInfo application_info = {
        VK_STRUCTURE_TYPE_APPLICATION_INFO,             // VkStructureType            sType
        nullptr,                                        // const void                *pNext
        "Interdimensional Llama",  // const char                *pApplicationName
        VK_MAKE_VERSION( 0, 0, 1 ),                     // uint32_t                   applicationVersion
        "Interdimensional Llama Engine",                // const char                *pEngineName
        VK_MAKE_VERSION( 0, 0, 1 ),                     // uint32_t                   engineVersion
        VK_MAKE_VERSION( 1, 0, 0 )                      // uint32_t                   apiVersion
    };
    
    VkInstanceCreateInfo instance_create_info = {
        VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,         // VkStructureType            sType
        nullptr,                                        // const void                *pNext
        0,                                              // VkInstanceCreateFlags      flags
        &application_info,                              // const VkApplicationInfo   *pApplicationInfo
        0,                                              // uint32_t                   enabledLayerCount
        nullptr,                                        // const char * const        *ppEnabledLayerNames
        static_cast<uint32_t>(extensions.size()),       // uint32_t                   enabledExtensionCount
        &extensions[0]                                  // const char * const        *ppEnabledExtensionNames
    };

#ifdef DEBUG
    if (!validationLayersSupported()) {
        std::cerr << "Vulkan validation layers are not supported." << std::endl;
    } else {
        instance_create_info.enabledLayerCount = static_cast<uint32_t>(validationLayers.size());
        instance_create_info.ppEnabledLayerNames = &validationLayers[0];
    }
#endif
    
    VkInstance instance = nullptr;
    if( vkCreateInstance( &instance_create_info, nullptr, &instance ) != VK_SUCCESS ) {
        std::cerr << "Could not create Vulkan instance!" << std::endl;
        return nullptr;
    }

#ifdef DEBUG
    /* Load VK_EXT_debug_report entry points in debug builds */
    PFN_vkCreateDebugReportCallbackEXT vkCreateDebugReportCallbackEXT =
        reinterpret_cast<PFN_vkCreateDebugReportCallbackEXT>
            (vkGetInstanceProcAddr(instance, "vkCreateDebugReportCallbackEXT"));
    PFN_vkDebugReportMessageEXT vkDebugReportMessageEXT =
        reinterpret_cast<PFN_vkDebugReportMessageEXT>
            (vkGetInstanceProcAddr(instance, "vkDebugReportMessageEXT"));
    PFN_vkDestroyDebugReportCallbackEXT vkDestroyDebugReportCallbackEXT =
        reinterpret_cast<PFN_vkDestroyDebugReportCallbackEXT>
            (vkGetInstanceProcAddr(instance, "vkDestroyDebugReportCallbackEXT"));

     /* Setup callback creation information */
    VkDebugReportCallbackCreateInfoEXT callbackCreateInfo;
    callbackCreateInfo.sType       = VK_STRUCTURE_TYPE_DEBUG_REPORT_CREATE_INFO_EXT;
    callbackCreateInfo.pNext       = nullptr;
    callbackCreateInfo.flags       = VK_DEBUG_REPORT_ERROR_BIT_EXT |
                                     VK_DEBUG_REPORT_WARNING_BIT_EXT |
                                     VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT; /* |
                                     VK_DEBUG_REPORT_DEBUG_BIT_EXT | 
                                     VK_DEBUG_REPORT_INFORMATION_BIT_EXT;*/
    callbackCreateInfo.pfnCallback = &VulkanDebugReportCallback;
    callbackCreateInfo.pUserData   = nullptr;

    /* Register the callback */
    VkDebugReportCallbackEXT callback;
    if ( vkCreateDebugReportCallbackEXT(instance, &callbackCreateInfo, nullptr, &callback) != VK_SUCCESS ) {
        std::cerr << "Could not register Vulkan debug report callback." << std::endl;
    }
#endif
    
    return instance;
}

C_API VkDevice VkDeviceCreate(VkPhysicalDevice physicalDevice, const uint32_t* queueFamilies, size_t queueFamilyCount) {
    
    std::vector<VkDeviceQueueCreateInfo> queueCreateInfos;
    
    float queuePriority = 1.0f;
    for (size_t i = 0; i < queueFamilyCount; i+= 1) {
        VkDeviceQueueCreateInfo queueCreateInfo = {};
        queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queueCreateInfo.queueFamilyIndex = queueFamilies[i];
        queueCreateInfo.queueCount = 1;
        queueCreateInfo.pQueuePriorities = &queuePriority;
        queueCreateInfos.push_back(queueCreateInfo);
    }
    
    VkPhysicalDeviceFeatures deviceFeatures = { };
    deviceFeatures.independentBlend = VK_TRUE;
    deviceFeatures.depthClamp = VK_TRUE;
    deviceFeatures.depthBiasClamp = VK_TRUE;

    VkDeviceCreateInfo createInfo = {};
    createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    
    createInfo.queueCreateInfoCount = static_cast<uint32_t>(queueCreateInfos.size());
    createInfo.pQueueCreateInfos = queueCreateInfos.data();
    
    createInfo.pEnabledFeatures = &deviceFeatures;
    
    createInfo.enabledExtensionCount = static_cast<uint32_t>(deviceExtensions.size());
    createInfo.ppEnabledExtensionNames = deviceExtensions.data();
    
    createInfo.enabledLayerCount = 0;
    
    VkDevice device = nullptr;
    VkResult createDeviceResult = vkCreateDevice(physicalDevice, &createInfo, nullptr, &device);
    if (createDeviceResult != VK_SUCCESS) {
        std::cerr << "Failed to create Vulkan logical device! Error: " << createDeviceResult << "." << std::endl;
        return nullptr;
    }
    
    return device;
    
}
