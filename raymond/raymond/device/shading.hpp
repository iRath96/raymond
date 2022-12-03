#pragma once

#include <bridge/common.hpp>

#ifdef JIT_COMPILED
#define SHADE_STUB ;
#else
#define SHADE_STUB {}
#endif

void shadeLight(MaterialIndex shaderIndex, device Context &ctx, thread ShadingContext &shading) SHADE_STUB
void shadeSurface(MaterialIndex shaderIndex, device Context &ctx, thread ShadingContext &shading) SHADE_STUB

#undef SHADE_STUB

