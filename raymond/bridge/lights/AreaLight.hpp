#pragma once

#include <bridge/common.hpp>
#include "LightInfo.hpp"

DEVICE_STRUCT(AreaLight) {
    DEVICE_STRUCT(LightInfo) info;
    
    float3x4 transform;
    float3 color;
    bool isCircular;
    
#ifdef __METAL_VERSION__
    LightSample sample(device Context &, thread ShadingContext &, thread PrngState &) const device;
#endif
};
