#pragma once

#include "context.hpp"
#include "nodes.hpp"
#include "ShaderTypes.h"
#include "random.hpp"

#include <metal_stdlib>
using namespace metal;

constant float eps = 0.001f;

template<typename T>
T interpolate(T a, T b, T c, float2 barycentric) {
    float u = barycentric.x;
    float v = barycentric.y;
    float w = 1.0f - u - v;
    
    return a * u + b * v + c * w;
}

float3 vertexToFloat3(Vertex v) { return float3(v.x, v.y, v.z); }

float3 safe_divide(float3 a, float3 b, float3 fallback) {
    return select(a / b, fallback, b == 0);
}

float computeMisWeight(float pdf, float other) {
    if (isinf(pdf))
        return 1;
    
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
    PRNGState prng = ray.prng;
    
    ThreadContext tctx;
    tctx.rayFlags = ray.flags;
    tctx.rnd = prng.sample3d();
    tctx.wo = -ray.direction;
    
    constant Intersection &isect = intersections[rayIndex];
    if (isect.distance <= 0.0f) {
        // miss
        if (isinf(ray.bsdfPdf) || uniforms.samplingMode != SamplingModeNee) {
            const float misWeight = uniforms.samplingMode == SamplingModeBsdf ? 1 :
                computeMisWeight(ray.bsdfPdf, ctx.lights.envmapPdf(ray.direction));
            
            ctx.lights.evaluateEnvironment(ctx, tctx);
            uint2 coordinates = uint2(ray.x, ray.y);
            image.write(
                image.read(coordinates) + float4(
                    misWeight * ray.weight * tctx.material.emission,
                    1),
                coordinates
            );
        }
        
        return;
    }
    
    const device PerInstanceData &instance = ctx.perInstanceData[isect.instanceIndex];
    
    int shaderIndex;
    {
        const unsigned int faceIndex = instance.faceOffset + isect.primitiveIndex;
        const unsigned int idx0 = instance.vertexOffset + ctx.vertexIndices[3 * faceIndex + 0];
        const unsigned int idx1 = instance.vertexOffset + ctx.vertexIndices[3 * faceIndex + 1];
        const unsigned int idx2 = instance.vertexOffset + ctx.vertexIndices[3 * faceIndex + 2];
        
        // @todo: is this numerically stable enough?
        //ipoint = ray.origin + ray.direction * isect.distance;
        
        float2 Tc = ctx.texcoords[idx2];
        float2x2 T;
        T.columns[0] = ctx.texcoords[idx0] - Tc;
        T.columns[1] = ctx.texcoords[idx1] - Tc;
        tctx.uv = float3(T * isect.coordinates + Tc, 0);
        
        float3 Pc = vertexToFloat3(ctx.vertices[idx2]);
        float2x3 P;
        P.columns[0] = vertexToFloat3(ctx.vertices[idx0]) - Pc;
        P.columns[1] = vertexToFloat3(ctx.vertices[idx1]) - Pc;
        tctx.trueNormal = normalize(instance.normalTransform * cross(P.columns[0], P.columns[1]));
        
        float3 localP = P * isect.coordinates + Pc;
        tctx.object = localP;
        tctx.generated = safe_divide(localP - instance.boundsMin, instance.boundsSize, 0.5f);
        tctx.position = (instance.pointTransform * float4(localP, 1)).xyz;
        
        tctx.normal = instance.normalTransform * interpolate(
            vertexToFloat3(ctx.vertexNormals[idx0]),
            vertexToFloat3(ctx.vertexNormals[idx1]),
            vertexToFloat3(ctx.vertexNormals[idx2]),
            isect.coordinates);
        tctx.normal = normalize(tctx.normal);
        
        tctx.tu = normalize(instance.normalTransform * (P * float2(T[1][1], -T[0][1])));
        tctx.tv = normalize(instance.normalTransform * (P * float2(-T[1][0], T[0][0])));

        shaderIndex = ctx.materials[faceIndex];
    }
    
    if (instance.visibility & ray.flags) {
        shadeSurface(shaderIndex, ctx, tctx);
    } else {
        tctx.material.alpha = 0;
    }
    
    if (mean(tctx.material.emission) != 0) {
        uint2 coordinates = uint2(ray.x, ray.y);
        image.write(
            image.read(coordinates) + float4(
                ray.weight * tctx.material.emission,
                1),
            coordinates
        );
    }
    
    /*{
        uint2 coordinates = uint2(ray.x, ray.y);
        image.write(
            image.read(coordinates) + float4(
                ray.weight * (
                    tctx.material.diffuse.diffuseWeight +
                    tctx.material.diffuse.sheenWeight +
                    tctx.material.specular.Cspec0 +
                    tctx.material.transmission.Cspec0
                ),
                1),
            coordinates
        );
        return;
    }*/
    
    float3 shNormal;
    if (all(tctx.material.normal == 0)) {
        shNormal = tctx.trueNormal;
    } else {
        float3 geoNormal = tctx.trueNormal;
        if (dot(geoNormal, tctx.wo) < 0) geoNormal *= -1;
        
        /// @todo this should use the shading normal I think
        shNormal = ensure_valid_reflection(geoNormal, tctx.wo, tctx.material.normal);
    }
    
    // MARK: NEE sampling
    /// @todo slight inaccuracies with BsdfTranslucent
    /// @todo verify that clearcoat evaluation works correctly
    if (uniforms.samplingMode != SamplingModeBsdf) {
        LightSample neeSample = ctx.lights.sample(ctx, tctx, prng);
        
        float bsdfPdf;
        float3 bsdf = tctx.material.evaluate(tctx.wo, neeSample.direction, shNormal, tctx.trueNormal, bsdfPdf);
        
        float3 contribution = neeSample.weight * bsdf * ray.weight;
        if (neeSample.castsShadows) {
            const float misWeight = uniforms.samplingMode == SamplingModeNee || !neeSample.canBeHit ? 1 :
                computeMisWeight(neeSample.pdf, bsdfPdf);
            
            const float3 neeWeight = misWeight * contribution;
            if (all(isfinite(neeWeight)) && any(neeWeight != 0)) {
                uint nextShadowRayIndex = atomic_fetch_add_explicit(&shadowRayCount, 1, memory_order_relaxed);
                device ShadowRay &shadowRay = shadowRays[nextShadowRayIndex];
                shadowRay.origin = tctx.position;
                shadowRay.direction = neeSample.direction;
                shadowRay.minDistance = eps;
                shadowRay.maxDistance = neeSample.distance;
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
    
    BSDFSample sample = tctx.material.sample(tctx.rnd, -ray.direction, shNormal, tctx.trueNormal, ray.flags);
    
    float3 weight = ray.weight * sample.weight;
    float meanWeight = mean(weight);
    if (!isfinite(meanWeight)) return;
    
    float survivalProb = min(meanWeight, 1.f);
    if (prng.sample() < survivalProb) {
        uint nextRayIndex = atomic_fetch_add_explicit(&nextRayCount, 1, memory_order_relaxed);
        device Ray &nextRay = nextRays[nextRayIndex];
        nextRay.origin = tctx.position;
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

kernel void buildEnvironmentMap(
    device Context &ctx [[buffer(0)]],
    device float *mipmap [[buffer(1)]],
    device float *pdfs [[buffer(2)]],
    uint2 threadIndex [[thread_position_in_grid]],
    uint2 imageSize   [[threads_per_grid]]
) {
    const bool UseSecondMoment = !true;
    
    const int rayIndex = threadIndex.y * imageSize.x + threadIndex.x;
    
    float value = 0;
    int numSamples = 64;
    for (int sampleIndex = 0; sampleIndex < numSamples; sampleIndex++) {
        /// @todo this might benefit from low discrepancy sampling
        
        PRNGState prng;
        prng.seed = sample_tea_32(sampleIndex, rayIndex);
        prng.index = 0;
        
        float2 projected = (float2(threadIndex) + prng.sample2d()) / float2(imageSize);
        float3 wo = warp::uniformSquareToSphere(projected);
        
        ThreadContext tctx;
        tctx.rayFlags = RayFlags(0);
        tctx.rnd = prng.sample3d();
        tctx.wo = -wo;
        ctx.lights.evaluateEnvironment(ctx, tctx);
        
        float3 sampleValue = tctx.material.emission;
        if (UseSecondMoment) {
            sampleValue = square(sampleValue);
        }
        
        value += mean(sampleValue);
    }
    
    value /= numSamples;
    if (UseSecondMoment) {
        value = sqrt(value);
    }
    value += 1e-8;
    
    const uint2 quadPosition = threadIndex / 2;
    const uint2 quadGridSize = imageSize / 2;
    const uint quadIndex = quadPosition.y * quadGridSize.x + quadPosition.x;
    const uint outputIndex = 4 * quadIndex + (threadIndex.x & 1) + 2 * (threadIndex.y & 1);
    mipmap[outputIndex] = value;
    pdfs[threadIndex.y * imageSize.x + threadIndex.x] = value;
}

kernel void handleShadowRays(
    texture2d<float, access::read_write> image [[texture(0)]],
    
    constant Intersection *intersections [[buffer(ShadowBufferIntersections)]],
    device ShadowRay *shadowRays [[buffer(ShadowBufferShadowRays)]],
    device const uint &rayCount [[buffer(ShadowBufferRayCount)]],
    
    uint rayIndex [[thread_position_in_grid]]
) {
    if (rayIndex >= rayCount)
        return;
    
    device ShadowRay &shadowRay = shadowRays[rayIndex];
    
    constant Intersection &isect = intersections[rayIndex];
    if (isect.distance < 0.0f)
    {
        uint2 coordinates = uint2(shadowRay.x, shadowRay.y);
        image.write(
            image.read(coordinates) + float4(shadowRay.weight, 1),
            coordinates
        );
    }
}

// MARK: environment map building

kernel void reduceEnvironmentMap(
    device float *mipmap [[buffer(0)]],
    uint2 threadIndex [[thread_position_in_grid]],
    uint2 gridSize [[threads_per_grid]]
) {
    const int inputIndex = threadIndex.y * gridSize.x + threadIndex.x;
    const int gridLength = gridSize.x * gridSize.y;
    
    float sum = 0;
    for (int i = 0; i < 4; ++i) {
        sum += mipmap[gridLength + 4 * inputIndex + i];
    }
    for (int i = 0; i < 4; ++i) {
        mipmap[gridLength + 4 * inputIndex + i] /= sum;
    }
    
    const uint2 quadPosition = threadIndex / 2;
    const uint2 quadGridSize = gridSize / 2;
    const uint quadIndex = quadPosition.y * quadGridSize.x + quadPosition.x;
    const uint outputIndex = 4 * quadIndex + (threadIndex.x & 1) + 2 * (threadIndex.y & 1);
    mipmap[outputIndex] = sum;
}

kernel void normalizeEnvironmentMap(
    device float &sum [[buffer(0)]],
    device float *pdfs [[buffer(1)]],
    uint threadIndex [[thread_position_in_grid]],
    uint gridSize [[threads_per_grid]]
) {
    pdfs[threadIndex] *= gridSize * warp::uniformSquareToSpherePdf() / sum;
}

kernel void testEnvironmentMapSampling(
    device Context &ctx [[buffer(0)]],
    device atomic_float *histogram [[buffer(1)]],
    uint2 threadIndex [[thread_position_in_grid]],
    uint2 gridSize [[threads_per_grid]]
) {
    PRNGState prng;
    prng.seed = sample_tea_32(threadIndex.x, threadIndex.y);
    prng.index = 0;
    
    const int outputResolution = 256;
    
    const float norm = outputResolution * outputResolution / float(gridSize.x * gridSize.y);
    //const float2 uv = prng.sample2d();
    const float2 uv = (float2(threadIndex) + prng.sample2d()) / float2(gridSize);
    //const float3 sample = warp::uniformSquareToSphere(uv);
    
    float samplePdf;
    const float3 sample = ctx.lights.worldLight.sample(uv, samplePdf);
    const float2 projected = warp::uniformSphereToSquare(sample);
    const float pdf = 1;//ctx.envmap.pdf(sample) * (4 * M_PI_F);
    
    const uint2 outputPos = uint2(projected * outputResolution) % outputResolution;
    const int outputIndex = outputPos.y * outputResolution + outputPos.x;
    atomic_fetch_add_explicit(histogram + outputIndex, norm / pdf, memory_order_relaxed);
}
