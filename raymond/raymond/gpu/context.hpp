#pragma once

#include "bsdf.hpp"

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
    
    float3 evaluate(float3 wo, float3 wi, thread float &pdf) {
        return float3(0);
    }
    
    BSDFSample sample(float3 rnd, float3 wo) {
        if (rnd.x < alpha) {
            rnd.x /= alpha;
        } else {
            BSDFSample sample;
            sample.weight = alphaWeight;
            sample.wi = -wo;
            sample.pdf = 1e+8; // @todo hack
            return sample;
        }
        
        if (rnd.x < lobeProbabilities[0]) {
            BSDFSample sample = diffuse.sample(rnd.yz, wo);
            sample.weight *= 1 / lobeProbabilities[0];
            sample.pdf *= alpha * lobeProbabilities[0];
            return sample;
        } else if (rnd.x < (lobeProbabilities[0] + lobeProbabilities[1])) {
            BSDFSample sample = specular.sample(rnd.yz, wo);
            sample.weight *= 1 / lobeProbabilities[1];
            sample.pdf *= alpha * lobeProbabilities[1];
            return sample;
        } else if (rnd.x < (lobeProbabilities[0] + lobeProbabilities[1] + lobeProbabilities[2])) {
            BSDFSample sample = transmission.sample(rnd.yz, wo);
            sample.weight *= 1 / lobeProbabilities[2];
            sample.pdf *= alpha * lobeProbabilities[2];
            return sample;
        } else {
            BSDFSample sample = clearcoat.sample(rnd.yz, wo);
            sample.weight *= 1 / lobeProbabilities[3];
            sample.pdf *= alpha * lobeProbabilities[3];
            return sample;
        }
    }
};

struct ThreadContext {
    float2 uv;
    float3 normal;
    float3 tu, tv;
    float3 rnd;
    float3 wo;
    
    bool isCameraRay;
    
    Material material;
};

#ifndef JIT_COMPILED
#define NUMBER_OF_TEXTURES 1
#endif

struct Context {
    array<texture2d<float>, NUMBER_OF_TEXTURES> textures [[ id(0) ]];
};
