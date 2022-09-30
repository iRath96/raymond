#pragma once

typedef struct {
    DEVICE_STRUCT(LightInfo) info;
    
    float3x4 transform;
    float3 color;
    bool isCircular;
    
#ifdef __METAL_VERSION__
    LightSample sample(device Context &ctx, thread ThreadContext &tctx, thread PRNGState &prng) const device;
#endif
} DEVICE_STRUCT(AreaLight);
