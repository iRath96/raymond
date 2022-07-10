#pragma once

#ifdef __METAL_VERSION__
using namespace metal;

#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
typedef packed_float3 MPSPackedFloat3;
#else
#include <simd/simd.h>
#import <Foundation/Foundation.h>
typedef simd_float3x3 float3x3;
typedef simd_float4x4 float4x4;
typedef __fp16 half;
typedef __attribute__((__ext_vector_type__(3))) half half3;

typedef struct _MPSPackedFloat3 {
    union {
        struct {
            float x;
            float y;
            float z;
        };
        float elements[3];
    };
} MPSPackedFloat3;
#endif

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
    
    // awesome
    ShadingBufferFunctionTable   = 15,
    ShadingBufferContext         = 16
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
    
    float4x4 pointTransform;
    float3x3 normalTransform;
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
    MPSPackedFloat3 origin;
    float minDistance;
    MPSPackedFloat3 direction;
    float maxDistance;
    
    PRNGState prng;
    simd_float3 weight;
    uint16_t x, y;
    float bsdfPdf;
} Ray;

typedef struct {
    MPSPackedFloat3 origin;
    float minDistance;
    MPSPackedFloat3 direction;
    float maxDistance;
    
    simd_float3 weight;
    uint16_t x, y;
} ShadowRay;

typedef struct {
    float distance;
    unsigned int primitiveIndex;
    unsigned int instanceIndex;
    vector_float2 coordinates;
} Intersection;

typedef struct {
    float x, y, z;
} Vertex;

typedef uint32_t VertexIndex;
typedef uint32_t PrimitiveIndex;
typedef uint32_t MaterialIndex;
