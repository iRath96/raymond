#include "distribution.h"

simd_float3 simd_make_float3(Vertex v) {
    return simd_make_float3(v.x, v.y, v.z);
}

float buildLightDistribution(
    float3x3 normalTransform,
    const IndexTriplet *indices,
    const Vertex *vertices,
    const MaterialIndex *materials,
    const bool *materialHasEmission,
    FaceIndex faceCount,
    
    float *output
) {
    double accumulatedArea = 0;
    
    for (FaceIndex i = 0; i < faceCount; i++) {
        IndexTriplet idx = indices[i];
        float3 v0 = simd_make_float3(vertices[idx.x]);
        float3 v1 = simd_make_float3(vertices[idx.y]);
        float3 v2 = simd_make_float3(vertices[idx.z]);
        
        float3 tn = simd_cross(
            matrix_multiply(normalTransform, v2 - v0),
            matrix_multiply(normalTransform, v2 - v1)
        );
        float area = simd_length(tn) / 2;
        
        output[i] = (accumulatedArea += area);
    }
    
    for (FaceIndex i = 0; i < faceCount; i++) {
        output[i] /= accumulatedArea;
    }
    
    return accumulatedArea;
}
