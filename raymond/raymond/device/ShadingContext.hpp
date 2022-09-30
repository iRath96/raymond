#pragma once

#include "../bridge/common.hpp"
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
    RayFlags rayFlags;
    
    UberShader material;
};
