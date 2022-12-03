#pragma once

#include <bridge/common.hpp>
#include "LightInfo.hpp"

DEVICE_STRUCT(SpotLight) {
    DEVICE_STRUCT(LightInfo) info;
    
    float3 location;
    float3 direction;
    float radius;
    float3 color;
    float spotSize;
    float spotBlend;
    
#ifdef __METAL_VERSION__
    LightSample sample(device Context &ctx, thread ShadingContext &shading, thread PrngState &prng) const device;
#endif
};
