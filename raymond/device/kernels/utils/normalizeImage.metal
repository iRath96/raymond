//
//  normalizeImage.metal
//  raymond
//
//  Created by Alexander Rath on 04.12.22.
//

#include <metal_stdlib>
using namespace metal;

float3 tonemapHable(float3 x) {
    const float hA = 0.15;
    const float hB = 0.50;
    const float hC = 0.10;
    const float hD = 0.20;
    const float hE = 0.02;
    const float hF = 0.30;
    return ((x*(hA*x+hC*hB)+hD*hE) / (x*(hA*x+hB)+hD*hF)) - hE/hF;
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
