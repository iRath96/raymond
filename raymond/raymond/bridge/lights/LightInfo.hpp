#pragma once

typedef struct {
    uint16_t shaderIndex;
    bool castsShadows;
    bool usesMIS;
} DEVICE_STRUCT(LightInfo);
