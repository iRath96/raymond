#pragma once

#include "context.hpp"
#include "nodes.hpp"
#include "ShaderTypes.h"

#include <metal_stdlib>
using namespace metal;

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
    if (isect.distance <= 0.0f)
        return;
    
    const device PerInstanceData &instance = perInstanceData[isect.instanceIndex];
    
    int shaderIndex;
    
    ThreadContext tctx;
    tctx.wo = -ray.direction;
    
    {
        const unsigned int faceIndex = instance.faceOffset + isect.primitiveIndex;
        const unsigned int idx0 = instance.vertexOffset + vertexIndices[3 * faceIndex + 0];
        const unsigned int idx1 = instance.vertexOffset + vertexIndices[3 * faceIndex + 1];
        const unsigned int idx2 = instance.vertexOffset + vertexIndices[3 * faceIndex + 2];
        
        /*float3 p = interpolate(
            vertexToFloat3(vertices[idx0]),
            vertexToFloat3(vertices[idx1]),
            vertexToFloat3(vertices[idx2]),
            isect.coordinates);*/
        
        tctx.uv = interpolate(
            texcoords[idx0],
            texcoords[idx1],
            texcoords[idx2],
            isect.coordinates);
        
        tctx.normal = interpolate(
            vertexToFloat3(vertexNormals[idx0]),
            vertexToFloat3(vertexNormals[idx1]),
            vertexToFloat3(vertexNormals[idx2]),
            isect.coordinates);
        
        shaderIndex = materials[faceIndex];
    }
    
    shaders[shaderIndex](ctx, tctx);
    
    uint2 coordinates = uint2(ray.x, ray.y);
    image.write(
        //image.read(coordinates) + float4(isect.distance, 0, 0, 1),
        image.read(coordinates) + float4(
            //tctx.normal,
            tctx.material.diffuse.diffuseWeight,
            1),
        coordinates
    );
    return;
}
