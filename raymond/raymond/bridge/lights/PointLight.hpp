#pragma once

typedef struct {
    DEVICE_STRUCT(LightInfo) info;
    
    float3 location;
    float radius;
    float3 color;

#ifdef __METAL_VERSION__
    LightSample sample(device Context &ctx, thread ThreadContext &tctx, thread PRNGState &prng) const device;
#endif
} DEVICE_STRUCT(PointLight);
