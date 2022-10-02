#import <Foundation/Foundation.h>
#import <simd/simd.h>
#include "../../bridge/common.hpp"

float buildLightDistribution(
    float3x3 normalTransform,
    const IndexTriplet *indices,
    const Vertex *vertices,
    const MaterialIndex *materials,
    const bool *materialHasEmission,
    FaceIndex faceCount,
    
    float *output
);
