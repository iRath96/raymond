#pragma once

#include <bridge/common.hpp>

DEVICE_STRUCT(ShapeLight) {
    InstanceIndex instanceIndex;
    float emissiveArea;
    
#ifdef __METAL_VERSION__
    float pdf(thread const ShadingContext &shading) const device;
    LightSample sample(device Context &ctx, thread ShadingContext &shading, thread PrngState &prng) const device;
#endif
};
