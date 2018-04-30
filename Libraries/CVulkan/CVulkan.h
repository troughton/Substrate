//
//  CVulkan.h
//  LlamaGame
//
//  Created by Thomas Roughton on 7/06/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

#ifndef CVulkan_h
#define CVulkan_h

#if defined(__APPLE__)
    #include "include/MoltenVK/mvk_vulkan.h"
    #include "include/MoltenVK/vk_mvk_moltenvk.h"
    #include "include/vulkan/vulkan.h"
    #include "include/vulkan/vk_platform.h"
#else
    #include <vulkan/vulkan.h>
    #include <vulkan/vk_platform.h>
#endif

#endif /* CVulkan_h */
