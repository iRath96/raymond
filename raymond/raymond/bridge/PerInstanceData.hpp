#pragma once

#include "common.hpp"
#include "Ray.hpp"

DEVICE_STRUCT(PerInstanceData) {
    uint32_t vertexOffset;
    uint32_t faceOffset;
    
    float3 boundsMin;
    float3 boundsSize;
    
    float4x4 pointTransform;
    float3x3 normalTransform;
    
    RayFlags visibility;
};
