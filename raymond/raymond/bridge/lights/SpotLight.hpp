#pragma once

typedef struct {
    DEVICE_STRUCT(LightInfo) info;
    
    float3 location;
    float3 direction;
    float radius;
    float3 color;
    float spotSize;
    float spotBlend;
    
#ifdef __METAL_VERSION__
    LightSample sample(device Context &ctx, thread ThreadContext &tctx, thread PRNGState &prng) const device;
#endif
} DEVICE_STRUCT(SpotLight);
