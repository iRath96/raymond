#pragma once

typedef struct {
    uint32_t vertexOffset;
    uint32_t faceOffset;
    
    float3 boundsMin;
    float3 boundsSize;
    
    float4x4 pointTransform;
    float3x3 normalTransform;
    
    RayFlags visibility;
} DEVICE_STRUCT(PerInstanceData);
