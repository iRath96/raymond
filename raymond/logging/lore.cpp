#include <lore/logging.h>
#include <logging/logging.h>

#include <sstream>
#include <ostream>

Logger *logger = logger_create("lore");

struct LoggingStringbuf : public std::stringbuf {
    LogLevel level;
    LoggingStringbuf(LogLevel level)
    : level(level) {}
    
    virtual int sync() {
        logger_log(logger, level, str().c_str());
        this->str("");
        return 0;
    }
};

namespace lore {

struct ConsoleLogger : public Logger {
    struct Channel {
        std::unique_ptr<LoggingStringbuf> stringbuf;
        std::ostream stream;
        
        Channel(::LogLevel level)
        : stringbuf(std::make_unique<LoggingStringbuf>(level)),
        stream(stringbuf.get()) {
            
        }
    };
    
    Channel debug { LogLevelDebug };
    Channel info { LogLevelInfo };
    Channel warning { LogLevelWarn };
    Channel error { LogLevelError };
    
    virtual std::ostream &log(Logger::Level level) override {
        switch (level) {
            case Logger::LOG_DEBUG:   return debug.stream;
            case Logger::LOG_INFO:    return info.stream;
            case Logger::LOG_WARNING: return warning.stream;
            case Logger::LOG_ERROR:   return error.stream;
        }
        return error.stream;
    }
};

std::shared_ptr<Logger> Logger::shared = std::make_shared<ConsoleLogger>();

}
