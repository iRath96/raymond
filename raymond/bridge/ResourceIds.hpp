#pragma once

#include "common.hpp"

typedef NS_ENUM(NSInteger, GeneratorBufferIndex) {
    GeneratorBufferRays     = 0,
    GeneratorBufferRayCount = 1,
    GeneratorBufferUniforms = 2,
    GeneratorBufferContext  = 3,
    GeneratorBufferLens     = 4,
    GeneratorBufferAccelerationStructure = 5,
    GeneratorBufferIntersections = 6,
};

typedef NS_ENUM(NSInteger, ContextBufferIndex) {
    ContextBufferVertices        = 0,
    ContextBufferVertexIndices   = 1,
    ContextBufferNormals         = 2,
    ContextBufferTexcoords       = 3,
    ContextBufferPerInstanceData = 4,
    ContextBufferMaterials       = 5,
    ContextBufferCamera          = 100,
    ContextBufferLights          = 200,
    ContextBufferTextures        = 300,
};

typedef NS_ENUM(NSInteger, LightsBufferIndex) {
    LightsBufferTotalLightCount = 0,
    LightsBufferAreaLightCount  = 1,
    LightsBufferPointLightCount = 2,
    LightsBufferSunLightCount   = 3,
    LightsBufferSpotLightCount  = 4,
    LightsBufferShapeLightCount = 5,
    LightsBufferLightFaces      = 10,
    LightsBufferWorldLight      = 11,
    LightsBufferAreaLight       = 20,
    LightsBufferPointLight      = 21,
    LightsBufferSunLight        = 22,
    LightsBufferSpotLight       = 23,
    LightsBufferShapeLight      = 24
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
    ShadingBufferUniforms        = 7,
    ShadingBufferContext         = 8
};

typedef NS_ENUM(NSInteger, ShadowBufferIndex) {
    ShadowBufferIntersections = 0,
    ShadowBufferShadowRays    = 1,
    ShadowBufferRayCount      = 2,
};
