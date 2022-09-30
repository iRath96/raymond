#pragma once

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

typedef struct {
    MPSPackedFloat3 origin;
    float minDistance;
    MPSPackedFloat3 direction;
    float maxDistance;
    
    PRNGState prng;
    simd_float3 weight;
    uint16_t x, y;
    RayFlags flags;
    float bsdfPdf;
} DEVICE_STRUCT(Ray);

typedef struct {
    MPSPackedFloat3 origin;
    float minDistance;
    MPSPackedFloat3 direction;
    float maxDistance;
    
    simd_float3 weight;
    uint16_t x, y;
} DEVICE_STRUCT(ShadowRay);

typedef struct {
    float distance;
    unsigned int primitiveIndex;
    unsigned int instanceIndex;
    vector_float2 coordinates;
} DEVICE_STRUCT(Intersection);
