#include "../../../bridge/common.hpp"
#include "../../../bridge/Ray.hpp"
#include "../../../bridge/Uniforms.hpp"
#include "../../../bridge/ResourceIds.hpp"
#include "../../../bridge/PrngState.hpp"

kernel void generateRays(
    device Ray *rays            [[buffer(GeneratorBufferRays)]],
    device uint *rayCount       [[buffer(GeneratorBufferRayCount)]],
    constant Uniforms &uniforms [[buffer(GeneratorBufferUniforms)]],
    uint2 coordinates           [[thread_position_in_grid]],
    uint2 imageSize             [[threads_per_grid]],
    uint2 threadIndex           [[thread_position_in_threadgroup]],
    uint2 warpIndex             [[threadgroup_position_in_grid]],
    uint2 actualWarpSize        [[threads_per_threadgroup]],
    uint2 warpSize              [[dispatch_threads_per_threadgroup]]
) {
    //const int rayIndex = coordinates.x + coordinates.y * imageSize.x;
    
    /// gain a few percents of performance by using block linear indexing for improved coherency
    const int rayIndex = threadIndex.x + threadIndex.y * actualWarpSize.x +
            warpIndex.x * warpSize.x * actualWarpSize.y +
            warpIndex.y * warpSize.y * imageSize.x;
    device Ray &ray = rays[rayIndex];
    
    ray.prng = PrngState(uniforms.frameIndex, rayIndex);
    ray.x = coordinates.x;
    ray.y = coordinates.y;
    
    const float2 jitteredCoordinates = float2(coordinates) + ray.prng.sample2d();
    const float2 uv = jitteredCoordinates / float2(imageSize) * 2.0f - 1.0f;

    const float aspect = float(imageSize.x) / float(imageSize.y);
    ray.origin = (uniforms.projectionMatrix * float4(0, 0, 0, 1.f)).xyz;
    ray.direction = normalize((uniforms.projectionMatrix * float4(aspect * uv.x, uv.y, -2.5f, 0)).xyz);
    ray.minDistance = 0.0f;
    ray.maxDistance = INFINITY;
    ray.weight = float3(1, 1, 1);
    ray.flags = RayFlagsCamera;
    
    ray.bsdfPdf = INFINITY;
    
    if (coordinates.x == 0 && coordinates.y == 0) {
        *rayCount = imageSize.x * imageSize.y;
    }
}
