#pragma once

#include "common.hpp"

typedef NS_ENUM(uint32_t, SamplingMode) {
    SamplingModeBsdf,
    SamplingModeNee,
    SamplingModeMis
};

DEVICE_STRUCT(Uniforms) {
    uint32_t numLensSurfaces;
    uint32_t frameIndex;
    float sensorScale;
    float cameraScale;
    float focus;
    float exposure;
    SamplingMode samplingMode;
};
