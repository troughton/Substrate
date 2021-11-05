#if __has_include(<vulkan/vulkan.h>) || __has_include("/usr/local/include/vulkan/vulkan.h")

#include <cstdint>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

#define VMA_IMPLEMENTATION
#include "include/vk_mem_alloc.h"

#pragma clang diagnostic pop

#endif // __has_include(<vulkan/vulkan.h>)
