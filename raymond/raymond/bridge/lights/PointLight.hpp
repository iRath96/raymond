#pragma once

#include "../common.hpp"
#include "LightInfo.hpp"

DEVICE_STRUCT(PointLight) {
    DEVICE_STRUCT(LightInfo) info;
    
    float3 location;
    float radius;
    float3 color;

#ifdef __METAL_VERSION__
    LightSample sample(device Context &ctx, thread ShadingContext &shading, thread PrngState &prng) const device;
#endif
};
