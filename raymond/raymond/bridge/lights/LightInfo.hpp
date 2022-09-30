#pragma once

#include "../common.hpp"

DEVICE_STRUCT(LightInfo) {
    uint16_t shaderIndex;
    bool castsShadows;
    bool usesMIS;
};
