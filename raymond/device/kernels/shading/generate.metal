#include <bridge/common.hpp>
#include <bridge/Ray.hpp>
#include <bridge/ResourceIds.hpp>
#include <bridge/PrngState.hpp>
#include <bridge/Uniforms.hpp>
#include <device/Context.hpp>
#include <device/utils/color.hpp>
#include <device/printf.hpp>

#include <lore/lens/Lens.h>
#include <lore/rt/GeometricalIntersector.h>
#include <lore/rt/SequentialTrace.h>

template<typename Float>
struct CustomTrace {
    Float wavelength;
    constant Uniforms &uniforms;

    CustomTrace(MTL_THREAD const Float &wavelength, constant Uniforms &uniforms)
        : wavelength(wavelength), uniforms(uniforms) {}

    bool testAperture(float2 pos) const {
        const float phi = atan2(pos.y, pos.x) / (2 * M_PI_F) + (1 - uniforms.relativeStop) / 4;
        const float phiL = fmod((phi + 1) * uniforms.numApertureBlades, 1) - 0.5;
        const float r = length(pos);
        
        const float x = M_PI_F / uniforms.numApertureBlades;
        const float norm = sqrt(tan(x) / x); // @todo compute this on host
        
        const float coolR = r * lerp(norm * cos(2 * phiL * x), float(1), sqr(uniforms.relativeStop));
        return coolR <= uniforms.relativeStop;
    }

    template<typename Intersector>
    bool operator()(
        MTL_THREAD lore::rt::Ray<Float> &ray,
        MTL_THREAD const lore::Lens<Float> &lens,
        MTL_THREAD const Intersector &intersector
    ) const {
        int surfaceIndex = lens.surfaces.size() - 1;
        Float n2 = lens.surfaces[surfaceIndex].ior(wavelength);
        for (; surfaceIndex > 0; surfaceIndex--) {
            MTL_DEVICE auto &surface = lens.surfaces[surfaceIndex];
            ray.origin.z() += surface.thickness;

            if (!lore::rt::TraceUtils<Float>::propagate(ray, surface, intersector)) {
                return false;
            }
            
            if (surfaceIndex == uniforms.stopIndex) {
                const float2 pos = float2(ray.origin.x(), ray.origin.y()) / surface.aperture;
                if (!testAperture(pos)) {
                    return false;
                }
            }

            const lore::Vector3<Float> normal = lore::rt::TraceUtils<Float>::normal(ray, surface);
            const Float n1 = lens.surfaces[surfaceIndex - 1].ior(wavelength);
            if (!lore::refract(ray.direction, normal, ray.direction, n2 / n1)) {
                return false;
            }

            n2 = n1;
        }

        return true;
    }
};

kernel void generateRays(
    device Ray *rays             [[buffer(GeneratorBufferRays)]],
    device atomic_uint *rayCount [[buffer(GeneratorBufferRayCount)]],
    texture2d<float, access::write> image [[texture(0)]],
    constant Uniforms &uniforms  [[buffer(GeneratorBufferUniforms)]],
    const device Context &ctx    [[buffer(GeneratorBufferContext)]],
    const device lore::Surface<> *surfaces [[buffer(GeneratorBufferLens)]],
    const uint2 coordinates      [[thread_position_in_grid]],
    const uint2 imageSize        [[threads_per_grid]],
    const uint2 threadIndex      [[thread_position_in_threadgroup]],
    const uint2 warpIndex        [[threadgroup_position_in_grid]],
    const uint2 actualWarpSize   [[threads_per_threadgroup]],
    const uint2 warpSize         [[dispatch_threads_per_threadgroup]]
) {
    /// gain a few percents of performance by using block linear indexing for improved coherency
    const int rayIndex = threadIndex.x + threadIndex.y * actualWarpSize.x +
        warpIndex.x * warpSize.x * actualWarpSize.y +
        warpIndex.y * warpSize.y * imageSize.x;
    
    Ray ray;
    ray.prng = PrngState(uniforms.randomSeed, rayIndex);
    ray.minDistance = ctx.camera.nearClip;
    ray.maxDistance = ctx.camera.farClip;
    ray.flags = RayFlagsCamera;
    ray.depth = 0;
    ray.bsdfPdf = INFINITY;
    ray.x = coordinates.x;
    ray.y = coordinates.y;

    if (!uniforms.accumulate) {
        // clear image if accumulation is not desired
        image.write(float4(0, 0, 0, 0), coordinates);
    }
    
    const float2 jitteredCoordinates = float2(coordinates) + ray.prng.sample2d();
    const float2 uv = float2(+1, -1) * ((jitteredCoordinates / float2(imageSize) + ctx.camera.shift) * 2.0f - 1.0f);
    const float aspect = float(imageSize.y) / float(imageSize.x);

    if (uniforms.numLensSurfaces == 0) {
        if (coordinates.x == 0 && coordinates.y == 0) {
            atomic_store_explicit(rayCount, imageSize.x * imageSize.y, memory_order_relaxed);
        }
        
        ray.origin = (ctx.camera.transform * float4(0, 0, 0, 1.f)).xyz;
        ray.direction = normalize((ctx.camera.transform * float4(uv.x, uv.y * aspect, -ctx.camera.focalLength, 0)).xyz);
        ray.weight = 1;
        
        rays[rayIndex] = ray;
        return;
    }
    
    lore::Lens<> lens;
    lens.surfaces.m_size = uniforms.numLensSurfaces;
    lens.surfaces.m_data = const_cast<device lore::Surface<> *>(surfaces);
    
    const float wavelength = lerp(0.38f, 0.78f, ray.prng.sample());
    const float wavelength_ipdf_nm = 400;
    
    lore::rt::GeometricalIntersector<float> isect;
    CustomTrace<float> trace(wavelength, uniforms);

    device auto &lastSurface = lens.surfaces[lens.surfaces.size() - 2];
    const float3 sensorPos = float3(-uv * uniforms.sensorScale * float2(36, 36 * aspect) / 2, uniforms.focus);
    const float3 sensorAim = float3(lastSurface.aperture * warp::uniformSquareToDisk(ray.prng.sample2d()), -lastSurface.thickness);
    const float3 sensorDirU = sensorAim - sensorPos;
    const float sensorDirInvDistSqr = 1 / length_squared(sensorDirU);
    const float3 sensorDir = sensorDirU * sqrt(sensorDirInvDistSqr);
    const float sensorDirInvPdf = abs(sensorDir.z) * sensorDirInvDistSqr * (M_PI_F * sqr(lastSurface.aperture));
    
    lore::rt::Ray<float> lensRay;
    lensRay.origin = { sensorPos.x, sensorPos.y, sensorPos.z };
    lensRay.direction = { sensorDir.x, sensorDir.y, sensorDir.z };
    
    if (!trace(lensRay, lens, isect)) {
        // do not commit ray
        return;
    }

    const float3 origin = uniforms.cameraScale * float3(lensRay.origin.x(), lensRay.origin.y(), lensRay.origin.z());
    ray.origin = (ctx.camera.transform * float4(origin, 1)).xyz;
    ray.direction = normalize((ctx.camera.transform * float4(lensRay.direction.x(), lensRay.direction.y(), lensRay.direction.z(), 0)).xyz);
    
    const float sensorW = abs(sensorDir.z);
    if (uniforms.lensSpectral) {
        ray.weight = sensorW * sensorDirInvPdf * xyz_to_rgb(wavelength_to_xyz(1000 * wavelength)) * cie_integral_norm_rgb * wavelength_ipdf_nm;
    } else {
        ray.weight = sensorW * sensorDirInvPdf;
    }
    
    const uint compactedRayIndex = atomic_fetch_add_explicit(rayCount, 1, memory_order_relaxed);
    rays[compactedRayIndex] = ray;
}
