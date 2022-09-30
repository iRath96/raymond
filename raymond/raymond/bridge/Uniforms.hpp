#pragma once

typedef NS_ENUM(NSInteger, SamplingMode) {
    SamplingModeBsdf,
    SamplingModeNee,
    SamplingModeMis
};

typedef struct {
    uint32_t frameIndex;
    float4x4 projectionMatrix;
    SamplingMode samplingMode;
} DEVICE_STRUCT(Uniforms);
