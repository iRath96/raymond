#include "ShadingContext.hpp"
#include "Context.hpp"

void ShadingContext::build(
    device const Context &ctx,
    device const PerInstanceData &instance,
    Intersection isect,
    thread MaterialIndex &shaderIndex
) {
    const float2 barycentric = isect.coordinates;
    
    const unsigned int faceIndex = instance.faceOffset + isect.primitiveIndex;
    const unsigned int idx0 = instance.vertexOffset + ctx.vertexIndices[faceIndex].x;
    const unsigned int idx1 = instance.vertexOffset + ctx.vertexIndices[faceIndex].y;
    const unsigned int idx2 = instance.vertexOffset + ctx.vertexIndices[faceIndex].z;
    
    float2 Tc = ctx.texcoords[idx2];
    float2x2 T;
    T.columns[0] = ctx.texcoords[idx0] - Tc;
    T.columns[1] = ctx.texcoords[idx1] - Tc;
    uv = float3(T * barycentric + Tc, 0);
    
    float3 Pc = ctx.vertices[idx2];
    float2x3 P;
    P.columns[0] = ctx.vertices[idx0] - Pc;
    P.columns[1] = ctx.vertices[idx1] - Pc;
    trueNormal = normalize(instance.normalTransform * cross(P.columns[0], P.columns[1]));
    
    float3 localP = P * barycentric + Pc;
    object = localP;
    generated = safe_divide(localP - instance.boundsMin, instance.boundsSize, 0.5f);
    position = (instance.pointTransform * float4(localP, 1)).xyz;
    
    normal = instance.normalTransform * interpolate(
        float3(ctx.vertexNormals[idx0]),
        float3(ctx.vertexNormals[idx1]),
        float3(ctx.vertexNormals[idx2]),
        barycentric);
    normal = normalize(normal);
    
    tu = normalize(instance.normalTransform * (P * float2(T[1][1], -T[0][1])));
    tv = normalize(instance.normalTransform * (P * float2(-T[1][0], T[0][0])));

    distance = isect.distance;

    shaderIndex = ctx.materials[faceIndex];
}
