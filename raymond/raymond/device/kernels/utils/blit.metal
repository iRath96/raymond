#include "../../../bridge/common.hpp"
#include "../../../bridge/Uniforms.hpp"

struct BlitVertexOut {
    float4 pos [[position]];
    float2 coords;
};

constant constexpr static const float4 fullscreenTrianglePositions[3] {
    { -1.0, -1.0, 0.0, 1.0 },
    {  3.0, -1.0, 0.0, 1.0 },
    { -1.0,  3.0, 0.0, 1.0 }
};

vertex BlitVertexOut blitVertex(
    uint vertexIndex [[vertex_id]]
) {
    BlitVertexOut out;
    out.pos = fullscreenTrianglePositions[vertexIndex];
    out.coords = out.pos.xy * 0.5 + 0.5;
    return out;
}

fragment float4 blitFragment(
    BlitVertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(0)]],
    texture2d<float> image [[texture(0)]]
) {
    constexpr sampler linearSampler(coord::normalized, filter::nearest);
    float4 color = uniforms.exposure * image.sample(linearSampler, in.coords) / (uniforms.frameIndex + 1);
    if (any(isnan(color))) color = float4(1, 0, 1, 1);
    return color;
}
