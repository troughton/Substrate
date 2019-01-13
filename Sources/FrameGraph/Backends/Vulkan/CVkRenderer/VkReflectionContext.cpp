//
//  VkReflectionContext.c
//  CVkRenderer
//
//  Created by Thomas Roughton on 12/01/18.
//

#include <algorithm>
#include <iostream>
#include <vector>

#include "include/VkReflectionContext.h"

#include "../SPIRV-Cross/spirv_cross.hpp"

struct VkReflectionContext_T {
    VkReflectionContext_T(const uint32_t* code, size_t wordCount) : compiler(code, wordCount) {
        
    }
    
    spirv_cross::Compiler compiler;
};

C_API VkReflectionContext VkReflectionContextCreate(const uint32_t* code, size_t wordCount) {
    VkReflectionContext context = new VkReflectionContext_T(code, wordCount);
    return context;
}

C_API void VkReflectionContextDestroy(const VkReflectionContext context) {
    delete context;
}

C_API void VkReflectionContextEnumerateEntryPoints(const VkReflectionContext context, void (^withEntryPoint)(const char* name)) {
     for (std::string& entryPoint : context->compiler.get_entry_points()) {
         withEntryPoint(entryPoint.c_str());
    }
}

C_API void VkReflectionContextSetEntryPoint(const VkReflectionContext context, const char* entryPoint) {
    context->compiler.set_entry_point(std::string(entryPoint));
}

C_API void VkReflectionContextRenameEntryPoint(const VkReflectionContext context, const char* fromName, const char* toName) {
    context->compiler.rename_entry_point(std::string(fromName), std::string(toName));
}


C_API void VkReflectionContextSetMainEntryPointName(const VkReflectionContext context, const char* newName) {
    const std::vector<std::string> entryPoints = context->compiler.get_entry_points();
    if (std::find(entryPoints.begin(), entryPoints.end(), "main") != entryPoints.end()) {
        context->compiler.rename_entry_point("main", std::string(newName));
    }
}

inline BindingIndex BindingIndexMake(const spirv_cross::Compiler& compiler, unsigned resourceId) {
    BindingIndex bindingIndex;
    bindingIndex.set = compiler.get_decoration(resourceId, spv::DecorationDescriptorSet);
    bindingIndex.binding = compiler.get_decoration(resourceId, spv::DecorationBinding);
    return bindingIndex;
}

inline BindingRange BufferBindingRange(std::vector<spirv_cross::BufferRange> bufferRanges) {
    size_t start = SIZE_MAX;
    size_t end = 0;
    for (auto& range : bufferRanges) {
        start = std::min(start, range.offset);
        end = std::max(end, range.offset + range.range);
    }
    return { static_cast<uint32_t>(start), static_cast<uint32_t>(end - start) };
}

C_API void VkReflectionContextEnumerateResources(const VkReflectionContext context, void (^withResourceInfo)(ShaderResourceType resourceType, BindingIndex index, BindingRange bindingRange, const char* name, AccessQualifier accessQualifier)) {
    const spirv_cross::ShaderResources resources = context->compiler.get_shader_resources(context->compiler.get_active_interface_variables());
    
    for (const spirv_cross::Resource& uniformBuffer : resources.uniform_buffers) {
        
        const std::string &name = context->compiler.get_name(uniformBuffer.id);
        withResourceInfo(ShaderResourceTypeUniformBuffer, BindingIndexMake(context->compiler, uniformBuffer.id), BufferBindingRange(context->compiler.get_active_buffer_ranges(uniformBuffer.id)), name.c_str(), AccessQualifierReadOnly);
    }
    
    for (const spirv_cross::Resource& storageBuffer : resources.storage_buffers) {
        bool isReadOnly = context->compiler.get_member_decoration(storageBuffer.base_type_id, 0, spv::DecorationNonWritable);
        bool isWriteOnly = context->compiler.get_member_decoration(storageBuffer.base_type_id, 0, spv::DecorationNonReadable);

        AccessQualifier access = AccessQualifierReadWrite;
        if (isReadOnly) {
            access = AccessQualifierReadOnly;
        } else if (isWriteOnly) {
            access = AccessQualifierWriteOnly;
        }

        const std::string &name = context->compiler.get_name(storageBuffer.id);

        withResourceInfo(ShaderResourceTypeStorageBuffer, BindingIndexMake(context->compiler, storageBuffer.id), BufferBindingRange(context->compiler.get_active_buffer_ranges(storageBuffer.id)), name.c_str(), access);
    }
    
    for (const spirv_cross::Resource& subpassInput : resources.subpass_inputs) {
        withResourceInfo(ShaderResourceTypeSubpassInput, BindingIndexMake(context->compiler, subpassInput.id), { 0, 0 }, subpassInput.name.c_str(), AccessQualifierReadOnly);
    }
    
    for (const spirv_cross::Resource& storageImage : resources.storage_images) {
        spv::AccessQualifier spvAccess = context->compiler.get_type_from_variable(storageImage.id).image.access;
        AccessQualifier access = AccessQualifierReadWrite;
        if (spvAccess == spv::AccessQualifierReadOnly) {
            access = AccessQualifierReadOnly;
        } else if (spvAccess == spv::AccessQualifierWriteOnly) {
            access = AccessQualifierWriteOnly;
        }

        withResourceInfo(ShaderResourceTypeStorageImage, BindingIndexMake(context->compiler, storageImage.id), { 0, 0 }, storageImage.name.c_str(), access);
    }
    
    for (const spirv_cross::Resource& sampledImage : resources.separate_images) {
        withResourceInfo(ShaderResourceTypeSampledImage, BindingIndexMake(context->compiler, sampledImage.id), { 0, 0 }, sampledImage.name.c_str(), AccessQualifierReadOnly);
    }
    
    for (const spirv_cross::Resource& sampler : resources.separate_samplers) {
        withResourceInfo(ShaderResourceTypeSampler, BindingIndexMake(context->compiler, sampler.id), { 0, 0 }, sampler.name.c_str(), AccessQualifierNone);
    }

    for (const spirv_cross::Resource& pushConstantBuffer : resources.push_constant_buffers) {
        std::vector<spirv_cross::BufferRange> activeRanges = context->compiler.get_active_buffer_ranges(pushConstantBuffer.id);
        for (const spirv_cross::BufferRange &range : activeRanges) {
            const std::string& name = context->compiler.get_member_name(pushConstantBuffer.base_type_id, range.index);
            withResourceInfo(ShaderResourceTypePushConstantBuffer,
                             { BindingIndexSetPushConstant, static_cast<uint32_t>(range.offset) },
                             { static_cast<uint32_t>(range.offset), static_cast<uint32_t>(range.range) },
                             name.c_str(), AccessQualifierReadOnly);
        }
    }
    
    // FIXME: We need to distinguish between texel- and non-texel variants of uniform and storage buffers.
    // Images also provide the access qualifier directly via the reflection API.
}

C_API size_t VkReflectionContextEnumerateSpecialisationConstants(const VkReflectionContext context, void (^withConstantInfo)(size_t index, uint32_t constantIndex, const char* constantName)) {
    auto constants = context->compiler.get_specialization_constants();
    
    if (withConstantInfo == nullptr) {
        return constants.size();
    }
    
    size_t i = 0;
    for (spirv_cross::SpecializationConstant& constant : constants) {
        std::string name = context->compiler.get_name(constant.id);
        withConstantInfo(i, constant.constant_id, name.c_str());
        i += 1;
    }
    
    return constants.size();
}
