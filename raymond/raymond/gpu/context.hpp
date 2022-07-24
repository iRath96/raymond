#pragma once

#include "bsdf.hpp"
#include "ShaderTypes.h"

#include <metal_stdlib>
using namespace metal;

struct Material {
    float3 normal;
    
    float lobeProbabilities[4] = { 0, 0, 0, 0 };
    Diffuse diffuse;
    Specular specular;
    Transmission transmission;
    Clearcoat clearcoat;
    
    float alpha = 1;
    float3 alphaWeight = 1;
    
    float3 emission = 0;
    
    float weight = 1;
    float pdf = 1;
    
    float3 evaluate(float3 wo, float3 wi, thread float &pdf) {
        return float3(0);
    }
    
    BSDFSample sample(float3 rnd, float3 wo, float3 shNormal, float3 geoNormal, RayFlags previousFlags) {
        if (rnd.x < alpha) {
            rnd.x /= alpha;
        } else {
            BSDFSample sample;
            sample.weight = alphaWeight * weight;
            sample.wi = -wo;
            sample.pdf = 1e+8; /// @todo hack
            sample.flags = previousFlags; /// null scattering does not alter ray flags
            return sample;
        }
        
        float3x3 worldToShadingFrame = buildOrthonormalBasis(shNormal);
        
        const float woDotGeoN = dot(wo, geoNormal);
        wo = wo * worldToShadingFrame;
        const float woDotShN = wo.z;
        if (woDotShN * woDotGeoN < 0) {
            return BSDFSample::invalid();
        }
        
        BSDFSample sample;
        if (rnd.x < lobeProbabilities[0]) {
            sample = diffuse.sample(rnd.yz, wo);
            sample.weight *= 1 / lobeProbabilities[0];
            sample.pdf *= alpha * lobeProbabilities[0];
        } else if (rnd.x < (lobeProbabilities[0] + lobeProbabilities[1])) {
            sample = specular.sample(rnd.yz, wo);
            sample.weight *= 1 / lobeProbabilities[1];
            sample.pdf *= alpha * lobeProbabilities[1];
        } else if (rnd.x < (lobeProbabilities[0] + lobeProbabilities[1] + lobeProbabilities[2])) {
            sample = transmission.sample(rnd.yz, wo);
            sample.weight *= 1 / lobeProbabilities[2];
            sample.pdf *= alpha * lobeProbabilities[2];
        } else {
            sample = clearcoat.sample(rnd.yz, wo);
            sample.weight *= 1 / lobeProbabilities[3];
            sample.pdf *= alpha * lobeProbabilities[3];
        }
        
        const float wiDotShN = sample.wi.z;
        sample.wi = sample.wi * transpose(worldToShadingFrame);
        sample.pdf *= pdf;
        sample.weight *= weight;
        const float wiDotGeoN = dot(sample.wi, geoNormal);
        if (wiDotShN * wiDotGeoN < 0) {
            return BSDFSample::invalid();
        }
        
        return sample;
    }
};

struct ThreadContext {
    float3 uv;
    float3 position;
    float3 generated;
    float3 object;
    float3 normal;
    float3 trueNormal;
    float3 tu, tv;
    float3 rnd;
    float3 wo;
    RayFlags rayFlags;
    
    Material material;
};

#ifndef JIT_COMPILED
#define NUMBER_OF_TEXTURES 1
#define USE_FUNCTION_TABLE
#endif

struct Context {
    array<texture2d<float>, NUMBER_OF_TEXTURES> textures [[ id(0) ]];
};
