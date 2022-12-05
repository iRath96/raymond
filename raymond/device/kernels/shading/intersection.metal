#include <bridge/common.hpp>
#include <bridge/Ray.hpp>
#include <bridge/Uniforms.hpp>
#include <bridge/ResourceIds.hpp>
#include <bridge/PerInstanceData.hpp>
#include <device/utils/math.hpp>
#include <device/lights/LightSample.hpp>
#include <device/bsdf/BsdfSample.hpp>
#include <device/ShadingContext.hpp>
#include <device/Context.hpp>
#include <device/constants.hpp>

float computeMisWeight(float pdf, float other) {
    pdf *= pdf;
    other *= other;
    return pdf / (pdf + other);
}

constant bool isMaxDepth [[function_constant(0)]];
kernel void handleIntersections(
    texture2d<float, access::read_write> image [[texture(0)]],
    
    // ray buffers
    constant Intersection *intersections [[buffer(ShadingBufferIntersections)]],
    device Ray *rays [[buffer(ShadingBufferRays)]],
    device Ray *nextRays [[buffer(ShadingBufferNextRays)]],
    device ShadowRay *shadowRays [[buffer(ShadingBufferShadowRays)]],
    
    // ray counters
    device const uint &currentRayCount [[buffer(ShadingBufferCurrentRayCount)]],
    device atomic_uint &nextRayCount [[buffer(ShadingBufferNextRayCount)]],
    device atomic_uint &shadowRayCount [[buffer(ShadingBufferShadowRayCount)]],
    
    // scene buffers
    constant Uniforms &uniforms [[buffer(ShadingBufferUniforms)]],
    device Context &ctx [[buffer(ShadingBufferContext)]],
    
    uint rayIndex [[thread_position_in_grid]]
) {
    if (rayIndex >= currentRayCount)
        return;
    
    device Ray &ray = rays[rayIndex];
    const bool needsToCollectEmission = isinf(ray.bsdfPdf) || uniforms.samplingMode != SamplingModeNee;
    
    /*{
        uint2 coordinates = uint2(ray.x, ray.y);
        image.write(
            image.read(coordinates) + float4(0.5, 0.2, 0.7, 1),
            coordinates
        );
        return;
    }*/
    
#define DO_COMPACTION
#ifndef DO_COMPACTION
    uint nextRayIndex = rayIndex;
    device Ray &nextRay = nextRays[nextRayIndex];
    nextRay = ray;
    nextRay.weight = 0;
    atomic_fetch_add_explicit(&nextRayCount, 1, memory_order_relaxed);
#endif
    
    PrngState prng = ray.prng;
    
    ShadingContext shading;
    shading.rayFlags = ray.flags;
    shading.rnd = prng.sample3d();
    shading.wo = -ray.direction;
    
    constant Intersection &isect = intersections[rayIndex];
    if (isect.distance <= 0.0f) {
        // miss
        if (needsToCollectEmission) {
            const float misWeight = (uniforms.samplingMode == SamplingModeBsdf) || isinf(ray.bsdfPdf) ? 1 :
                computeMisWeight(ray.bsdfPdf, ctx.lights.envmapPdf(ray.direction));
            
            ctx.lights.evaluateEnvironment(ctx, shading);
            uint2 coordinates = uint2(ray.x, ray.y);
            image.write(
                image.read(coordinates) + float4(
                    misWeight * ray.weight * shading.material.emission,
                    1),
                coordinates
            );
        }
        
        return;
    }
    
    const device PerInstanceData &instance = ctx.perInstanceData[isect.instanceIndex];
    
    MaterialIndex shaderIndex;
    shading.build(ctx, instance, isect, shaderIndex);
    
    if (instance.visibility & ray.flags) {
        shadeSurface(shaderIndex, ctx, shading);
    } else {
        shading.material.alpha = 0;
    }
    
    if (needsToCollectEmission && mean(shading.material.emission) != 0) {
        const float misWeight = (uniforms.samplingMode == SamplingModeBsdf) || isinf(ray.bsdfPdf) ? 1 :
            computeMisWeight(ray.bsdfPdf, ctx.lights.shapePdf(instance, shading));
        
        uint2 coordinates = uint2(ray.x, ray.y);
        image.write(
            image.read(coordinates) + float4(
                misWeight * ray.weight * shading.material.emission,
                1),
            coordinates
        );
    }
    
    /*{
        uint2 coordinates = uint2(ray.x, ray.y);
        image.write(
            image.read(coordinates) + float4(
                ray.weight * (
                    shading.material.diffuse.diffuseWeight +
                    shading.material.diffuse.sheenWeight +
                    shading.material.specular.Cspec0 +
                    shading.material.transmission.Cspec0
                ),
                1),
            coordinates
        );
        return;
    }*/
    
    float3 shNormal;
    if (all(shading.material.normal == 0)) {
        shNormal = shading.trueNormal;
    } else {
        float3 geoNormal = shading.trueNormal;
        if (dot(geoNormal, shading.wo) < 0) geoNormal *= -1;
        
        /// @todo this should use the shading normal I think
        shNormal = ensure_valid_reflection(geoNormal, shading.wo, shading.material.normal);
    }
    
    // MARK: NEE sampling
    /// @todo slight inaccuracies with BsdfTranslucent
    /// @todo verify that clearcoat evaluation works correctly
    if (uniforms.samplingMode != SamplingModeBsdf) {
        LightSample neeSample = ctx.lights.sample(ctx, shading, prng);
        
        float bsdfPdf;
        float3 bsdf = shading.material.evaluate(shading.wo, neeSample.direction, shNormal, shading.trueNormal, bsdfPdf);
        
        float3 contribution = neeSample.weight * bsdf * ray.weight;
        if (neeSample.castsShadows) {
            const float misWeight = uniforms.samplingMode == SamplingModeNee || !neeSample.canBeHit ? 1 :
                computeMisWeight(neeSample.pdf, bsdfPdf);
            
            const float3 neeWeight = misWeight * contribution;
            if (all(isfinite(neeWeight)) && any(neeWeight != 0)) {
                uint nextShadowRayIndex = atomic_fetch_add_explicit(&shadowRayCount, 1, memory_order_relaxed);
                device ShadowRay &shadowRay = shadowRays[nextShadowRayIndex];
                shadowRay.origin = shading.position;
                shadowRay.direction = neeSample.direction;
                shadowRay.minDistance = eps;
                shadowRay.maxDistance = neeSample.distance - eps;
                shadowRay.weight = neeWeight;
                shadowRay.x = ray.x;
                shadowRay.y = ray.y;
            }
        } else {
            uint2 coordinates = uint2(ray.x, ray.y);
            image.write(
                image.read(coordinates) + float4(
                    ray.weight * contribution,
                    1),
                coordinates
            );
        }
    }
    
    // MARK: BSDF sampling
    
    BsdfSample sample = shading.material.sample(shading.rnd, -ray.direction, shNormal, shading.trueNormal, ray.flags);
    
    float3 weight = ray.weight * sample.weight;
    float meanWeight = mean(weight);
    if (!isfinite(meanWeight)) return;
    
    float survivalProb = min(meanWeight, 1.f);
    if (prng.sample() < survivalProb) {
#ifdef DO_COMPACTION
        uint nextRayIndex = atomic_fetch_add_explicit(&nextRayCount, 1, memory_order_relaxed);
        device Ray &nextRay = nextRays[nextRayIndex];
#endif
        nextRay.origin = shading.position;
        nextRay.flags = sample.flags;
        nextRay.direction = sample.wi;
        nextRay.minDistance = eps;
        nextRay.maxDistance = INFINITY;
        nextRay.weight = weight * (1 / survivalProb);
        nextRay.x = ray.x;
        nextRay.y = ray.y;
        nextRay.prng = prng;
        nextRay.bsdfPdf = sample.pdf;
    }
    
    return;
}
