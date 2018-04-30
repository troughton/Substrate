//
//  VkReflectionContext.h
//  CVkRenderer
//
//  Created by Thomas Roughton on 12/01/18.
//

#ifndef VkReflectionContext_h
#define VkReflectionContext_h

#include <stdio.h>
#include <stdint.h>
#include "CVkRendererShared.h"

typedef struct VkReflectionContext_T *VkReflectionContext;

C_API VkReflectionContext VkReflectionContextCreate(const uint32_t* code, size_t wordCount);
C_API void VkReflectionContextDestroy(const VkReflectionContext context);

C_API void VkReflectionContextSetEntryPoint(const VkReflectionContext context, const char* entryPoint);

typedef NS_ENUM(uint32_t, ShaderResourceType) {
    /// A single struct of read-only data with the 'constant' storage class.
    ShaderResourceTypeUniformBuffer,
    /// A tightly packed array of read-only data with the 'constant' storage class.
    ShaderResourceTypeUniformTexelBuffer,
    /// A single struct of atomic read-write data with the 'device' storage class.
    ShaderResourceTypeStorageBuffer,
    /// A tightly packed array of atomic read-write data with the 'device' storage class.
    ShaderResourceTypeStorageTexelBuffer,
    /// An image view that can be used for unfiltered pixel-local load operations.
    ShaderResourceTypeSubpassInput,
    /// An image that can be loaded from, stored to, and used for atomic operations.
    ShaderResourceTypeStorageImage,
    /// An image that can be read or sampled from with a sampler
    ShaderResourceTypeSampledImage,
    /// A variant of uniform buffers that's fast-pathed for updates (e.g. setBytes).
    ShaderResourceTypePushConstantBuffer,
    /// A sampler that can be used with multiple sampled images.
    ShaderResourceTypeSampler
};

typedef NS_ENUM(uint32_t, AccessQualifier) {
    AccessQualifierNone,
    AccessQualifierReadOnly,
    AccessQualifierReadWrite,
    AccessQualifierWriteOnly
};

static const uint16_t BindingIndexSetPushConstant = UINT16_MAX;

typedef struct BindingIndex {
    uint32_t set;
    uint32_t binding;
} BindingIndex;

typedef struct BindingRange {
    uint32_t offset;
    uint32_t size;
} BindingRange;


C_API void VkReflectionContextSetMainEntryPointName(const VkReflectionContext context, const char* newName);

C_API void VkReflectionContextRenameEntryPoint(const VkReflectionContext context, const char* oldName, const char* newName);

C_API void VkReflectionContextEnumerateEntryPoints(const VkReflectionContext context, void (^withEntryPoint)(const char* name));

C_API void VkReflectionContextEnumerateResources(const VkReflectionContext context, void (^withResourceInfo)(ShaderResourceType resourceType, BindingIndex index, BindingRange bindingRange, const char* name, AccessQualifier accessQualifier));

C_API size_t VkReflectionContextEnumerateSpecialisationConstants(const VkReflectionContext context, void (^withConstantInfo)(size_t index, uint32_t constantIndex, const char* constantName));

#endif /* VkReflectionContext_h */
