//
//  normalizeImage.metal
//  raymond
//
//  Created by Alexander Rath on 04.12.22.
//

#include <metal_stdlib>
using namespace metal;

float3 tonemapHablePartial(float3 x) {
    const float hA = 0.15f;
    const float hB = 0.50f;
    const float hC = 0.10f;
    const float hD = 0.20f;
    const float hE = 0.02f;
    const float hF = 0.30f;
    return ((x*(hA*x+hC*hB)+hD*hE) / (x*(hA*x+hB)+hD*hF)) - hE/hF;
}

float3 tonemapHable(float3 x) {
    const float exposureBias = 2.0f;
    const float3 curr = tonemapHablePartial(x * exposureBias);

    const float3 W = 11.2f;
    const float3 whiteScale = 1 / tonemapHablePartial(W);
    return curr * whiteScale;
}

float3 tonemapAces(float3 x) {
    const float tA = 2.51f;
    const float tB = 0.03f;
    const float tC = 2.43f;
    const float tD = 0.59f;
    const float tE = 0.14f;
    return saturate((x*(tA*x+tB))/(x*(tC*x+tD)+tE));
}

kernel void normalizeImage(
    constant Uniforms &uniforms [[buffer(0)]],
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 coordinates [[thread_position_in_grid]]
) {
    float3 color = uniforms.exposure * input.read(coordinates).xyz / (uniforms.frameIndex + 1);
    
    switch (uniforms.tonemapping) {
    case TonemappingLinear: break;
    case TonemappingHable:
        color = tonemapHable(color);
        break;
    case TonemappingAces:
        color = tonemapAces(color);
        break;
    }
    
    output.write(float4(color, 1), coordinates);
}
