#include <bridge/common.hpp>
#include <bridge/Ray.hpp>
#include <bridge/ResourceIds.hpp>
#include <bridge/PrngState.hpp>
#include <bridge/Uniforms.hpp>
#include <device/Context.hpp>

#include <lore/lens/Lens.h>
#include <lore/rt/GeometricalIntersector.h>
#include <lore/rt/SequentialTrace.h>

#define SPECTRAL 1

/// @todo replace this with proper CIE curves
float3 spectral(float wavelength) {
    float3 result = 0;
    if ((wavelength >= 380) && (wavelength < 440)) {
        result = float3(-(wavelength - 440) / (440 - 380), 0, 1);
    } else if ((wavelength >= 440) && (wavelength < 490)) {
        result = float3(0, (wavelength - 440) / (490 - 440), 1);
    } else if ((wavelength >= 490) && (wavelength < 510)) {
        result = float3(0, 1, -(wavelength - 510) / (510 - 490));
    } else if ((wavelength >= 510) && (wavelength < 580)) {
        result = float3((wavelength - 510) / (580 - 510), 1, 0);
    } else if ((wavelength >= 580) && (wavelength < 645)) {
        result = float3(1, -(wavelength - 645) / (645 - 580), 0);
    } else if ((wavelength >= 645) && (wavelength < 781)) {
        result = float3(1, 0, 0);
    }

    // Let the intensity fall off near the vision limits
    if ((wavelength >= 380) && (wavelength < 420)) {
        result *= 0.3f + 0.7f * (wavelength - 380) / (420 - 380);
    } else if ((wavelength >= 420) && (wavelength < 701)) {
        result *= 1;
    } else if ((wavelength >= 701) && (wavelength < 781)) {
        result *= 0.3f + 0.7f * (780 - wavelength) / (780 - 700);
    }
    
    return result;
}

kernel void generateRays(
    device Ray *rays            [[buffer(GeneratorBufferRays)]],
    device uint *rayCount       [[buffer(GeneratorBufferRayCount)]],
    constant Uniforms &uniforms [[buffer(GeneratorBufferUniforms)]],
    device Context &ctx         [[buffer(GeneratorBufferContext)]],
    device lore::Surface<> *surfaces [[buffer(GeneratorBufferLens)]],
    uint2 coordinates           [[thread_position_in_grid]],
    uint2 imageSize             [[threads_per_grid]],
    uint2 threadIndex           [[thread_position_in_threadgroup]],
    uint2 warpIndex             [[threadgroup_position_in_grid]],
    uint2 actualWarpSize        [[threads_per_threadgroup]],
    uint2 warpSize              [[dispatch_threads_per_threadgroup]]
) {
    if (coordinates.x == 0 && coordinates.y == 0) {
        *rayCount = imageSize.x * imageSize.y;
    }
    
    //const int rayIndex = coordinates.x + coordinates.y * imageSize.x;
    
    /// gain a few percents of performance by using block linear indexing for improved coherency
    const int rayIndex = threadIndex.x + threadIndex.y * actualWarpSize.x +
            warpIndex.x * warpSize.x * actualWarpSize.y +
            warpIndex.y * warpSize.y * imageSize.x;
    device Ray &ray = rays[rayIndex];
    
    ray.prng = PrngState(uniforms.frameIndex, rayIndex);
    ray.minDistance = ctx.camera.nearClip;
    ray.maxDistance = ctx.camera.farClip;
    ray.flags = RayFlagsCamera;
    ray.bsdfPdf = INFINITY;
    ray.x = coordinates.x;
    ray.y = coordinates.y;
    
    const float2 jitteredCoordinates = float2(coordinates) + ray.prng.sample2d();
    const float2 uv = (jitteredCoordinates / float2(imageSize) + ctx.camera.shift) * 2.0f - 1.0f;

    lore::Lens<> lens;
    lens.surfaces.m_size = uniforms.numLensSurfaces;
    lens.surfaces.m_data = surfaces;
    
    const float wavelength = lerp(0.38f, 0.75f, ray.prng.sample());
    lore::rt::GeometricalIntersector<float> isect;
    lore::rt::InverseSequentialTrace<float> trace(wavelength);

    device auto &lastSurface = lens.surfaces[lens.surfaces.size() - 2];
    const float3 sensorPos = float3(-uv * uniforms.sensorScale * float2(36, 24)/2, uniforms.focus);
    const float3 sensorAim = float3(lastSurface.aperture * warp::uniformSquareToDisk(ray.prng.sample2d()), -lastSurface.thickness);
    const float3 sensorDir = normalize(sensorAim - sensorPos);
    
    lore::rt::Ray<float> lensRay;
    lensRay.origin = { sensorPos.x, sensorPos.y, sensorPos.z };
    lensRay.direction = { sensorDir.x, sensorDir.y, sensorDir.z };
    
    if (!trace(lensRay, lens, isect)) {
        ray.weight = float3(0);
        return;
    }

    const float3 origin = uniforms.cameraScale * float3(lensRay.origin.x(), lensRay.origin.y(), lensRay.origin.z());
    ray.origin = (ctx.camera.transform * float4(origin, 1)).xyz;
    ray.direction = normalize((ctx.camera.transform * float4(lensRay.direction.x(), lensRay.direction.y(), lensRay.direction.z(), 0)).xyz);
    //const float aspect = float(imageSize.y) / float(imageSize.x);
    //ray.origin = (ctx.camera.transform * float4(0, 0, 0, 1.f)).xyz;
    //ray.direction = normalize((ctx.camera.transform * float4(uv.x, uv.y * aspect, -ctx.camera.focalLength, 0)).xyz);
    
#ifdef SPECTRAL
    ray.weight = float3(1.5, 2, 3) * spectral(wavelength * 1000);
#else
    ray.weight = 1;//float3(M_PI_F) / sensorDir.z;
#endif
}
