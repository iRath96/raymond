#pragma once

#include "common.hpp"

DEVICE_STRUCT(Camera) {
    float4x4 transform;
    float nearClip;
    float farClip;
    float focalLength;
    float2 shift;
};
