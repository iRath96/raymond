#include <lore/logging.h>
#include "imgui.h"

#include <sstream>
#include <iostream>
#include <vector>

struct Logger {
    enum LogLevel {
        LOG_DEBUG = 0,
        LOG_INFO,
        LOG_WARN,
        LOG_ERROR,
        
        LOG_COUNT
    };
    
    struct Item {
        std::string text;
        LogLevel level;
        
        Item(LogLevel level, const std::string &text)
        : level(level), text(text) {}
    };
    
    std::vector<ImVec4> logColors;
    ImGuiTextFilter     filter;
    std::vector<Item>   items;
    bool                isOpen = true;
    bool                autoScroll = true;

    Logger() {
        autoScroll = true;
        clear();
        
        items.push_back(Item(LOG_DEBUG, "testing"));
        items.push_back(Item(LOG_INFO,  "testing"));
        items.push_back(Item(LOG_WARN,  "testing"));
        items.push_back(Item(LOG_ERROR, "testing"));
        
        logColors.resize(LOG_COUNT);
        logColors[LOG_DEBUG] = ImVec4(0.5f, 0.5f, 0.5f, 1);
        logColors[LOG_INFO ] = ImVec4(0.9f, 0.9f, 0.9f, 1);
        logColors[LOG_WARN ] = ImVec4(0.9f, 0.5f, 0.2f, 1);
        logColors[LOG_ERROR] = ImVec4(1.0f, 0.1f, 0.1f, 1);
    }

    void clear() {
        items.clear();
    }

    void addLog(LogLevel level, const std::string &text) {
        items.push_back(Item(level, text));
    }

    void draw() {
        if (!isOpen) {
            return;
        }
        
        if (!ImGui::Begin("Log", &isOpen)) {
            ImGui::End();
            return;
        }

        if (ImGui::BeginPopup("Options")) {
            ImGui::Checkbox("Auto-scroll", &autoScroll);
            ImGui::EndPopup();
        }

        // Main window
        if (ImGui::Button("Options"))
            ImGui::OpenPopup("Options");
        ImGui::SameLine();
        const bool shouldClear = ImGui::Button("Clear");
        ImGui::SameLine();
        const bool shouldCopy = ImGui::Button("Copy");
        ImGui::SameLine();
        filter.Draw("Filter", -100.0f);

        ImGui::Separator();

        if (ImGui::BeginChild("scrolling", ImVec2(0, 0), false, ImGuiWindowFlags_HorizontalScrollbar)) {
            if (shouldClear)
                clear();
            if (shouldCopy)
                ImGui::LogToClipboard();

            ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(0, 0));
            for (const auto &item : items) {
                const char *text = item.text.c_str();
                if (!filter.IsActive() || filter.PassFilter(text)) {
                    ImGui::PushStyleColor(ImGuiCol_Text, logColors[item.level]);
                    ImGui::TextUnformatted(text);
                    ImGui::PopStyleColor();
                }
            }
            ImGui::PopStyleVar();

            // Keep up at the bottom of the scroll region if we were already at the bottom at the beginning of the frame.
            // Using a scrollbar or mouse-wheel will take away from the bottom edge.
            if (autoScroll && ImGui::GetScrollY() >= ImGui::GetScrollMaxY())
                ImGui::SetScrollHereY(1.0f);
        }
        ImGui::EndChild();
        ImGui::End();
    }
};

Logger logger;

bool *isLoggerOpen() {
    return &logger.isOpen;
}

void drawLogger() {
    logger.draw();
}

struct LoggingStringbuf : public std::stringbuf {
    Logger::LogLevel level;
    LoggingStringbuf(Logger::LogLevel level)
    : level(level) {}
    
    virtual int sync() {
        logger.addLog(level, str());
        this->str("");
        return 0;
    }
};

namespace lore {

struct ConsoleLogger : public Logger {
    struct Channel {
        std::unique_ptr<LoggingStringbuf> stringbuf;
        std::ostream stream;
        
        Channel(::Logger::LogLevel level)
        : stringbuf(std::make_unique<LoggingStringbuf>(level)),
        stream(stringbuf.get()) {
            
        }
    };
    
    Channel debug { ::Logger::LOG_DEBUG };
    Channel info { ::Logger::LOG_INFO };
    Channel warning { ::Logger::LOG_WARN };
    Channel error { ::Logger::LOG_ERROR };
    
    virtual std::ostream &log(Logger::Level level) override {
        switch (level) {
            case Logger::LOG_DEBUG:   return debug.stream << "[debug] ";
            case Logger::LOG_INFO:    return info.stream << "[info ] ";
            case Logger::LOG_WARNING: return warning.stream << "[warn ] ";
            case Logger::LOG_ERROR:   return error.stream << "[error] ";
        }
        return error.stream << "[ ??? ] ";
    }
};

std::shared_ptr<Logger> Logger::shared = std::make_shared<ConsoleLogger>();

}
