#pragma once

#include "../common.hpp"

DEVICE_STRUCT(LightInfo) {
    MaterialIndex shaderIndex;
    bool castsShadows;
    bool usesMIS;
};
