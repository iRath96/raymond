#pragma once

#include <array>
#include <algorithm>
#include <numeric>

int floatToByte(float v) {
    return std::clamp(int(v * 255), 0, 255);
}

void ui_inspect_image(int px, int py, id<MTLTexture> texture) {
    constexpr int   ZoomSize           = 4;
    constexpr float ZoomRectangleWidth = 100;
    constexpr float QuadWidth          = ZoomRectangleWidth / (ZoomSize * 2 + 1);
    static std::array<float, (2 * ZoomSize + 1) * (2 * ZoomSize + 1)> lums;

    static std::array<simd_float4, (2 * ZoomSize + 1) * (2 * ZoomSize + 1)> pixels;
    
    const int x0 = std::clamp(px - ZoomSize, 0, int(texture.width)  - 1);
    const int y0 = std::clamp(py - ZoomSize, 0, int(texture.height) - 1);
    const int x1 = std::clamp(px + ZoomSize, 0, int(texture.width)  - 1);
    const int y1 = std::clamp(py + ZoomSize, 0, int(texture.height) - 1);
    
    [texture
        getBytes:pixels.data()
        bytesPerRow:(2 * ZoomSize + 1) * sizeof(simd_float4)
        fromRegion:MTLRegionMake2D(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
        mipmapLevel:0];

    ImGui::BeginTooltip();
    ImGui::BeginGroup();
    ImDrawList *drawList = ImGui::GetWindowDrawList();

    // bitmap zoom
    ImGui::InvisibleButton("_inspector_1", ImVec2(ZoomRectangleWidth, ZoomRectangleWidth));
    const ImVec2 rectMin = ImGui::GetItemRectMin();
    //const ImVec2 rectMax = ImGui::GetItemRectMax();
    //drawList->AddRectFilled(rectMin, rectMax, IM_COL32_WHITE);

    simd_float3 centerColor;
    
    int index = 0;
    for (int y = -ZoomSize; y <= ZoomSize; y++) {
        for (int x = -ZoomSize; x <= ZoomSize; x++) {
            const bool validX = (x + px >= 0) && (x + px < int(texture.width));
            const bool validY = (y + py >= 0) && (x + py < int(texture.height));
            const simd_float3 color = validX && validY ?
                pixels[(y + py - y0) * (2 * ZoomSize + 1) + (x + px - x0)].xyz :
                simd_make_float3(0, 0, 0);
            const uint32_t texel = IM_COL32(floatToByte(color.x), floatToByte(color.y), floatToByte(color.z), 255);
            
            const ImVec2 pos = ImVec2(
                rectMin.x + float(x + ZoomSize) * QuadWidth,
                rectMin.y + float(y + ZoomSize) * QuadWidth
            );
            drawList->AddRectFilled(pos, ImVec2(pos.x + QuadWidth, pos.y + QuadWidth), texel);
            
            if (!x && !y) {
                centerColor = color;
            }
            
            lums[index++] = color.x * 0.2126f + color.y * 0.7152f + color.z * 0.0722f;
        }
    }
    ImGui::SameLine();

    std::sort(lums.begin(), lums.end());
    const float mean   = std::accumulate(lums.begin(), lums.end(), 0.0f) / (float)lums.size();
    const float median = lums[lums.size() / 2];
    const float max    = lums.back();
    const float min    = lums.front();

    // center quad
    const ImVec2 pos = ImVec2(rectMin.x + float(ZoomSize) * QuadWidth, rectMin.y + float(ZoomSize) * QuadWidth);
    drawList->AddRect(pos, ImVec2(pos.x + QuadWidth + 0.25f, pos.y + QuadWidth + 0.25f), IM_COL32_BLACK, 0.f, 15, 1.f);

    ImGui::EndGroup();
    
    ImGui::SameLine();
    
    ImGui::BeginGroup();
    ImGui::Dummy(ImVec2(0, 3));
    ImGui::PushFont(ImGui::GetIO().Fonts->Fonts[1]);
    ImGui::Text("@(%d, %d)", px, py);
    ImGui::Text("R%1.3f G%1.3f B%1.3f ", centerColor.x, centerColor.y, centerColor.z);
    ImGui::Text(
        "Max    %.3e\n"
        "Min    %.3e\n"
        "Mean   %.3e\n"
        "Median %.3e\n",
        max, min, mean, median);
    ImGui::PopFont();
    ImGui::EndGroup();
    ImGui::EndTooltip();
}
