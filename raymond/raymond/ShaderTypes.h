#pragma once

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#include <simd/simd.h>
#import <Foundation/Foundation.h>
typedef simd_float4x4 float4x4;
typedef __fp16 half;
/*typedef struct {
    half x;
    half y;
    half z;
} half3;*/
typedef __attribute__((__ext_vector_type__(3))) half half3;
#endif

#include <MetalPerformanceShaders/MetalPerformanceShaders.h>

typedef NS_ENUM(NSInteger, GeneratorBufferIndex) {
    GeneratorBufferRays     = 0,
    GeneratorBufferRayCount = 1,
    GeneratorBufferUniforms = 2,
};

typedef NS_ENUM(NSInteger, ShadingBufferIndex) {
    // ray buffers
    ShadingBufferIntersections   = 0,
    ShadingBufferRays            = 1,
    ShadingBufferNextRays        = 2,
    ShadingBufferShadowRays      = 3,
    
    // ray counters
    ShadingBufferCurrentRayCount = 4,
    ShadingBufferNextRayCount    = 5,
    ShadingBufferShadowRayCount  = 6,
    
    // geometry buffers
    ShadingBufferVertices        = 7,
    ShadingBufferVertexIndices   = 8,
    ShadingBufferNormals         = 9,
    ShadingBufferTexcoords       = 10,
    
    // scene buffers
    ShadingBufferUniforms        = 11,
    ShadingBufferPerInstanceData = 12,
    ShadingBufferMaterials       = 13,
    ShadingBufferLightSources    = 14,
};

typedef NS_ENUM(NSInteger, ShadowBufferIndex) {
    ShadowBufferIntersections = 0,
    ShadowBufferShadowRays    = 1,
    ShadowBufferRayCount      = 2,
};

typedef NS_ENUM(uint8_t, ImportanceSampling) {
    ImportanceSamplingBSDF = 0,
    ImportanceSamplingNEE  = 1,
    ImportanceSamplingMIS  = 2,
};

typedef struct {
    uint32_t vertexOffset;
    uint32_t faceOffset;
} PerInstanceData;

typedef struct {
    uint32_t frameIndex;
    float4x4 projectionMatrix;
} Uniforms;

typedef struct {
    uint32_t seed;
    uint16_t index;
} PRNGState;

typedef struct {
    MPSRayOriginMinDistanceDirectionMaxDistance base;
    
    PRNGState prng;
    simd_float3 weight;
    uint16_t x, y;
    float bsdfPdf;
} Ray;

typedef struct {
    MPSRayOriginMinDistanceDirectionMaxDistance base;
    simd_float3 weight;
    uint16_t x, y;
} ShadowRay;

typedef MPSIntersectionDistancePrimitiveIndexInstanceIndexCoordinates Intersection;

typedef struct {
    float x, y, z;
} Vertex;

typedef uint32_t VertexIndex;
typedef uint32_t PrimitiveIndex;
typedef uint32_t MaterialIndex;
