#include <metal_stdlib>
#include <simd/simd.h>

#include "gpu/random.hpp"

#import "ShaderTypes.h"

using namespace metal;

float sample1d(device PRNGState &prng) {
    return sample_tea_float32(prng.seed, prng.index++);
}

float2 sample2d(device PRNGState &prng) {
    return float2(
        sample_tea_float32(prng.seed, prng.index++),
        sample_tea_float32(prng.seed, prng.index++)
    );
}

float3 sample3d(device PRNGState &prng) {
    return float3(
        sample_tea_float32(prng.seed, prng.index++),
        sample_tea_float32(prng.seed, prng.index++),
        sample_tea_float32(prng.seed, prng.index++)
    );
}

float3 sample3d(thread PRNGState &prng) {
    return float3(
        sample_tea_float32(prng.seed, prng.index++),
        sample_tea_float32(prng.seed, prng.index++),
        sample_tea_float32(prng.seed, prng.index++)
    );
}

// MARK: - ray tracing

float3 interpolate(
    const float3 a,
    const float3 b,
    const float3 c,
    float2 barycentric
) {
    float u = barycentric.x;
    float v = barycentric.y;
    float w = 1.0f - u - v;
    
    return float3(a * u + b * v + c * w);
}

float3 vertexToFloat3(Vertex v) { return float3(v.x, v.y, v.z); }

struct SurfaceInfo {
    float3 point;
    float3 normal;
    uint32_t material;
};

kernel void background(
    texture2d<float, access::write> image [[texture(0)]],
    uint2 coordinates [[thread_position_in_grid]],
    uint2 size [[threads_per_grid]]
) {
    image.write(float4(0, 0, 0, 1), coordinates);
}

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
    ray.base.origin = (float4(0, 0, 0, 1.f) * uniforms.projectionMatrix).xyz;
    ray.base.direction = normalize((float4(aspect * uv.x, uv.y, -2.5f, 0) * uniforms.projectionMatrix).xyz);
    ray.base.minDistance = 0.0f;
    ray.base.maxDistance = INFINITY;
    ray.weight = float3(1, 1, 1);
    
    ray.bsdfPdf = INFINITY;
    
    if (coordinates.x == 0 && coordinates.y == 0) {
        *rayCount = imageSize.x * imageSize.y;
    }
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
    
    // geometry buffers
    device const Vertex *vertices [[buffer(ShadingBufferVertices)]],
    device const VertexIndex *vertexIndices [[buffer(ShadingBufferVertexIndices)]],
    device const Vertex *vertexNormals [[buffer(ShadingBufferNormals)]],
    device const float2 *texcoords [[buffer(ShadingBufferTexcoords)]],
    
    // scene buffers
    constant Uniforms &uniforms [[buffer(ShadingBufferUniforms)]],
    device const PerInstanceData *perInstanceData [[buffer(ShadingBufferPerInstanceData)]],
    device const MaterialIndex *materials [[buffer(ShadingBufferMaterials)]],
    
    uint rayIndex [[thread_position_in_grid]]
) {
    if (rayIndex >= currentRayCount)
        return;
    
    device Ray &ray = rays[rayIndex];
    constant Intersection &isect = intersections[rayIndex];
    if (isect.distance <= 0.0f)
        return;
    
    const device PerInstanceData &instance = perInstanceData[isect.instanceIndex];
    SurfaceInfo surf;
    
    {
        const unsigned int faceIndex = instance.faceOffset + isect.primitiveIndex;
        const unsigned int idx0 = instance.vertexOffset + vertexIndices[3 * faceIndex + 0];
        const unsigned int idx1 = instance.vertexOffset + vertexIndices[3 * faceIndex + 1];
        const unsigned int idx2 = instance.vertexOffset + vertexIndices[3 * faceIndex + 2];
        
        surf.point = interpolate(
            vertexToFloat3(vertices[idx0]),
            vertexToFloat3(vertices[idx1]),
            vertexToFloat3(vertices[idx2]),
            isect.coordinates);
        
        surf.normal = interpolate(
            vertexToFloat3(vertexNormals[idx0]),
            vertexToFloat3(vertexNormals[idx1]),
            vertexToFloat3(vertexNormals[idx2]),
            isect.coordinates);
        
        surf.material = materials[faceIndex];
    }
    
    uint2 coordinates = uint2(ray.x, ray.y);
    image.write(
        //image.read(coordinates) + float4(isect.distance, 0, 0, 1),
        image.read(coordinates) + float4(
            surf.normal,
            1),
        coordinates
    );
    return;
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
    if (!(color.x >= 0)) color = float4(1, 0, 1, 1);
    if (!(color.y >= 0)) color = float4(1, 0, 1, 1);
    if (!(color.z >= 0)) color = float4(1, 0, 1, 1);
    return color;// + float4(1, 1, 1, 0);
}
