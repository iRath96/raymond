#pragma once

#include "../common.hpp"
#include "LightInfo.hpp"

DEVICE_STRUCT(SunLight) {
    DEVICE_STRUCT(LightInfo) info;
    
    float3 direction;
    float cosAngle;
    float3 color;
    
#ifdef __METAL_VERSION__
    LightSample sample(device Context &ctx, thread ShadingContext &shading, thread PrngState &prng) const device;
#endif
};
