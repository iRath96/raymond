#pragma once

#include <bridge/common.hpp>
#include <bridge/lights/AreaLight.hpp>
#include <bridge/lights/PointLight.hpp>
#include <bridge/lights/SunLight.hpp>
#include <bridge/lights/SpotLight.hpp>
#include <bridge/lights/ShapeLight.hpp>
#include <bridge/ResourceIds.hpp>
#include <bridge/PrngState.hpp>
#include <device/ShadingContext.hpp>
#include <device/shading.hpp>
#include "LightSample.hpp"
#include "WorldLight.hpp"

struct Lights {
    int numLightsTotal [[id(LightsBufferTotalLightCount)]];
    int numAreaLights  [[id(LightsBufferAreaLightCount)]];
    int numPointLights [[id(LightsBufferPointLightCount)]];
    int numSunLights   [[id(LightsBufferSunLightCount)]];
    int numSpotLights  [[id(LightsBufferSpotLightCount)]];
    int numShapeLights [[id(LightsBufferShapeLightCount)]];
    
    device const float *lightFaces [[id(LightsBufferLightFaces)]];
    
    WorldLight worldLight          [[id(LightsBufferWorldLight)]];
    device AreaLight *areaLights   [[id(LightsBufferAreaLight)]];
    device PointLight *pointLights [[id(LightsBufferPointLight)]];
    device SunLight *sunLights     [[id(LightsBufferSunLight)]];
    device SpotLight *spotLights   [[id(LightsBufferSpotLight)]];
    device ShapeLight *shapeLights [[id(LightsBufferShapeLight)]];
    
    float shapePdf(device const PerInstanceData &instance, thread const ShadingContext &shading) const device {
        const float selectionProbability = 1 / float(numLightsTotal);
        return selectionProbability * shapeLights[instance.lightIndex].pdf(shading);
    }
    
    float envmapPdf(float3 wo) const device {
        const float selectionProbability = 1 / float(numLightsTotal);
        return selectionProbability * worldLight.pdf(wo);
    }
    
    LightSample sample(device Context &ctx, thread ShadingContext &shading, thread PrngState &prng) const device {
        int sampledLightSource = prng.sampleInt(numLightsTotal);
        LightSample sample;
        
        ShadingContext lightShading;
        lightShading.rayFlags = shading.rayFlags;
        lightShading.position = shading.position;
        
        if (sampledLightSource == 0) {
            sample = sampleEnvmap(ctx, lightShading, prng);
        } else if ((sampledLightSource -= 1) < numAreaLights) {
            sample = areaLights[sampledLightSource].sample(ctx, lightShading, prng);
        } else if ((sampledLightSource -= numAreaLights) < numPointLights) {
            sample = pointLights[sampledLightSource].sample(ctx, lightShading, prng);
        } else if ((sampledLightSource -= numPointLights) < numSunLights) {
            sample = sunLights[sampledLightSource].sample(ctx, lightShading, prng);
        } else if ((sampledLightSource -= numSunLights) < numSpotLights) {
            sample = spotLights[sampledLightSource].sample(ctx, lightShading, prng);
        } else if ((sampledLightSource -= numSpotLights) < numShapeLights) {
            sample = shapeLights[sampledLightSource].sample(ctx, lightShading, prng);
        } else {
            return LightSample::invalid();
        }
        
        lightShading.wo = -sample.direction;
        if (any(sample.weight != 0)) {
            if (sample.isLight) {
                shadeLight(sample.shaderIndex, ctx, lightShading);
            } else {
                // :-(
                shadeSurface(sample.shaderIndex, ctx, lightShading);
            }
            sample.weight *= lightShading.material.emission;
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
    
    void evaluateEnvironment(device Context &ctx, thread ShadingContext &shading) const device;

private:
    LightSample sampleEnvmap(device Context &ctx, thread ShadingContext &shading, thread PrngState &prng) const device {
        LightSample sample;
        sample.direction = worldLight.sample(prng.sample2d(), sample.pdf);
        sample.distance = INFINITY;
        sample.shaderIndex = worldLight.shaderIndex;
        sample.castsShadows = true;
        sample.canBeHit = true;
        sample.isLight = true;
        
        shading.position = -sample.direction;
        shading.normal = -sample.direction;
        shading.trueNormal = -sample.direction; /// @todo ???
        shading.generated = sample.direction;
        shading.object = sample.direction;
        shading.uv = 0;
        
        sample.weight = 1 / sample.pdf;
        return sample;
    }
};
