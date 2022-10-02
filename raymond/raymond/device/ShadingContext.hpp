#pragma once

#include "../bridge/common.hpp"
#include "../bridge/PerInstanceData.hpp"
#include "bsdf/UberShader.hpp"

struct ShadingContext {
    float3 uv;
    float3 position;
    float3 generated;
    float3 object;
    float3 normal;
    float3 trueNormal;
    float3 tu, tv;
    float3 rnd;
    float3 wo; // pointing away from the hitpoint
    float distance;
    RayFlags rayFlags;
    
    UberShader material;
    
    void build(
        device const Context &ctx,
        device const PerInstanceData &instance,
        Intersection isect,
        thread MaterialIndex &shaderIndex
    );
    
    float geometryTerm() const {
        return abs(dot(wo, trueNormal)) / square(distance);
    }
};
