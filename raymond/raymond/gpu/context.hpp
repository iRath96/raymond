#pragma once

#include "bsdf.hpp"
#include "warp.hpp"
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
    
    float3 evaluate(float3 wo, float3 wi, float3 shNormal, float3 geoNormal, thread float &pdf) {
        /// @todo alpha? pdf and weight fields? mix/add shaders?
        pdf = 0;
        
        float3x3 worldToShadingFrame = buildOrthonormalBasis(shNormal);
        
        const float woDotGeoN = dot(wo, geoNormal);
        wo = wo * worldToShadingFrame;
        const float woDotShN = wo.z;
        if (woDotShN * woDotGeoN < 0) {
            return 0;
        }
        
        const float wiDotGeoN = dot(wi, geoNormal);
        wi = wi * worldToShadingFrame;
        const float wiDotShN = wi.z;
        if (wiDotShN * wiDotGeoN < 0) {
            return 0;
        }
        
        float3 value = 0;
        float lobePdf;
        if (lobeProbabilities[0] > 0) {
            value += diffuse.evaluate(wo, wi, lobePdf); pdf += lobeProbabilities[0] * lobePdf;
        }
        if (lobeProbabilities[1] > 0) {
            value += specular.evaluate(wo, wi, lobePdf); pdf += lobeProbabilities[1] * lobePdf;
        }
        if (lobeProbabilities[2] > 0) {
            value += transmission.evaluate(wo, wi, lobePdf); pdf += lobeProbabilities[2] * lobePdf;
        }
        if (lobeProbabilities[3] > 0) {
            value += clearcoat.evaluate(wo, wi, lobePdf); pdf += lobeProbabilities[3] * lobePdf;
        }
        pdf *= alpha;
        value *= this->weight * alpha;
        return value;
    }
    
    BSDFSample sample(float3 rnd, float3 wo, float3 shNormal, float3 geoNormal, RayFlags previousFlags) {
        if (rnd.x < alpha) {
            rnd.x /= alpha;
        } else {
            BSDFSample sample;
            sample.weight = alphaWeight * weight;
            sample.wi = -wo;
            sample.pdf = INFINITY; /// @todo hack
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
        
        uint8_t selectedLobe;
        BSDFSample sample;
        if (rnd.x < lobeProbabilities[0]) {
            selectedLobe = 0;
            sample = diffuse.sample(rnd.yz, wo);
        } else if (rnd.x < (lobeProbabilities[0] + lobeProbabilities[1])) {
            selectedLobe = 1;
            sample = specular.sample(rnd.yz, wo);
        } else if (rnd.x < (lobeProbabilities[0] + lobeProbabilities[1] + lobeProbabilities[2])) {
            selectedLobe = 2;
            sample = transmission.sample(rnd.yz, wo);
        } else {
            selectedLobe = 3;
            sample = clearcoat.sample(rnd.yz, wo);
        }
        
        if (!isfinite(lobeProbabilities[selectedLobe]))
            /// @todo why is this needed?
            return BSDFSample::invalid();
        
        if (lobeProbabilities[selectedLobe] < 1) {
            /// For MIS, we will need an accurate PDF and value of the entire material, not just the sampled lobe
            /// @todo the efficiency of this can probably be greatly improved by not re-evaluating the already sampled lobe
            sample.weight = evaluate(wo, sample.wi, shNormal, geoNormal, sample.pdf);
            sample.weight /= sample.pdf;
        } else {
            sample.pdf *= alpha;
            sample.weight *= this->weight * alpha;
        }
        
        const float wiDotShN = sample.wi.z;
        sample.wi = sample.wi * transpose(worldToShadingFrame);
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
    
    void setupForWorldHit() {
        normal = wo;
        uv = 0;
        generated = -wo;
        object = -wo;
    }
};

#ifndef JIT_COMPILED
#define NUMBER_OF_TEXTURES 1
#define USE_FUNCTION_TABLE
#endif

struct EnvmapSampling {
    int resolution [[ id(0) ]]; // must be a power of two
    device float *pdfs [[ id(1) ]];
    device float *mipmap [[ id(2) ]];
    
    float pdf(float3 wo) const device {
        uint2 position = uint2(resolution * warp::uniformSphereToSquare(wo)) % resolution;
        return pdfs[position.y * resolution + position.x];
    }
    
    float3 sample(float2 uv, thread float &pdf) const device {
        int currentResolution = 1;
        int2 shift = 0;
        
        device float *currentLevel = mipmap;
        while (currentResolution < resolution) {
            const int currentOffset = 4 * (shift.y * currentResolution + shift.x);
            
            currentLevel += currentResolution * currentResolution;
            shift *= 2;
            currentResolution *= 2;
            
            const float topLeft = currentLevel[currentOffset+0];
            const float topRight = currentLevel[currentOffset+1];
            const float bottomLeft = currentLevel[currentOffset+2];
            
            const float leftProb = topLeft + bottomLeft;
            float topProb;
            if (uv.x < leftProb) {
                // left
                const float invProb = 1 / leftProb;
                uv.x *= invProb;
                topProb = topLeft * invProb;
            } else {
                // right
                const float invProb = 1 / (1 - leftProb);
                uv.x = (uv.x - leftProb) * invProb;
                topProb = topRight * invProb;
                shift.x += 1;
            }
            
            if (uv.y < topProb) {
                // top
                uv.y /= topProb;
            } else {
                uv.y = (uv.y - topProb) / (1 - topProb);
                shift.y += 1;
            }
        }
        
        pdf = pdfs[shift.y * resolution + shift.x];
        uv = (float2(shift) + uv) / resolution;
        return warp::uniformSquareToSphere(uv);
    }
};

struct AreaLight {
    float3x4 transform;
    float3 color;
    bool isCircular;
};

struct NEESample {
    float3 weight;
    float pdf;
    float3 direction;
    float distance;
};

struct Context;
struct NEESampling {
    int numLightsTotal [[ id(0) ]];
    int numAreaLights [[ id(1) ]];
    
    int envmapShader [[ id(2) ]];
    EnvmapSampling envmap [[ id(3) ]];
    device AreaLight *areaLights [[ id(6) ]];
    
    float envmapPdf(float3 wo) const device {
        const float envmapSelectionProbability = 1 / float(numLightsTotal);
        return envmap.pdf(wo) * envmapSelectionProbability;
    }
    
    NEESample sample(device Context &ctx, thread ThreadContext &tctx, thread PRNGState &prng) const device {
        const int sampledLightSource = prng.sampleInt(numLightsTotal);
        const float lightSelectionProbability = 1 / float(numLightsTotal);
        if (sampledLightSource == 0) {
            NEESample result = sampleEnvmap(ctx, tctx, prng);
            result.pdf *= lightSelectionProbability;
            return result;
        }
        
        NEESample result = sampleAreaLights(ctx, tctx, prng);
        result.pdf *= lightSelectionProbability;
        return result;
    }
    
    void evaluateEnvironment(device Context &ctx, thread ThreadContext &tctx) const device;

private:
    NEESample sampleEnvmap(device Context &ctx, thread ThreadContext &tctx, thread PRNGState &prng) const device {
        NEESample sample;
        sample.direction = envmap.sample(prng.sample2d(), sample.pdf);
        sample.distance = INFINITY;
        
        ThreadContext neeTctx;
        neeTctx.rayFlags = tctx.rayFlags;
        neeTctx.rnd = prng.sample3d();
        neeTctx.wo = sample.direction;
        evaluateEnvironment(ctx, neeTctx);
        
        sample.weight = neeTctx.material.emission / sample.pdf;
        return sample;
    }
    
    NEESample sampleAreaLights(device Context &ctx, thread ThreadContext &tctx, thread PRNGState &prng) const device {
        NEESample sample;
        sample.weight = 0;
        sample.pdf = 0;
        return sample;
    }
};

struct Context {
    NEESampling nee [[ id(0) ]];
    array<texture2d<float>, NUMBER_OF_TEXTURES> textures [[ id(10) ]];
};

void NEESampling::evaluateEnvironment(device Context &ctx, thread ThreadContext &tctx) const device {
    tctx.setupForWorldHit();
    
#ifdef JIT_COMPILED
    const int shaderIndex = envmapShader;
    SWITCH_SHADERS
#endif
}
