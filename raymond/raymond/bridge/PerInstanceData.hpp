#pragma once

#include "common.hpp"
#include "Ray.hpp"

DEVICE_STRUCT(PerInstanceData) {
    VertexIndex vertexOffset;
    FaceIndex faceOffset;
    FaceIndex lightFaceOffset;
    FaceIndex lightFaceCount;
    LightIndex lightIndex;
    
    float3 boundsMin;
    float3 boundsSize;
    
    float4x4 pointTransform;
    float3x3 normalTransform;
    
    RayFlags visibility;
};
