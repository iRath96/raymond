#pragma once

#include "common.hpp"

typedef NS_ENUM(uint32_t, SamplingMode) {
    SamplingModeBsdf = 0,
    SamplingModeNee,
    SamplingModeMis,
};

typedef NS_ENUM(uint32_t, Tonemapping) {
    TonemappingLinear = 0,
    TonemappingHable,
    TonemappingAces,
};

typedef NS_ENUM(uint32_t, OutputChannel) {
    OutputChannelImage = 0,
    OutputChannelAlbedo,
    OutputChannelRoughness,
};

typedef NS_ENUM(uint32_t, RussianRoulette) {
    RussianRouletteNone = 0,
    RussianRouletteThroughput,
};


DEVICE_STRUCT(Uniforms) {
    uint32_t numLensSurfaces;
    uint32_t frameIndex;
    uint32_t randomSeed;
    bool accumulate;
    bool lensSpectral;
    float sensorScale;
    float cameraScale;
    float focus;
    float exposure;
    int stopIndex;
    float relativeStop;
    int numApertureBlades;
    SamplingMode samplingMode;
    Tonemapping tonemapping;
    RussianRoulette rr;
    int rrDepth;
    OutputChannel outputChannel;
};
