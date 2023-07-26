#include "imgui.h"

#include <logging/logging.h>
#include "console.hpp"

#include <sstream>
#include <iostream>
#include <vector>
#include <iomanip>

struct Console;
void subscribeConsoleToLogger(Console *console);

struct Console {
    struct Item {
        std::string text;
        LogLevel level;
        
        Item(LogLevel level, const std::string &text)
        : level(level), text(text) {}
    };
    
    std::vector<ImVec4> logColors;
    ImGuiTextFilter filter;
    std::vector<std::shared_ptr<Item>> items;
    ImFont *monospaceFont = nullptr;
    bool isOpen = true;
    bool autoScroll = true;

    Console() {
        autoScroll = true;
        clear();
        
        logColors.resize(4);
        logColors[LogLevelDebug] = ImVec4(0.5f, 0.5f, 0.5f, 1);
        logColors[LogLevelInfo]  = ImVec4(0.9f, 0.9f, 0.9f, 1);
        logColors[LogLevelWarn]  = ImVec4(0.9f, 0.5f, 0.2f, 1);
        logColors[LogLevelError] = ImVec4(1.0f, 0.1f, 0.1f, 1);
        
        subscribeConsoleToLogger(this);
    }

    void clear() {
        items.clear();
    }
    
    void log(LogLevel level, const char *subsystem, const char *text) {
        std::stringstream ss;
        ss << "[" << "DIWE"[level] << "] " << std::setw(8) << subsystem << ": " << text;
        items.push_back(std::make_shared<Item>(level, ss.str()));
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

            ImGui::PushFont(ImGui::GetIO().Fonts->Fonts[1]);
            ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(0, 0));
            for (const auto &item : items) {
                const char *text = item->text.c_str();
                if (!filter.IsActive() || filter.PassFilter(text)) {
                    ImGui::PushStyleColor(ImGuiCol_Text, logColors[item->level]);
                    ImGui::TextUnformatted(text);
                    ImGui::PopStyleColor();
                }
            }
            ImGui::PopStyleVar();
            ImGui::PopFont();

            // Keep up at the bottom of the scroll region if we were already at the bottom at the beginning of the frame.
            // Using a scrollbar or mouse-wheel will take away from the bottom edge.
            if (autoScroll && ImGui::GetScrollY() >= ImGui::GetScrollMaxY())
                ImGui::SetScrollHereY(1.0f);
        }
        ImGui::EndChild();
        ImGui::End();
    }
};

void loggerCallback(LogLevel level, const char *subsystem, const char *text, void *context) {
    auto console = (Console *)context;
    console->log(level, subsystem, text);
}

void subscribeConsoleToLogger(Console *console) {
    logger_subscribe(loggerCallback, console);
}

Console console;

bool *isConsoleOpen() {
    return &console.isOpen;
}

void drawConsole() {
    console.draw();
}
