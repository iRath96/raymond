#pragma once

#include "common.hpp"

DEVICE_STRUCT(PrngState) {
    uint32_t seed;
    uint16_t index;

#ifdef __METAL_VERSION__
    PrngState(uint32_t a, uint32_t b);
    
    float sample();
    float2 sample2d();
    float3 sample3d();
    int sampleInt(int max);
    
    float sample() device;
    float2 sample2d() device;
    float3 sample3d() device;
    int sampleInt(int max) device;
#endif
};
