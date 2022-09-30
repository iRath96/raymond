#pragma once

#include "common.hpp"

typedef NS_ENUM(NSInteger, SamplingMode) {
    SamplingModeBsdf,
    SamplingModeNee,
    SamplingModeMis
};

DEVICE_STRUCT(Uniforms) {
    uint32_t frameIndex;
    float4x4 projectionMatrix;
    SamplingMode samplingMode;
};
