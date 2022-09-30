#pragma once

#include <metal_stdlib>
using namespace metal;

#ifndef JIT_COMPILED
#define NUMBER_OF_TEXTURES 1
#endif

#include "../bridge/common.hpp"
#include "../bridge/PerInstanceData.hpp"
#include "lights/Lights.hpp"

struct Context {
    device const Vertex *vertices                 [[id(ContextBufferVertices)]];
    device const VertexIndex *vertexIndices       [[id(ContextBufferVertexIndices)]];
    device const Vertex *vertexNormals            [[id(ContextBufferNormals)]];
    device const float2 *texcoords                [[id(ContextBufferTexcoords)]];
    device const PerInstanceData *perInstanceData [[id(ContextBufferPerInstanceData)]];
    device const MaterialIndex *materials         [[id(ContextBufferMaterials)]];
    
    Lights lights [[id(ContextBufferLights)]];
    array<texture2d<float>, NUMBER_OF_TEXTURES> textures [[id(ContextBufferTextures)]];
};
