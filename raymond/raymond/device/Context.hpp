#pragma once

#include <metal_stdlib>
using namespace metal;

#ifndef JIT_COMPILED
#define NUMBER_OF_TEXTURES 1
#endif

#include "../bridge/common.hpp"
#include "../bridge/PerInstanceData.hpp"
#include "../bridge/Camera.hpp"
#include "lights/Lights.hpp"

struct Context {
    device const Vertex *vertices                 [[id(ContextBufferVertices)]];
    device const IndexTriplet *vertexIndices      [[id(ContextBufferVertexIndices)]];
    device const Normal *vertexNormals            [[id(ContextBufferNormals)]];
    device const TexCoord *texcoords              [[id(ContextBufferTexcoords)]];
    device const PerInstanceData *perInstanceData [[id(ContextBufferPerInstanceData)]];
    device const MaterialIndex *materials         [[id(ContextBufferMaterials)]];
    
    Camera camera [[id(ContextBufferCamera)]];
    Lights lights [[id(ContextBufferLights)]];
    array<texture2d<float>, NUMBER_OF_TEXTURES> textures [[id(ContextBufferTextures)]];
};
