#pragma once

typedef unsigned char printf_tag;

enum {
    PrintfBufferConstantIndex = 2022
};

enum {
    PRINTF_TAG_UNKNOWN = 0,
    PRINTF_TAG_FLOAT,
    PRINTF_TAG_INT,
    PRINTF_TAG_STRING
};
