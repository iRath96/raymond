#pragma once

struct BsdfSample {
    float pdf;
    float3 wi;
    float3 weight;
    RayFlags flags;
    
    static BsdfSample invalid() {
        BsdfSample result;
        result.pdf = 0;
        result.weight = 0;
        result.flags = RayFlags(0);
        return result;
    }
};
