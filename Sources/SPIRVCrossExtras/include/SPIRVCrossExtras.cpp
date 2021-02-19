//
//  SPIRVCrossExtras.c
//  
//
//  Created by Thomas Roughton on 19/02/21.
//

#include "SPIRVCrossExtras.h"
#include <cstddef>
#include <unordered_set>

// This is incredibly brittle, but it's also only intended as a short-term fix; HLSL should gain support
// for 'invariant' in the near future (https://github.com/KhronosGroup/glslang/issues/1911).
struct ScratchMemoryAllocation
{
    virtual ~ScratchMemoryAllocation() = default;
};

struct spvc_set_s: ScratchMemoryAllocation {
    std::unordered_set<uint32_t> values;
};

spvc_result spvc_compiler_make_position_invariant(spvc_compiler compiler) {
    spvc_set activeSet = NULL;
    spvc_compiler_get_active_interface_variables(compiler, &activeSet);
    
    for (uint32_t varId : activeSet->values) {
        if (spvc_compiler_has_decoration(compiler, varId, SpvDecorationBuiltIn) &&
            spvc_compiler_get_decoration(compiler, varId, SpvDecorationBuiltIn) == SpvBuiltInPosition) {
            spvc_compiler_set_decoration(compiler, varId, SpvDecorationInvariant, 0);
        }
    }
    return SPVC_SUCCESS;
}
