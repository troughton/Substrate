#pragma once

#if __has_include(<vulkan/vulkan.h>)
#include <vulkan/vulkan.h>
#include <vulkan/vk_platform.h>

#if __has_include(<X11/Xlib.h>)
#include <X11/Xlib.h>
#include <vulkan/vulkan_xlib.h>
#endif

#else
#include "/usr/local/include/vulkan/vulkan.h"
#endif
