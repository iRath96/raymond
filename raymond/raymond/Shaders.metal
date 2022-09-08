#include <metal_stdlib>
#include <simd/simd.h>

#include "gpu/random.hpp"
#include "gpu/context.hpp"
#include "gpu/nodes.hpp"
#include "gpu/shading.hpp"

#import "gpu/ShaderTypes.h"

using namespace metal;

// MARK: - ray tracing

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
    
    ray.prng.seed = sample_tea_32(uniforms.frameIndex, rayIndex);
    ray.prng.index = 0;
    ray.x = coordinates.x;
    ray.y = coordinates.y;
    
    const float2 jitteredCoordinates = float2(coordinates) + sample2d(ray.prng);
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

kernel void makeIndirectDispatchArguments(
    device uint *rayCount [[buffer(0)]],
    device MTLDispatchThreadgroupsIndirectArguments *dispatchArg [[buffer(1)]]
) {
    dispatchArg->threadgroupsPerGrid[0] = (*rayCount + 63) / 64;
    dispatchArg->threadgroupsPerGrid[1] = 1;
    dispatchArg->threadgroupsPerGrid[2] = 1;
}

// MARK: - blit shader

struct BlitVertexOut {
    float4 pos [[position]];
    float2 coords;
};

constant constexpr static const float4 fullscreenTrianglePositions[3] {
    { -1.0, -1.0, 0.0, 1.0 },
    {  3.0, -1.0, 0.0, 1.0 },
    { -1.0,  3.0, 0.0, 1.0 }
};

vertex BlitVertexOut blitVertex(
    uint vertexIndex [[vertex_id]]
) {
    BlitVertexOut out;
    out.pos = fullscreenTrianglePositions[vertexIndex];
    out.coords = out.pos.xy * 0.5 + 0.5;
    return out;
}

fragment float4 blitFragment(
    BlitVertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(0)]],
    texture2d<float> image [[texture(0)]]
) {
    constexpr sampler linearSampler(coord::normalized, filter::nearest);
    float4 color = image.sample(linearSampler, in.coords) / (uniforms.frameIndex + 1);
    if (any(isnan(color))) color = float4(1, 0, 1, 1);
    return color;
}
