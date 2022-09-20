#pragma once

#include "bsdf.hpp"
#include "warp.hpp"
#include "ShaderTypes.h"

#include <metal_stdlib>
using namespace metal;

struct Context;
struct ThreadContext;
void runShader(device Context &ctx, thread ThreadContext &tctx, int shaderIndex);

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
    
    template<bool IsLocal = false>
    float3 evaluate(float3 wo, float3 wi, float3 shNormal, float3 geoNormal, thread float &pdf) {
        /// @todo alpha? pdf and weight fields? mix/add shaders?
        pdf = 0;
        
        if (!IsLocal) {
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
            sample.weight = evaluate<true>(wo, sample.wi, shNormal, geoNormal, sample.pdf);
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
    float3 wo; // pointing away from the hitpoint
    RayFlags rayFlags;
    
    Material material;
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

struct NEESample {
    bool canBeHit;
    float3 weight;
    float pdf;
    float3 direction;
    float distance;
    
    static NEESample invalid() {
        NEESample result;
        result.pdf = 0;
        result.weight = 0;
        return result;
    }
};

struct Context;
struct NEESampling {
    int numLightsTotal [[ id(0) ]];
    int numAreaLights [[ id(1) ]];
    int numPointLights [[ id(2) ]];
    
    int envmapShader [[ id(3) ]];
    EnvmapSampling envmap [[ id(4) ]];
    device NEEAreaLight *neeAreaLights [[ id(7) ]];
    device NEEPointLight *neePointLights [[ id(8) ]];
    
    float envmapPdf(float3 wo) const device {
        const float envmapSelectionProbability = 1 / float(numLightsTotal);
        return envmap.pdf(wo) * envmapSelectionProbability;
    }
    
    NEESample sample(device Context &ctx, thread ThreadContext &tctx, thread PRNGState &prng) const device {
        int sampledLightSource = prng.sampleInt(numLightsTotal);
        NEESample result;
        if (sampledLightSource == 0) {
            result = sampleEnvmap(ctx, tctx, prng);
            result.canBeHit = true;
        } else if ((sampledLightSource -= 1) < numAreaLights) {
            result = neeAreaLights[sampledLightSource].sample(ctx, tctx, prng);
            result.canBeHit = false;
        } else if ((sampledLightSource -= numAreaLights) < numPointLights) {
            result = neePointLights[sampledLightSource].sample(ctx, tctx, prng);
            result.canBeHit = false;
        } else {
            result = NEESample::invalid();
        }
        
        result.weight *= numLightsTotal;
        result.pdf /= numLightsTotal;
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
        neeTctx.wo = -sample.direction;
        evaluateEnvironment(ctx, neeTctx);
        
        sample.weight = neeTctx.material.emission / sample.pdf;
        return sample;
    }
};

struct Context {
    NEESampling nee [[ id(0) ]];
    array<texture2d<float>, NUMBER_OF_TEXTURES> textures [[ id(10) ]];
};

void NEESampling::evaluateEnvironment(device Context &ctx, thread ThreadContext &tctx) const device {
    tctx.normal = tctx.wo;
    tctx.generated = -tctx.wo;
    tctx.object = -tctx.wo;
    tctx.uv = 0;
    
    runShader(ctx, tctx, envmapShader);
}

NEESample NEEAreaLight::sample(
    device Context &ctx,
    thread ThreadContext &tctx,
    thread PRNGState &prng
) const device {
    const float3 point = float4(prng.sample2d() - 0.5, 0, 1) * transform;
    const float3 normal = normalize(float4(0, 0, 1, 0) * transform);
    
    NEESample sample;
    sample.direction = point - tctx.position;
    
    const float lensqr = length_squared(sample.direction);
    sample.distance = sqrt(lensqr);
    
    ThreadContext neeTctx;
    neeTctx.rayFlags = tctx.rayFlags;
    neeTctx.wo = -sample.direction;
    neeTctx.position = point;
    neeTctx.generated = point;
    neeTctx.position = point;
    runShader(ctx, neeTctx, shaderIndex);
    
    const float G = saturate(dot(normal, sample.direction)) / lensqr;
    sample.direction /= sample.distance;
    sample.weight = color * neeTctx.material.emission * G * 0.25f;
    sample.pdf = 1;
    return sample;
}

NEESample NEEPointLight::sample(
    device Context &ctx,
    thread ThreadContext &tctx,
    thread PRNGState &prng
) const device {
    const float3 lightN = normalize(tctx.position - location);
    float3 point = location;
    
    if (radius > 0) {
        float3x3 basis = buildOrthonormalBasis(lightN);
        point += radius * (basis * float3(warp::uniformSquareToDisk(prng.sample2d()), 0));
    }
    
    NEESample sample;
    sample.direction = point - tctx.position;
    
    const float lensqr = length_squared(sample.direction);
    sample.distance = sqrt(lensqr);
    sample.direction /= sample.distance;
    
    ThreadContext neeTctx;
    neeTctx.rayFlags = tctx.rayFlags;
    neeTctx.wo = -sample.direction;
    neeTctx.normal = -sample.direction;
    neeTctx.trueNormal = -sample.direction;
    neeTctx.position = point;
    neeTctx.generated = point;
    neeTctx.position = point;
    neeTctx.uv = float3(warp::uniformSphereToSquare(-sample.direction), 0);
    runShader(ctx, neeTctx, shaderIndex);
    
    const float G = 1 / lensqr;
    sample.weight = color * neeTctx.material.emission * G * (M_1_PI_F * 0.25f);
    sample.pdf = 1;
    return sample;
}

void runShader(device Context &ctx, thread ThreadContext &tctx, int shaderIndex) {
#ifdef JIT_COMPILED
    SWITCH_SHADERS
#endif
}
