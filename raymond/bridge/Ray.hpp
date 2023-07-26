#pragma once

#include "common.hpp"
#include "PrngState.hpp"

typedef NS_ENUM(uint8_t, RayFlags) {
    RayFlagsCamera       = 1<<0,
    RayFlagsReflection   = 1<<1,
    RayFlagsTransmission = 1<<2,
    RayFlagsShadow       = 1<<3,
    RayFlagsVolume       = 1<<4,
    RayFlagsDiffuse      = 1<<5,
    RayFlagsGlossy       = 1<<6,
    RayFlagsSingular     = 1<<7
};

DEVICE_STRUCT(Ray) {
    MPSPackedFloat3 origin;
    float minDistance;
    MPSPackedFloat3 direction;
    float maxDistance;
    
    DEVICE_STRUCT(PrngState) prng;
    simd_float3 weight;
    uint16_t x, y;
    uint16_t depth;
    RayFlags flags;
    float bsdfPdf;
};

DEVICE_STRUCT(ShadowRay) {
    MPSPackedFloat3 origin;
    float minDistance;
    MPSPackedFloat3 direction;
    float maxDistance;
    
    simd_float3 weight;
    uint16_t x, y;
};

DEVICE_STRUCT(Intersection) {
    float distance;
    unsigned int primitiveIndex;
    unsigned int instanceIndex;
    vector_float2 coordinates;
};
