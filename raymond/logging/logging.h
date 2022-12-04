#pragma once

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#else
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#endif

#ifndef __OBJC__
extern "C" {
#endif

typedef NS_ENUM(int, LogLevel) {
    LogLevelDebug = 0,
    LogLevelInfo,
    LogLevelWarn,
    LogLevelError
};

struct Logger;
typedef void (*LoggerCallback)(LogLevel level, const char *subsystem, const char *text, void *context);

struct Logger *logger_create(const char *subsystem);
void logger_log(struct Logger *logger, LogLevel level, const char *text);
void logger_subscribe(LoggerCallback callback, void *context);

#ifndef __OBJC__
}
#endif
