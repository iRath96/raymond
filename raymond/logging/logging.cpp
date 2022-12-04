#include "logging.h"

#include <iostream>
#include <string>
#include <vector>

struct Logger {
    std::string name;
};

void log_to_console(LogLevel level, const char *subsystem, const char *text, void *callback) {
    std::ostream &os = level >= LogLevelWarn ? std::cerr : std::cout;
    char code = "DIWE"[level];
    os << "[" << code << "][" << subsystem << "] " << text << std::endl;
}

std::vector<std::pair<LoggerCallback, void *>> *g_callbacks;

decltype(*g_callbacks) &callbacks() {
    if (!g_callbacks) {
        g_callbacks = new std::vector<std::pair<LoggerCallback, void *>>;
        g_callbacks->push_back({ log_to_console, nullptr });
    }
    return *g_callbacks;
}

struct Logger *logger_create(const char *subsystem) {
    Logger *logger = new Logger();
    logger->name = subsystem;
    return logger;
}

void logger_log(struct Logger *logger, LogLevel level, const char *text) {
    for (const auto &callback : callbacks()) {
        callback.first(level, logger->name.c_str(), text, callback.second);
    }
}

void logger_subscribe(LoggerCallback callback, void *context) {
    callbacks().push_back({ callback, context });
}
