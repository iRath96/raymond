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
    
    // awesome
    visible_function_table<
        void (Context, thread ThreadContext &)
    > shaders [[buffer(ShadingBufferFunctionTable)]],
    device Context &ctx [[buffer(ShadingBufferContext)]],
    
    uint rayIndex [[thread_position_in_grid]]
) {
    if (rayIndex >= currentRayCount)
        return;
    
    device Ray &ray = rays[rayIndex];
    constant Intersection &isect = intersections[rayIndex];
    if (isect.distance <= 0.0f) {
        // miss
        float envmapCos = dot(ray.direction, normalize(float3(1.192f, -1, 0.42f)));
        envmapCos = select(1, 0, envmapCos < 0.9);
        float3 envmap = 10 * float3(1.538, 1.351, 1.257) * envmapCos + 0.05f;
            
        uint2 coordinates = uint2(ray.x, ray.y);
        image.write(
            //image.read(coordinates) + float4(isect.distance, 0, 0, 1),
            image.read(coordinates) + float4(
                envmap * ray.weight,
                1),
            coordinates
        );
        
        return;
    }
    
    const device PerInstanceData &instance = perInstanceData[isect.instanceIndex];
    
    int shaderIndex;
    
    ThreadContext tctx;
    tctx.rnd = sample3d(ray.prng);
    tctx.wo = -ray.direction;
    
    float3 ipoint;
    {
        const unsigned int faceIndex = instance.faceOffset + isect.primitiveIndex;
        const unsigned int idx0 = instance.vertexOffset + vertexIndices[3 * faceIndex + 0];
        const unsigned int idx1 = instance.vertexOffset + vertexIndices[3 * faceIndex + 1];
        const unsigned int idx2 = instance.vertexOffset + vertexIndices[3 * faceIndex + 2];
        
        // @todo: is this numerically stable enough?
        //ipoint = ray.origin + ray.direction * isect.distance;
        
        float2 Tc = texcoords[idx2];
        float2x2 T;
        T.columns[0] = texcoords[idx0] - Tc;
        T.columns[1] = texcoords[idx1] - Tc;
        tctx.uv = T * isect.coordinates + Tc;
        
        float3 Pc = vertexToFloat3(vertices[idx2]);
        float2x3 P;
        P.columns[0] = vertexToFloat3(vertices[idx0]) - Pc;
        P.columns[1] = vertexToFloat3(vertices[idx1]) - Pc;
        ipoint = (instance.pointTransform * float4(P * isect.coordinates + Pc, 1)).xyz;
        
        tctx.normal = instance.normalTransform * interpolate(
            vertexToFloat3(vertexNormals[idx0]),
            vertexToFloat3(vertexNormals[idx1]),
            vertexToFloat3(vertexNormals[idx2]),
            isect.coordinates);
        tctx.normal = normalize(tctx.normal);
        
        tctx.tu = normalize(instance.normalTransform * (P * float2(T[1][1], -T[0][1])));
        tctx.tv = normalize(instance.normalTransform * (P * float2(T[1][0], -T[0][0])));

        shaderIndex = materials[faceIndex];
    }
    
    /*{
        uint2 coordinates = uint2(ray.x, ray.y);
        image.write(
            image.read(coordinates) + float4(
                ipoint,//float3(pow(max(dot(-ray.direction, tctx.normal), 0.f), 100.f)),
                1),
            coordinates
        );
        return;
    }*/
    
    shaders[shaderIndex](ctx, tctx);
    
    if (mean(tctx.material.emission) > 0) {
        uint2 coordinates = uint2(ray.x, ray.y);
        image.write(
            image.read(coordinates) + float4(
                ray.weight + tctx.material.emission,
                1),
            coordinates
        );
    }
    
    float3x3 worldToShadingFrame;
    if (all(tctx.material.normal == 0)) {
        worldToShadingFrame = buildOrthonormalBasis(tctx.normal);
    } else {
        float3 normal = ensure_valid_reflection(tctx.normal, tctx.wo, tctx.material.normal);
        worldToShadingFrame = buildOrthonormalBasis(normal);
    }
    
    float3 weight = ray.weight;
    float3 direction;
    
    do {
        const float3 transformedWo = tctx.wo * worldToShadingFrame;
        const float woDotGeoN = dot(tctx.wo, tctx.normal);
        const float woDotShN = transformedWo.z;
        if (woDotShN * woDotGeoN < 0) {
            weight = 0;
            break;
        }
        
        auto sample = tctx.material.sample(tctx.rnd, transformedWo);
        weight *= sample.weight;
        direction = sample.wi * transpose(worldToShadingFrame);
        
        const float wiDotGeoN = dot(direction, tctx.normal);
        const float wiDotShN = sample.wi.z;
        if (wiDotShN * wiDotGeoN < 0) {
            weight = 0;
            break;
        }
    } while (false);
    
    if (mean(weight) > 0) {
        uint nextRayIndex = atomic_fetch_add_explicit(&nextRayCount, 1, memory_order_relaxed);
        device Ray &nextRay = nextRays[nextRayIndex];
        nextRay.origin = ipoint;
        nextRay.direction = direction;
        nextRay.minDistance = eps;
        nextRay.maxDistance = INFINITY;
        nextRay.weight = weight;
        nextRay.x = ray.x;
        nextRay.y = ray.y;
        nextRay.prng = ray.prng;
    }
    
    return;
}
