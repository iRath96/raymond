#pragma once

#ifdef __METAL_VERSION__

using namespace metal;
#define DEVICE_STRUCT(name) name

#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
typedef packed_float3 MPSPackedFloat3;

#else

#include <simd/simd.h>
#import <Foundation/Foundation.h>
#define DEVICE_STRUCT(name) Device##name
typedef simd_float3 float3;
typedef simd_float3x3 float3x3;
typedef simd_float3x4 float3x4;
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

typedef NS_ENUM(NSInteger, ContextBufferIndex) {
    ContextBufferVertices        = 0,
    ContextBufferVertexIndices   = 1,
    ContextBufferNormals         = 2,
    ContextBufferTexcoords       = 3,
    ContextBufferPerInstanceData = 4,
    ContextBufferMaterials       = 5,
    ContextBufferLights          = 100,
    ContextBufferTextures        = 200,
};

typedef NS_ENUM(NSInteger, LightsBufferIndex) {
    LightsBufferTotalLightCount = 0,
    LightsBufferAreaLightCount  = 1,
    LightsBufferPointLightCount = 2,
    LightsBufferSunLightCount   = 3,
    LightsBufferSpotLightCount  = 4,
    LightsBufferWorldLight      = 5,
    LightsBufferAreaLight       = 20,
    LightsBufferPointLight      = 21,
    LightsBufferSunLight        = 22,
    LightsBufferSpotLight       = 23
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
    
    // scene buffers
    ShadingBufferUniforms        = 11,
    
    // awesome
    ShadingBufferFunctionTable   = 15,
    ShadingBufferContext         = 16
};

typedef NS_ENUM(NSInteger, ShadowBufferIndex) {
    ShadowBufferIntersections = 0,
    ShadowBufferShadowRays    = 1,
    ShadowBufferRayCount      = 2,
};

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
    uint32_t vertexOffset;
    uint32_t faceOffset;
    
    float3 boundsMin;
    float3 boundsSize;
    
    float4x4 pointTransform;
    float3x3 normalTransform;
    
    RayFlags visibility;
} PerInstanceData;

typedef NS_ENUM(NSInteger, SamplingMode) {
    SamplingModeBsdf,
    SamplingModeNee,
    SamplingModeMis
};

typedef struct {
    uint32_t frameIndex;
    float4x4 projectionMatrix;
    SamplingMode samplingMode;
} Uniforms;

typedef struct {
    uint32_t seed;
    uint16_t index;

#ifdef __METAL_VERSION__
    float sample();
    float2 sample2d();
    float3 sample3d();
    int sampleInt(int max);
    
    float sample() device;
    float2 sample2d() device;
    float3 sample3d() device;
    int sampleInt(int max) device;
#endif
} PRNGState;

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

typedef struct {
    float x, y, z;
} Vertex;

typedef uint32_t VertexIndex;
typedef uint32_t PrimitiveIndex;
typedef uint16_t MaterialIndex;

struct LightSample;
struct Context;
struct ThreadContext;

typedef struct {
    uint16_t shaderIndex;
    bool castsShadows;
    bool usesMIS;
} DEVICE_STRUCT(LightInfo);

typedef struct {
    DEVICE_STRUCT(LightInfo) info;
    
    float3x4 transform;
    float3 color;
    bool isCircular;
    
#ifdef __METAL_VERSION__
    LightSample sample(device Context &ctx, thread ThreadContext &tctx, thread PRNGState &prng) const device;
#endif
} DEVICE_STRUCT(AreaLight);

typedef struct {
    DEVICE_STRUCT(LightInfo) info;
    
    float3 location;
    float radius;
    float3 color;

#ifdef __METAL_VERSION__
    LightSample sample(device Context &ctx, thread ThreadContext &tctx, thread PRNGState &prng) const device;
#endif
} DEVICE_STRUCT(PointLight);

typedef struct {
    DEVICE_STRUCT(LightInfo) info;
    
    float3 direction;
    float cosAngle;
    float3 color;
    
#ifdef __METAL_VERSION__
    LightSample sample(device Context &ctx, thread ThreadContext &tctx, thread PRNGState &prng) const device;
#endif
} DEVICE_STRUCT(SunLight);

typedef struct {
    DEVICE_STRUCT(LightInfo) info;
    
    float3 location;
    float3 direction;
    float radius;
    float3 color;
    float spotSize;
    float spotBlend;
    
#ifdef __METAL_VERSION__
    LightSample sample(device Context &ctx, thread ThreadContext &tctx, thread PRNGState &prng) const device;
#endif
} DEVICE_STRUCT(SpotLight);
