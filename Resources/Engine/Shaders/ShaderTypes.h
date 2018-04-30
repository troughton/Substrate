//
//  ShaderTypes.h
//  Interdimensional Llama
//
//  Created by Thomas Roughton on 16/12/17.
//  Copyright © 2017 troughton. All rights reserved.
//

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

typedef NS_ENUM(NSInteger, ScreenRenderTargetIndex)
{
    ScreenRenderTargetIndexDisplay,
    
    ScreenRenderTargetIndexLast
};

typedef NS_ENUM(NSInteger, HDRRenderTargetIndex)
{
    HDRRenderTargetIndexLightAccumulation,
    HDRRenderTargetIndexMotionVectors,
    HDRRenderTargetIndexGBuffer0,
    HDRRenderTargetIndexGBuffer1,
    HDRRenderTargetIndexGBuffer2,
    
    HDRRenderTargetIndexLast
};

typedef NS_ENUM(NSInteger, RenderTargetShadowIndex)
{
    RenderTargetShadowIndexLast
};

typedef NS_ENUM(NSInteger, CubeFaceIndex)
{
    CubeFaceIndexPositiveX,
    CubeFaceIndexNegativeX,
    CubeFaceIndexPositiveY,
    CubeFaceIndexNegativeY,
    CubeFaceIndexPositiveZ,
    CubeFaceIndexNegativeZ,
    
    CubeFaceIndexLast
};

#endif /* ShaderTypes_h */

