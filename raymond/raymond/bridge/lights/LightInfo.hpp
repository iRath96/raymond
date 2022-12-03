#pragma once

#include <bridge/common.hpp>

DEVICE_STRUCT(LightInfo) {
    MaterialIndex shaderIndex;
    bool castsShadows;
    bool usesMIS;
};
