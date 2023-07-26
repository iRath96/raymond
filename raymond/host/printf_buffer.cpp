extern "C" {
#include "printf_buffer.h"
}

#include <logging/logging.h>
#include <bridge/printf.hpp>

#include <iostream>

template<typename T>
T read(const char *&src) {
    T *t = (T *)src;
    src += sizeof(T);
    return *t;
}

static Logger *logger = logger_create("device");

void execute_printf_buffer(const char *data, uint32_t index) {
    static char buffer[8192];
    
    const char *end = data + index;
    while (data < end) {
        const char *format = data;
        if (*format == 0) {
            logger_log(logger, LogLevelWarn, "printf: buffer overflow");
            break;
        }

        while (*data++); // skip format string
        auto nargs = read<int>(data);
        
        char vargs[8*nargs];
        
        char *p = vargs;
        while (nargs --> 0) {
            auto tag = read<printf_tag>(data);
            switch (tag) {
            case PRINTF_TAG_FLOAT: *(double *)p = read<float>(data); break;
            case PRINTF_TAG_INT: *(int64_t *)p = read<int64_t>(data); break;
            case PRINTF_TAG_STRING: {
                *(const char **)p = data;
                while (*data++);
                break;
            }
            default:
                logger_log(logger, LogLevelWarn, "printf: unexpected tag");
            }
            p += 8;
        }
        
        vsnprintf(buffer, sizeof(buffer), format, (va_list)vargs);
        logger_log(logger, LogLevelInfo, buffer);
    }
}
