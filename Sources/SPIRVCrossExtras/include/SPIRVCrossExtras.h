//
//  SPIRVCrossExtras.h
//  
//
//  Created by Thomas Roughton on 19/02/21.
//

#ifndef SPIRVCrossExtras_h
#define SPIRVCrossExtras_h

#include <spirv_cross_c.h>

#ifdef __cplusplus
extern "C" {
#endif

spvc_result spvc_compiler_make_position_invariant(spvc_compiler compiler);

#ifdef __cplusplus
}
#endif

#endif /* SPIRVCrossExtras_h */
