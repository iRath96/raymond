#pragma once

#include "../../bridge/common.hpp"
#include "../../bridge/lights/LightInfo.hpp"

struct LightSample {
    int shaderIndex;
    bool canBeHit;
    bool castsShadows;
    float3 weight;
    float pdf;
    float3 direction;
    float distance;
    
    LightSample() {}
    LightSample(LightInfo info) {
        shaderIndex = info.shaderIndex;
        canBeHit = info.usesMIS;
        castsShadows = info.castsShadows;
    }
    
    static LightSample invalid() {
        LightSample result;
        result.pdf = 0;
        result.weight = 0;
        return result;
    }
};
