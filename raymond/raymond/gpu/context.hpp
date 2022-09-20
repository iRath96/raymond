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
    int shaderIndex;
    bool canBeHit;
    bool usesVisibility;
    float3 weight;
    float pdf;
    float3 direction;
    float distance;
    
    NEESample() {}
    NEESample(NEELightInfo info) {
        shaderIndex = info.shaderIndex;
        canBeHit = info.usesMIS;
        usesVisibility = info.usesVisibility;
    }
    
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
    int numSunLights [[ id(3) ]];
    int numSpotLights [[ id(4) ]];
    
    int envmapShader [[ id(5) ]];
    EnvmapSampling envmap [[ id(6) ]];
    device NEEAreaLight *neeAreaLights [[ id(9) ]];
    device NEEPointLight *neePointLights [[ id(10) ]];
    device NEESunLight *neeSunLights [[ id(11) ]];
    device NEESpotLight *neeSpotLights [[ id(12) ]];
    
    float envmapPdf(float3 wo) const device {
        const float envmapSelectionProbability = 1 / float(numLightsTotal);
        return envmap.pdf(wo) * envmapSelectionProbability;
    }
    
    NEESample sample(device Context &ctx, thread ThreadContext &tctx, thread PRNGState &prng) const device {
        int sampledLightSource = prng.sampleInt(numLightsTotal);
        NEESample sample;
        
        ThreadContext neeTctx;
        neeTctx.rayFlags = tctx.rayFlags;
        neeTctx.position = tctx.position;
        
        if (sampledLightSource == 0) {
            sample = sampleEnvmap(ctx, neeTctx, prng);
        } else if ((sampledLightSource -= 1) < numAreaLights) {
            sample = neeAreaLights[sampledLightSource].sample(ctx, neeTctx, prng);
        } else if ((sampledLightSource -= numAreaLights) < numPointLights) {
            sample = neePointLights[sampledLightSource].sample(ctx, neeTctx, prng);
        } else if ((sampledLightSource -= numPointLights) < numSunLights) {
            sample = neeSunLights[sampledLightSource].sample(ctx, neeTctx, prng);
        } else if ((sampledLightSource -= numSunLights) < numSpotLights) {
            sample = neeSpotLights[sampledLightSource].sample(ctx, neeTctx, prng);
        } else {
            return NEESample::invalid();
        }
        
        neeTctx.wo = -sample.direction;
        if (any(sample.weight != 0)) {
            runShader(ctx, neeTctx, sample.shaderIndex);
            sample.weight *= neeTctx.material.emission;
        }
        
        sample.weight *= numLightsTotal;
        sample.pdf /= numLightsTotal;
        
        /// @todo evaluate whether this is actually beneficial for performance
        const float survivalProbability = saturate(4 * mean(sample.weight));
        if (survivalProbability < 1) {
            //sample.pdf *= survivalProbability; /// @todo this would also need to be done in evaluate
            if (prng.sample() < survivalProbability) {
                sample.weight /= survivalProbability;
            } else {
                sample.weight = 0;
            }
        }
        
        return sample;
    }
    
    void evaluateEnvironment(device Context &ctx, thread ThreadContext &tctx) const device;

private:
    NEESample sampleEnvmap(device Context &ctx, thread ThreadContext &tctx, thread PRNGState &prng) const device {
        NEESample sample;
        sample.direction = envmap.sample(prng.sample2d(), sample.pdf);
        sample.distance = INFINITY;
        sample.shaderIndex = envmapShader;
        sample.usesVisibility = true;
        sample.canBeHit = true;
        
        tctx.position = -sample.direction;
        tctx.normal = -sample.direction;
        tctx.trueNormal = -sample.direction; /// @todo ???
        tctx.generated = sample.direction;
        tctx.object = sample.direction;
        tctx.uv = 0;
        
        sample.weight = 1 / sample.pdf;
        return sample;
    }
};

struct Context {
    NEESampling nee [[ id(0) ]];
    array<texture2d<float>, NUMBER_OF_TEXTURES> textures [[ id(20) ]];
};

void NEESampling::evaluateEnvironment(device Context &ctx, thread ThreadContext &tctx) const device {
    tctx.position = tctx.wo;
    tctx.normal = tctx.wo;
    tctx.trueNormal = tctx.wo; /// @todo ???
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
    float2 uv = prng.sample2d();
    if (isCircular) {
        uv = warp::uniformSquareToDisk(uv) / 2 + 0.5;
    }
    
    const float3 point = float4(uv - 0.5, 0, 1) * transform;
    const float3 normal = normalize(float4(0, 0, 1, 0) * transform);
    
    NEESample sample(info);
    sample.direction = point - tctx.position;
    
    const float lensqr = length_squared(sample.direction);
    sample.distance = sqrt(lensqr);
    
    tctx.normal = -normal;
    tctx.trueNormal = -normal;
    tctx.position = point;
    tctx.generated = point;
    tctx.position = point;
    tctx.uv = float3(uv, 0);
    
    const float G = saturate(dot(normal, sample.direction)) / lensqr;
    sample.direction /= sample.distance;
    sample.weight = color * G * 0.25f;
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
    
    NEESample sample(info);
    sample.direction = point - tctx.position;
    
    const float lensqr = length_squared(sample.direction);
    sample.distance = sqrt(lensqr);
    sample.direction /= sample.distance;
    
    tctx.normal = -sample.direction;
    tctx.trueNormal = -sample.direction;
    tctx.position = point;
    tctx.generated = point;
    tctx.position = point;
    tctx.uv = float3(warp::uniformSphereToSquare(-sample.direction), 0);
    
    const float G = 1 / lensqr;
    sample.weight = color * G * (M_1_PI_F * 0.25f);
    sample.pdf = 1;
    return sample;
}

NEESample NEESunLight::sample(
    device Context &ctx,
    thread ThreadContext &tctx,
    thread PRNGState &prng
) const device {
    const float2 rnd = prng.sample2d();
    const float cosTheta = 1 - rnd.y * (1 - cosAngle);
    const float sinTheta = sqrt(saturate(1 - cosTheta * cosTheta));
    float cosPhi;
    float sinPhi = sincos(2 * M_PI_F * rnd.x, cosPhi);
    
    const float3x3 frame = buildOrthonormalBasis(direction);
    const float3 point = frame * float3(sinTheta * sinPhi, sinTheta * cosPhi, cosTheta);

    NEESample sample(info);
    sample.direction = point;
    sample.distance = INFINITY;
    
    tctx.normal = -sample.direction;
    tctx.trueNormal = -sample.direction;
    tctx.position = -sample.direction;
    tctx.generated = -sample.direction;
    tctx.position = -sample.direction;
    tctx.uv = float3(warp::uniformSphereToSquare(-sample.direction), 0);
    
    sample.weight = color;
    sample.pdf = 1;
    return sample;
}

float spotLightAttenuation(float3 dir, float spotAngle, float spotSmooth, float3 N) {
    float attenuation = dot(dir, N);
    if (attenuation <= spotAngle) {
        attenuation = 0.0f;
    } else {
        float t = attenuation - spotAngle;
        if (t < spotSmooth && spotSmooth != 0.0f)
            attenuation *= smoothstep(0, spotSmooth, t);
    }

    return attenuation;
}

NEESample NEESpotLight::sample(
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
    
    NEESample sample(info);
    sample.direction = point - tctx.position;
    
    const float lensqr = length_squared(sample.direction);
    sample.distance = sqrt(lensqr);
    sample.direction /= sample.distance;
    
    tctx.normal = -sample.direction;
    tctx.trueNormal = -sample.direction;
    tctx.position = point;
    tctx.generated = point;
    tctx.position = point;
    tctx.uv = float3(warp::uniformSphereToSquare(-sample.direction), 0);
    
    const float G = 1 / lensqr;
    const float attenuation = spotLightAttenuation(direction, spotSize, spotBlend, sample.direction);
    sample.weight = attenuation * color * G * (M_1_PI_F * 0.25f);
    sample.pdf = 1;
    return sample;
}

void runShader(device Context &ctx, thread ThreadContext &tctx, int shaderIndex) {
#ifdef JIT_COMPILED
    SWITCH_SHADERS
#endif
}
