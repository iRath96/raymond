#pragma once

#include "../bridge/common.hpp"

#ifdef JIT_COMPILED
#define SHADE_STUB ;
#else
#define SHADE_STUB {}
#endif

void shadeLight(int shaderIndex, device Context &ctx, thread ShadingContext &shading) SHADE_STUB
void shadeSurface(int shaderIndex, device Context &ctx, thread ShadingContext &shading) SHADE_STUB

#undef SHADE_STUB

