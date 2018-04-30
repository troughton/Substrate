
#include "CVkRendererShared.h"
#include "VkReflectionContext.h"
#include "vk_mem_alloc.h"

C_API VkInstance VkInstanceCreate();
C_API VkDevice VkDeviceCreate(VkPhysicalDevice device, const uint32_t* queueFamilies, size_t queueFamilyCount);
